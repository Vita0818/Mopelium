#if canImport(SwiftUI)
import SwiftUI
import MopeliumAgent
import MopeliumCore
import MopeliumProviders
import MopeliumTools
#if canImport(AppKit)
import AppKit
#endif

struct MopeliumConfigSnapshot: Equatable, Sendable {
    var baseURLString: String
    var apiKeyEnv: String
    var apiKeyLoaded: Bool
    var model: String
    var stream: Bool
    var providerHost: String

    static let unavailable = MopeliumConfigSnapshot(
        baseURLString: CLIConfig.defaultBaseURL,
        apiKeyEnv: CLIConfig.defaultAPIKeyEnv,
        apiKeyLoaded: false,
        model: CLIConfig.defaultModel,
        stream: true,
        providerHost: "api.openai.com"
    )

    init(resolved: ResolvedCLIConfig) {
        baseURLString = resolved.baseURLString
        apiKeyEnv = resolved.apiKeyEnv
        apiKeyLoaded = resolved.apiKeyLoaded
        model = resolved.model
        stream = resolved.stream
        providerHost = resolved.baseURL.host ?? resolved.baseURLString
    }

    private init(
        baseURLString: String,
        apiKeyEnv: String,
        apiKeyLoaded: Bool,
        model: String,
        stream: Bool,
        providerHost: String
    ) {
        self.baseURLString = baseURLString
        self.apiKeyEnv = apiKeyEnv
        self.apiKeyLoaded = apiKeyLoaded
        self.model = model
        self.stream = stream
        self.providerHost = providerHost
    }

    static func load() throws -> MopeliumConfigSnapshot {
        MopeliumConfigSnapshot(resolved: try CLIConfigStore.resolve())
    }

    var responseModeLabel: String {
        stream ? "Streaming" : "Complete"
    }
}

private enum MopeliumChatRole: Equatable, Sendable {
    case user
    case assistant
    case system
}

private struct MopeliumChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    var role: MopeliumChatRole
    var text: String
    var isComplete: Bool

    init(id: UUID = UUID(), role: MopeliumChatRole, text: String, isComplete: Bool) {
        self.id = id
        self.role = role
        self.text = text
        self.isComplete = isComplete
    }
}

@MainActor
private final class MopeliumChatViewModel: ObservableObject {
    @Published private(set) var messages: [MopeliumChatMessage] = []
    @Published private(set) var config = MopeliumConfigSnapshot.unavailable
    @Published private(set) var configError: String?
    @Published private(set) var isRunning = false
    @Published var prompt = ""
    @Published var errorText: String?
    @Published var toolsEnabled = false
    @Published var allowToolWrites = false
    @Published var allowDestructiveTools = false
    @Published var allowShellTool = false
    @Published private(set) var toolWorkspaceURL: URL?

    private var activeTask: Task<Void, Never>?
    private var scopedToolURLs: [URL] = []

    deinit {
        activeTask?.cancel()
        scopedToolURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    var canSend: Bool {
        !isRunning && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refreshConfig() {
        do {
            config = try MopeliumConfigSnapshot.load()
            configError = nil
        } catch {
            configError = error.localizedDescription
        }
    }

    func chooseToolWorkspace() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.title = "Choose Mopelium Tool Workspace"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.startAccessingSecurityScopedResource() {
            scopedToolURLs.append(url)
        }
        toolWorkspaceURL = url.standardizedFileURL
        errorText = nil
        #endif
    }

    func send() {
        guard canSend else { return }
        if toolsEnabled, toolWorkspaceURL == nil {
            errorText = "Choose a tool workspace before sending with tools enabled."
            return
        }
        let userText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestMessages = historyMessages(adding: userText)
        let assistantID = UUID()
        let toolsEnabled = toolsEnabled
        let toolWorkspaceURL = toolWorkspaceURL
        let allowToolWrites = allowToolWrites
        let allowDestructiveTools = allowDestructiveTools
        let allowShellTool = allowShellTool

        prompt = ""
        errorText = nil
        isRunning = true
        messages.append(MopeliumChatMessage(role: .user, text: userText, isComplete: true))
        messages.append(MopeliumChatMessage(id: assistantID, role: .assistant, text: "", isComplete: false))

        activeTask?.cancel()
        activeTask = Task.detached(priority: .userInitiated) { [weak self, requestMessages, assistantID] in
            do {
                let resolved = try CLIConfigStore.resolve()
                let snapshot = MopeliumConfigSnapshot(resolved: resolved)
                await self?.markConfigLoaded(snapshot)

                let apiKey = try resolved.requireAPIKey()
                let provider = OpenAICompatibleProvider(baseURL: resolved.baseURL, apiKey: apiKey)
                let request = ChatRequest(
                    model: resolved.model,
                    messages: requestMessages,
                    stream: resolved.stream
                )

                if toolsEnabled, let toolWorkspaceURL {
                    let toolProvider = OpenAICompatibleToolCallingProvider(provider: provider)
                    let agent = MopeliumAgentLoop(
                        provider: toolProvider,
                        registry: .standard(),
                        workspaceRoot: toolWorkspaceURL,
                        policy: Self.toolPolicy(
                            allowWrite: allowToolWrites,
                            allowDestructive: allowDestructiveTools,
                            allowShell: allowShellTool
                        )
                    )
                    let events = agent.stream(model: request.model, messages: request.messages)
                    for try await event in events {
                        if Task.isCancelled { throw CancellationError() }
                        switch event {
                        case .textDelta(let delta):
                            await self?.appendAssistantDelta(delta, id: assistantID)
                        case .toolCall(_, let name, _):
                            await self?.appendAssistantDelta("\n\n[tool] \(name)\n", id: assistantID)
                        case .toolResult(_, let name, let observation, let changedFiles):
                            let changed = changedFiles.isEmpty ? "" : "\nchanged: \(changedFiles.joined(separator: ", "))"
                            await self?.appendAssistantDelta("[tool result] \(name): \(truncated(observation, limit: 700))\(changed)\n", id: assistantID)
                        }
                    }
                } else if resolved.stream {
                    let chunks = try await provider.stream(request: request)
                    for try await chunk in chunks {
                        if Task.isCancelled { throw CancellationError() }
                        await self?.appendAssistantDelta(chunk.content, id: assistantID)
                    }
                } else {
                    let response = try await provider.complete(request: request)
                    await self?.appendAssistantDelta(response.content, id: assistantID)
                }
                await self?.finishAssistant(id: assistantID)
            } catch is CancellationError {
                await self?.failAssistant(id: assistantID, message: "Request cancelled.")
            } catch {
                await self?.failAssistant(id: assistantID, message: error.localizedDescription)
            }
        }
    }

    nonisolated private static func toolPolicy(allowWrite: Bool,
                                               allowDestructive: Bool,
                                               allowShell: Bool) -> MopeliumAgentToolPolicy {
        var allowed: Set<SideEffect> = [.readOnly, .network, .exec]
        if allowWrite { allowed.insert(.write) }
        if allowDestructive { allowed.insert(.destructive) }
        return MopeliumAgentToolPolicy(
            allowedSideEffects: allowed,
            allowShellTool: allowShell
        )
    }

    private func historyMessages(adding userText: String) -> [ChatMessage] {
        let history = messages.compactMap { message -> ChatMessage? in
            switch message.role {
            case .user:
                return ChatMessage(role: "user", content: message.text)
            case .assistant:
                guard message.isComplete, !message.text.isEmpty else { return nil }
                return ChatMessage(role: "assistant", content: message.text)
            case .system:
                return nil
            }
        }
        return history + [ChatMessage(role: "user", content: userText)]
    }

    private func markConfigLoaded(_ snapshot: MopeliumConfigSnapshot) {
        config = snapshot
        configError = nil
    }

    private func appendAssistantDelta(_ delta: String, id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += delta
    }

    private func finishAssistant(id: UUID) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            if messages[index].text.isEmpty {
                messages[index].text = "No content returned."
            }
            messages[index].isComplete = true
        }
        isRunning = false
        activeTask = nil
    }

    private func failAssistant(id: UUID, message: String) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].role = .system
            messages[index].text = message
            messages[index].isComplete = true
        } else {
            messages.append(MopeliumChatMessage(role: .system, text: message, isComplete: true))
        }
        errorText = message
        isRunning = false
        activeTask = nil
    }
}

struct MopeliumChatScreen: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var model = MopeliumChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            MopeliumPageHeader(
                title: "Chat",
                subtitle: "\(model.config.model) · \(model.config.providerHost) · \(model.config.responseModeLabel)"
            ) {
                HStack(spacing: 8) {
                    MopeliumStatusBadge(
                        status: model.config.apiKeyLoaded ? .enabled : .failed,
                        label: model.config.apiKeyLoaded ? "Key Loaded" : "Key Missing"
                    )
                    MopeliumStatusBadge(status: model.isRunning ? .running : .local, label: "Local v0.4")
                }
                .padding(.top, 3)
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 14)

            if let configError = model.configError {
                InlineNotice(text: configError, status: .failed)
                    .frame(maxWidth: 900)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 8)
            } else if let errorText = model.errorText {
                InlineNotice(text: errorText, status: .failed)
                    .frame(maxWidth: 900)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 8)
            }

            ChatToolControls(model: model)
                .frame(maxWidth: 900)
                .padding(.horizontal, 30)
                .padding(.bottom, 8)

            messages

            MopeliumComposer(
                text: $model.prompt,
                placeholder: "Message Mopelium...",
                isBusy: model.isRunning,
                onSubmit: model.send
            )
            .frame(maxWidth: 900)
            .padding(.horizontal, 30)
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .task {
            model.refreshConfig()
        }
    }

    @ViewBuilder private var messages: some View {
        if model.messages.isEmpty {
            ChatEmptyState(config: model.config)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.messages) { message in
                            MopeliumMessageBubble(message: message)
                                .id(message.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 16)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: model.messages) { _ in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct ChatEmptyState: View {
    let config: MopeliumConfigSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 13) {
            Spacer()
            MopeliumIconBadge(systemName: "sparkles", status: config.apiKeyLoaded ? .enabled : .failed)
                .frame(width: 58, height: 58)
            Text(config.apiKeyLoaded ? "Ask anything" : "Connect your API key")
                .font(MopeliumType.title(22))
                .foregroundStyle(MopeliumTheme.primaryText(scheme))
            Text(emptyMessage)
                .font(MopeliumType.body(14))
                .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if config.apiKeyLoaded {
            return "Mopelium will keep this window's conversation in memory and can call enabled workspace tools."
        }
        return "Set \(config.apiKeyEnv) in the launch environment, or change api_key_env with the CLI config command."
    }
}

private struct ChatToolControls: View {
    @ObservedObject var model: MopeliumChatViewModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Toggle("Tools", isOn: $model.toolsEnabled)
                    .toggleStyle(.switch)
                    .font(MopeliumType.caption(12, .semibold))
                    .disabled(model.isRunning)

                Button {
                    model.chooseToolWorkspace()
                } label: {
                    Label("Workspace", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isRunning)

                Text(model.toolWorkspaceURL?.path ?? "No workspace")
                    .font(MopeliumType.mono(11))
                    .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)

                MopeliumStatusBadge(
                    status: model.toolsEnabled ? (model.toolWorkspaceURL == nil ? .queued : .enabled) : .disabled,
                    label: model.toolsEnabled ? "AI Tools" : "Tools Off"
                )
            }

            if model.toolsEnabled {
                HStack(spacing: 14) {
                    Toggle("Write", isOn: $model.allowToolWrites)
                    Toggle("Destructive", isOn: $model.allowDestructiveTools)
                    Toggle("Shell", isOn: $model.allowShellTool)
                    Spacer(minLength: 0)
                }
                .toggleStyle(.checkbox)
                .font(MopeliumType.caption(11, .medium))
                .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                .disabled(model.isRunning)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MopeliumTheme.surface(scheme).opacity(scheme == .dark ? 0.26 : 0.64))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MopeliumTheme.stroke(scheme).opacity(0.70), lineWidth: 1)
                }
        }
    }
}

private struct MopeliumMessageBubble: View {
    let message: MopeliumChatMessage
    @Environment(\.colorScheme) private var scheme

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: 72) }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(roleLabel)
                        .font(MopeliumType.caption(10, .semibold))
                        .foregroundStyle(roleColor)
                    if !message.isComplete {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(displayText)
                    .font(MopeliumType.body(15))
                    .foregroundStyle(MopeliumTheme.primaryText(scheme))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background { bubbleBackground }
            .frame(maxWidth: 620, alignment: .leading)

            if !isUser { Spacer(minLength: 72) }
        }
    }

    private var displayText: String {
        message.text.isEmpty && !message.isComplete ? "..." : message.text
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "YOU"
        case .assistant: return "MOPELIUM"
        case .system: return "SYSTEM"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user:
            return MopeliumTheme.accentDeep
        case .assistant:
            return MopeliumTheme.tertiaryText(scheme)
        case .system:
            return MopeliumTheme.statusFailed
        }
    }

    @ViewBuilder private var bubbleBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        switch message.role {
        case .user:
            shape
                .fill(MopeliumTheme.accentSoft.opacity(scheme == .dark ? 0.18 : 0.44))
                .overlay { shape.stroke(MopeliumTheme.accent.opacity(0.32), lineWidth: 1) }
        case .assistant:
            shape
                .fill(MopeliumTheme.surface(scheme).opacity(scheme == .dark ? 0.30 : 0.70))
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.stroke(MopeliumTheme.stroke(scheme).opacity(0.78), lineWidth: 1) }
        case .system:
            shape
                .fill(MopeliumTheme.statusFill(.failed, scheme))
                .overlay { shape.stroke(MopeliumTheme.statusStroke(.failed, scheme), lineWidth: 1) }
        }
    }
}

private struct InlineNotice: View {
    let text: String
    let status: MopeliumStatus
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: status == .failed ? "exclamationmark.triangle" : "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MopeliumTheme.statusColor(status))
                .frame(width: 18)
            Text(text)
                .font(MopeliumType.caption(12, .medium))
                .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MopeliumTheme.statusFill(status, scheme))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MopeliumTheme.statusStroke(status, scheme), lineWidth: 1)
                }
        }
    }
}

#if DEBUG
struct MopeliumChatScreen_Previews: PreviewProvider {
    static var previews: some View {
        MopeliumChatScreen()
            .frame(width: 900, height: 700)
    }
}
#endif
#endif
