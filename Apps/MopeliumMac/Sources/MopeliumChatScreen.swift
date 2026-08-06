//
//  MopeliumChatScreen.swift
//  MopeliumMac
//
//  The macOS Chat surface follows the native window material. Content uses
//  semantic system Material, while the custom composer and controls adopt
//  Liquid Glass on current systems.
//

#if canImport(SwiftUI)
import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import MopeliumCore
import MopeliumProtocol
import MopeliumProviders
import MopeliumConversation
import MopeliumSharedUI

struct MopeliumMacScreenLayout {
    let rawWidth: CGFloat

    private var width: CGFloat { max(rawWidth, 1) }
    private var threadLayout: MopeliumThreadContentLayout {
        MopeliumThreadContentLayout(rawWidth: rawWidth, contentMaxWidth: 900, messageMaxWidth: 560)
    }

    var isCompact: Bool { width < 700 }

    var horizontalPadding: CGFloat {
        if width < 380 { return 10 }
        if width < 500 { return 14 }
        if width < 760 { return 20 }
        return 30
    }

    var contentMaxWidth: CGFloat { 900 }
    var contentWidth: CGFloat { threadLayout.contentWidth }
    var settingsMaxWidth: CGFloat { 960 }
    var settingsCardMaxWidth: CGFloat { 820 }
    var settingsUsesColumns: Bool { width >= 760 }

    var providerListWidth: CGFloat {
        min(220, max(176, width * 0.30))
    }

    var messageMaxWidth: CGFloat {
        threadLayout.messageMaxWidth
    }

    var messageGutter: CGFloat {
        threadLayout.messageGutter
    }
}

struct MopeliumChatScreen: View {
    @ObservedObject var env: AppEnvironment
    let sessionTitle: String

    var body: some View {
        MopeliumChatSessionScreen(
            env: env,
            model: env.viewModel,
            sessionTitle: sessionTitle)
            .id(env.chatSessionID.rawValue)
    }
}

private struct MopeliumChatSessionScreen: View {
    @ObservedObject var env: AppEnvironment
    @ObservedObject var model: ChatViewModel
    let sessionTitle: String
    @Environment(\.colorScheme) private var scheme
    private static let bottomAnchorID = "mopelium-chat-thread-bottom"

    var body: some View {
        GeometryReader { proxy in
            content(layout: MopeliumMacScreenLayout(rawWidth: proxy.size.width))
        }
    }

    private func content(layout: MopeliumMacScreenLayout) -> some View {
        VStack(spacing: 0) {
            header(layout: layout)

            messages(layout: layout)

            errorText(layout: layout)

            if !model.artifactProgress.isEmpty {
                MopeliumArtifactProgressStrip(progress: model.artifactProgress)
                    .frame(maxWidth: layout.contentMaxWidth)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.top, 8)
            }

            MopeliumComposer(model: model,
                            catalog: env.providerCatalog,
                            onSelectModel: env.selectProviderModel(providerID:modelID:variantID:))
                .frame(maxWidth: layout.contentMaxWidth)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(layout: MopeliumMacScreenLayout) -> some View {
        MopeliumPageHeader(title: sessionTitle, subtitle: subtitle)
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, 24)
        .padding(.bottom, 10)
    }

    private var subtitle: String {
        let catalog = env.providerCatalog
        let provider = catalog.selectedProvider
        let model = catalog.selectedModel
        let host = provider.flatMap { URL(string: $0.baseURL)?.host } ?? provider?.baseURL ?? AppConfig.defaultBaseURL
        return "\(model?.title ?? AppConfig.defaultDisplayName(for: AppConfig.defaultModel)) · \(provider?.title ?? "OpenAI") · \(host)"
    }

    @ViewBuilder private func errorText(layout: MopeliumMacScreenLayout) -> some View {
        if let err = env.chatSessionError ?? model.errorText {
            Text(err)
                .font(MopeliumType.caption(12))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, layout.horizontalPadding)
        }
    }

    @ViewBuilder private func messages(layout: MopeliumMacScreenLayout) -> some View {
        if model.messages.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    MopeliumAdaptiveThreadStack(
                        visibleRowCount: model.messages.count
                            + ((model.isStreaming && model.messages.last?.role == .user) ? 1 : 0),
                        spacing: 14) {
                        ForEach(model.messages) { msg in
                            MopeliumMessageBubble(message: msg,
                                                 rowWidth: layout.contentWidth,
                                                 maxWidth: layout.messageMaxWidth,
                                                 gutter: layout.messageGutter)
                                .id(msg.id)
                        }
                        if model.isStreaming, model.messages.last?.role == .user {
                            thinkingRow(layout: layout)
                                .id("mopelium-chat-thinking-\(chatThinkingPhaseID)")
                        }
                        Color.clear
                            .frame(height: 1)
                            .padding(.bottom, 16)
                            .id(Self.bottomAnchorID)
                    }
                    .frame(width: layout.contentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.top, 16)
                }
                .scrollContentBackground(.hidden)
                .onAppear {
                    scrollToBottom(proxy, animated: false)
                }
                .onChange(of: chatScrollSignature) { _ in
                    scrollToBottom(proxy)
                }
            }
        }
    }

    private var chatScrollSignature: String {
        guard let last = model.messages.last else { return "0" }
        return [
            "\(model.messages.count)",
            last.id.rawValue,
            "\(last.text.count)",
            "\(last.isComplete)",
            "\(model.isStreaming)"
        ].joined(separator: ":")
    }

    private var chatThinkingPhaseID: String {
        [
            env.chatSessionID.rawValue,
            model.messages.last?.id.rawValue ?? "initial"
        ].joined(separator: ":")
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkle")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(MopeliumTheme.accent(scheme))
            .frame(width: 76, height: 76)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func thinkingRow(layout: MopeliumMacScreenLayout) -> some View {
        MopeliumThreadBubbleRow(isTrailing: false,
                               fillsAvailableWidth: true,
                               rowWidth: layout.contentWidth,
                               maxWidth: layout.messageMaxWidth,
                               gutter: layout.messageGutter) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                MopeliumThinkingElapsedLabel(phaseID: chatThinkingPhaseID)
                    .font(MopeliumType.caption(12))
                    .foregroundStyle(MopeliumTheme.softText(scheme))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
    }
}

struct MopeliumChatModelMenu: View {
    let catalog: AppProviderCatalog
    let isBusy: Bool
    let isCompact: Bool
    var usesGlassButton: Bool = true
    var help: String = MopeliumLocalization.string("Switch model")
    let onSelect: (String, String, String?) -> Void
    @Environment(\.colorScheme) private var scheme

    private var selectedModel: AppProviderModel? { catalog.selectedModel }
    private var menuProviders: [ProviderModelMenuProvider] {
        catalog.providers.map { provider in
            ProviderModelMenuProvider(
                id: provider.id,
                title: provider.title,
                models: provider.models.flatMap { model in
                    let base = ProviderModelMenuModel(
                        id: model.id,
                        modelID: model.id,
                        variantID: nil,
                        title: model.title,
                        detail: model.reasoningLabel)
                    let variants = model.variants.map { variant in
                        ProviderModelMenuModel(
                            id: variantMenuID(modelID: model.id, variantID: variant.id),
                            modelID: model.id,
                            variantID: variant.id,
                            title: model.title,
                            detail: variantMenuDetail(variant))
                    }
                    return [base] + variants
                })
        }
    }

    @ViewBuilder var body: some View {
        if usesGlassButton {
            selectionMenu
                .mopeliumComposerSelectionMenu()
        } else {
            selectionMenu
                .buttonStyle(.borderless)
        }
    }

    private var selectionMenu: some View {
        ProviderModelSelectionMenu(
            providers: menuProviders,
            selectedProviderID: catalog.selectedProviderID,
            selectedModelID: catalog.selectedModelID,
            selectedVariantID: catalog.selectedVariantID,
            isBusy: isBusy,
            onSelect: onSelect) {
                label
        }
        .help(isBusy
            ? MopeliumLocalization.string("Model changes apply after the current response finishes")
            : help)
    }

    @ViewBuilder private var label: some View {
        if usesGlassButton && isCompact {
            labelContent
                .mopeliumComposerSelectionLabel()
        } else if usesGlassButton {
            labelContent
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .mopeliumLiquidGlass(cornerRadius: 16, interactive: true)
        } else {
            labelContent
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .frame(
                    maxWidth: MopeliumComposerControlMetrics.selectionMaxWidth,
                    alignment: .leading)
        }
    }

    private var labelContent: some View {
        HStack(spacing: 8) {
            Text(selectedModel?.title ?? AppConfig.defaultDisplayName(for: AppConfig.defaultModel))
                .font(MopeliumType.body(13, .semibold))
                .foregroundStyle(MopeliumTheme.deepText(scheme))
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
        }
        .frame(
            minWidth: isCompact || !usesGlassButton ? 0 : 190,
            maxWidth: usesGlassButton
                ? (isCompact ? nil : 260)
                : MopeliumComposerControlMetrics.selectionMaxWidth,
            alignment: .leading)
    }

    private func variantMenuID(modelID: String, variantID: String) -> String {
        "\(modelID.utf8.count):\(modelID)\(variantID)"
    }

    private func variantMenuDetail(_ variant: AppProviderModelVariant) -> String {
        guard let reasoning = variant.reasoningLabel,
              reasoning.caseInsensitiveCompare(variant.id) != .orderedSame else {
            return variant.reasoningLabel ?? variant.id
        }
        return "\(variant.id) · \(reasoning)"
    }
}

struct MopeliumArtifactProgressStrip: View {
    let progress: [ArtifactProgressSnapshot]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(progress) { item in
                HStack(spacing: 10) {
                    ProgressView(value: min(max(item.progress, 0), 1))
                        .frame(width: 120)
                    Text(localizedState(item.state))
                        .font(MopeliumType.caption(12, .semibold))
                        .foregroundStyle(MopeliumTheme.deepText(scheme))
                    Spacer(minLength: 8)
                    Text("\(Int(min(max(item.progress, 0), 1) * 100))%")
                        .font(MopeliumType.caption(12))
                        .foregroundStyle(MopeliumTheme.softText(scheme))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .mopeliumCard(cornerRadius: 14)
    }

    private func localizedState(_ state: String) -> String {
        switch state.lowercased() {
        case "queued": return MopeliumLocalization.string("queued")
        case "running": return MopeliumLocalization.string("running")
        case "completed": return MopeliumLocalization.string("completed")
        case "failed": return MopeliumLocalization.string("failed")
        case "cancelled": return MopeliumLocalization.string("cancelled")
        default: return state
        }
    }
}

// MARK: - Message bubble

struct MopeliumMessageBubble: View {
    let message: ChatMessageView
    let rowWidth: CGFloat
    let maxWidth: CGFloat
    let gutter: CGFloat
    @Environment(\.colorScheme) private var scheme

    private var isUser: Bool { message.role == .user }

    private var isUninterruptedAgentReply: Bool {
        (message.role == .assistant || message.role == .agent)
            && message.recoveryAdvice == nil
    }

    private var roleLabel: String {
        switch message.role {
        case .user:      return MopeliumLocalization.string("You")
        case .assistant: return "Mopelium"
        case .agent:     return message.agent?.rawValue ?? "Mopelium"
        case .system:    return MopeliumLocalization.string("System")
        }
    }

    private var displayText: String {
        (message.text.isEmpty && !message.isComplete) ? "…" : message.text
    }

    var body: some View {
        MopeliumThreadBubbleRow(
            isTrailing: isUser,
            fillsAvailableWidth: message.role == .assistant || message.role == .agent,
            rowWidth: rowWidth,
            maxWidth: maxWidth,
            gutter: gutter) {
            bubble
        }
    }

    @ViewBuilder private var bubble: some View {
        if isUninterruptedAgentReply {
            bubbleBody
                .padding(.vertical, 8)
        } else {
            bubbleBody
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .mopeliumContentSurface(cornerRadius: 16)
                .overlay { userSelectionStroke }
        }
    }

    private var bubbleBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(roleLabel)
                    .font(MopeliumType.caption(10, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(isUser ? MopeliumTheme.accent(scheme) : MopeliumTheme.tertiaryText(scheme))
                if (message.role == .assistant || message.role == .agent),
                   let timestamp = message.timestamp {
                    Text(MopeliumMessageTimestampPresentation.string(for: timestamp))
                        .font(MopeliumType.caption(10))
                        .monospacedDigit()
                        .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
                }
                ForEach(message.tags, id: \.self) { tag in
                    goalTag(tag)
                }
            }
            if message.role == .assistant || message.role == .agent {
                MopeliumMessageContentView(
                    messageID: message.id.rawValue,
                    rawText: message.text,
                    isComplete: message.isComplete,
                    policy: .richText,
                    style: .mopeliumMac(scheme))
            } else {
                Text(displayText)
                    .font(MopeliumType.chat(15))
                    .foregroundStyle(MopeliumTheme.deepText(scheme))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var userSelectionStroke: some View {
        if isUser {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MopeliumTheme.selectedStroke(scheme), lineWidth: 1)
        }
    }

    private func goalTag(_ tag: String) -> some View {
        Text(tag.uppercased())
            .font(MopeliumType.caption(10, .semibold))
            .foregroundStyle(MopeliumTheme.accent(scheme))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay {
                Capsule().stroke(MopeliumTheme.separator(scheme), lineWidth: 1)
            }
    }
}

// MARK: - Composer

struct MopeliumComposer: View {
    @ObservedObject var model: ChatViewModel
    let catalog: AppProviderCatalog
    let onSelectModel: (String, String, String?) -> Void
    @Environment(\.colorScheme) private var scheme

    private var canSend: Bool {
        !model.isBusy && !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        MopeliumThreadComposer(
            placeholder: MopeliumLocalization.string("Message Mopelium..."),
            input: $model.input,
            canSend: canSend,
            isInputDisabled: model.isBusy,
            style: .mopeliumMac(scheme),
            secondaryAction: MopeliumThreadComposerSecondaryAction(
                systemImage: "photo",
                help: MopeliumLocalization.string("Generate image from prompt"),
                isBusy: model.isGeneratingArtifact,
                isDisabled: !canSend,
                action: { model.generateImage() }),
            leadingAccessory: AnyView(MopeliumComposerModelControl(
                catalog: catalog,
                isBusy: model.isBusy,
                onSelectModel: onSelectModel)),
            stopAction: model.isBusy
                ? MopeliumThreadComposerSecondaryAction(
                    systemImage: "stop.fill",
                    help: MopeliumLocalization.string("Stop"),
                    action: { model.cancelCurrentOperation() })
                : nil,
            accessory: {
                MopeliumComposerUsageStrip(
                    stats: model.latestTurnStats,
                    style: .mopeliumMac(scheme))
            },
            onSend: { model.send() })
    }
}

struct MopeliumComposerModelControl: View {
    let catalog: AppProviderCatalog
    let isBusy: Bool
    let onSelectModel: (String, String, String?) -> Void

    var body: some View {
        MopeliumChatModelMenu(
            catalog: catalog,
            isBusy: isBusy,
            isCompact: true,
            usesGlassButton: true,
            help: MopeliumLocalization.string("Switch model"),
            onSelect: onSelectModel)
    }
}

// MARK: - Settings panel

struct MopeliumSettingsPanel: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.colorScheme) private var scheme
    @State private var catalog = AppConfig.providerCatalog
    @State private var apiKeyEnvironmentNamesByProviderID: [String: String] = [:]
    @State private var saved = false
    @State private var settingsError: String?
    @State private var isTestingProvider = false
    @State private var providerHealthReports: [ProviderHealthReport] = []
    @State private var showThirdPartyNotices = false
    @AppStorage(MopeliumMessageRendererMode.defaultsKey)
    private var rendererModeRawValue = MopeliumMessageRendererMode.microsoft.rawValue

    var body: some View {
        GeometryReader { proxy in
            settingsContent(layout: MopeliumMacScreenLayout(rawWidth: proxy.size.width))
        }
        .sheet(isPresented: $showThirdPartyNotices) {
            NavigationStack {
                MopeliumThirdPartyNoticesView()
                    .navigationTitle("Open-source notices")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showThirdPartyNotices = false }
                        }
                    }
            }
            .frame(minWidth: 680, minHeight: 560)
        }
    }

    private func settingsContent(layout: MopeliumMacScreenLayout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MopeliumPageHeader(
                    title: MopeliumLocalization.string("Settings"),
                    subtitle: MopeliumLocalization.string(
                        "Providers · models · API key environments"))

                settingsCard(layout: layout)

                messageRenderingCard
                    .frame(maxWidth: layout.settingsCardMaxWidth, alignment: .leading)

                Text(settingsStorageNote)
                    .font(MopeliumType.caption(12, .regular))
                    .foregroundStyle(MopeliumTheme.softText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: layout.settingsCardMaxWidth, alignment: .leading)

                if let settingsError {
                    Text(settingsError)
                        .font(MopeliumType.caption(12, .regular))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: layout.settingsCardMaxWidth, alignment: .leading)
                }

                providerHealthSummary
                    .frame(maxWidth: layout.settingsCardMaxWidth, alignment: .leading)

                settingsActions(layout: layout)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, 26)
            .padding(.bottom, 30)
            .frame(maxWidth: layout.settingsMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
    }

    private var messageRenderingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Message rendering")
                .font(MopeliumType.body(14, .semibold))
            Picker("Message rendering", selection: rendererModeSelection) {
                Text("Rich Markdown").tag(MopeliumMessageRendererMode.microsoft.rawValue)
                Text("Plain text safe mode").tag(MopeliumMessageRendererMode.plainSafe.rawValue)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("settings.message-renderer-mode")
            Text(rendererModeHelpText)
                .font(MopeliumType.caption(12, .regular))
                .foregroundStyle(MopeliumTheme.softText(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Divider().opacity(0.45)
            Button {
                showThirdPartyNotices = true
            } label: {
                Label("Open-source notices", systemImage: "doc.text")
            }
            .buttonStyle(.plain)
            .foregroundStyle(MopeliumTheme.accent(scheme))
            .accessibilityIdentifier("settings.open-source-notices")
        }
        .padding(18)
        .mopeliumCard(cornerRadius: 20)
    }

    private var rendererLaunchOverride: MopeliumMessageRendererMode? {
        MopeliumMessageRendererMode.launchOverride()
    }

    /// The Phase 0 renderer stored `rich`. Render routing already migrates that
    /// value to Microsoft; normalize the Picker view as well so an upgraded
    /// user never sees an empty segmented selection.
    private var rendererModeSelection: Binding<String> {
        Binding(
            get: {
                MopeliumMessageRendererMode.resolve(
                    persistedRawValue: rendererModeRawValue,
                    arguments: []).rawValue
            },
            set: { rendererModeRawValue = $0 })
    }

    private var rendererModeHelpText: String {
        if let rendererLaunchOverride {
            let label = rendererLaunchOverride == .plainSafe
                ? MopeliumLocalization.string("Plain text safe mode")
                : MopeliumLocalization.string("Rich Markdown")
            return MopeliumLocalization.format(
                "Current launch is forced to %@. This picker is saved immediately for the next launch without an override, so a rescued session can remain in safe mode.",
                label)
        }
        return MopeliumLocalization.string(
            "This choice is saved and applied immediately; it is independent of provider Save. Rich Markdown uses the audited upstream renderer with images, math typesetting, and syntax highlighting disabled for the first release. Plain text safe mode bypasses Markdown entirely. Raw session data is unchanged.")
    }

    @ViewBuilder private func settingsCard(layout: MopeliumMacScreenLayout) -> some View {
        if layout.settingsUsesColumns {
            HStack(alignment: .top, spacing: 18) {
                providerList
                    .frame(width: layout.providerListWidth, alignment: .topLeading)
                Divider().opacity(0.45)
                providerDetail(layout: layout)
            }
            .padding(22)
            .mopeliumCard(cornerRadius: 24)
            .frame(maxWidth: layout.settingsCardMaxWidth, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                providerList
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Divider().opacity(0.45)
                providerDetail(layout: layout)
            }
            .padding(18)
            .mopeliumCard(cornerRadius: 20)
            .frame(maxWidth: layout.settingsCardMaxWidth, alignment: .leading)
        }
    }

    @ViewBuilder private func settingsActions(layout: MopeliumMacScreenLayout) -> some View {
        if layout.isCompact {
            VStack(alignment: .trailing, spacing: 10) {
                savedLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Spacer(minLength: 0)
                    openJSONButton
                    testProviderButton(layout: layout)
                    saveButton
                }
            }
            .frame(maxWidth: layout.settingsCardMaxWidth)
        } else {
            HStack {
                savedLabel
                Spacer()
                openJSONButton
                testProviderButton(layout: layout)
                saveButton
            }
            .frame(maxWidth: layout.settingsCardMaxWidth)
        }
    }

    @ViewBuilder private var savedLabel: some View {
        if saved {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(MopeliumType.caption(12, .semibold))
                .foregroundStyle(.green)
        }
    }

    private var openJSONButton: some View {
        Button(action: openJSONConfig) {
            Label("Open Mopelium Config", systemImage: "curlybraces")
                .font(MopeliumType.body(14, .semibold))
                .foregroundStyle(.primary)
        }
        .mopeliumGlassButton()
        .help("Open the Mopelium provider config")
    }

    private func testProviderButton(layout: MopeliumMacScreenLayout) -> some View {
        Button(action: testProvider) {
            Label(isTestingProvider
                    ? MopeliumLocalization.string("Testing")
                    : MopeliumLocalization.string(layout.isCompact ? "Test" : "Test Provider"),
                  systemImage: isTestingProvider ? "hourglass" : "checkmark.seal")
                .font(MopeliumType.body(14, .semibold))
                .foregroundStyle(.primary)
        }
        .mopeliumGlassButton()
        .disabled(isTestingProvider)
        .help("Save current settings and run a small model health check")
    }

    private var saveButton: some View {
        Button(action: save) {
            Text("Save")
                .font(MopeliumType.body(14, .semibold))
                .foregroundStyle(.primary)
        }
        .mopeliumGlassButton(prominent: true)
    }

    @ViewBuilder private var providerHealthSummary: some View {
        if isTestingProvider {
            Label("Testing provider…", systemImage: "hourglass")
                .font(MopeliumType.caption(12, .semibold))
                .foregroundStyle(MopeliumTheme.softText(scheme))
        } else if !providerHealthReports.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(providerHealthReports.enumerated()), id: \.offset) { _, report in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(MopeliumLocalization.string(report.displayTitle),
                              systemImage: report.isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(MopeliumType.caption(12, .semibold))
                            .foregroundStyle(report.isOK ? .green : .red)
                        Text(MopeliumLocalization.providerHealthSummary(report))
                            .font(MopeliumType.caption(11, .medium))
                            .foregroundStyle(MopeliumTheme.softText(scheme))
                            .lineLimit(2)
                        Text(MopeliumLocalization.providerHealthDetail(report))
                            .font(MopeliumType.caption(11, .regular))
                            .foregroundStyle(MopeliumTheme.softText(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Providers")
                    .font(MopeliumType.caption(12, .semibold))
                    .foregroundStyle(MopeliumTheme.softText(scheme))
                Spacer()
                Button(action: addProvider) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Add provider")
            }

            VStack(spacing: 8) {
                ForEach(catalog.providers) { provider in
                    providerRow(provider)
                }
            }
        }
    }

    private func providerDetail(layout: MopeliumMacScreenLayout) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let providerIndex = selectedProviderIndex {
                field("Provider name",
                      text: providerFieldBinding(providerIndex, \.displayName),
                      placeholder: "OpenAI")
                field("Base URL",
                      text: baseURLBinding(providerIndex),
                      placeholder: AppConfig.defaultBaseURL)
                field("Chat endpoint",
                      text: chatEndpointBinding(providerIndex),
                      placeholder: AppConfig.defaultChatEndpoint)
                field("API key environment variable",
                      text: apiKeyEnvironmentBinding(
                          for: catalog.providers[providerIndex]),
                      placeholder: AppConfig.defaultAPIKeyEnvironmentName())
                Text(MopeliumLocalization.format(
                    "Credential status: %@",
                    apiKeyStatusLabel(for: catalog.providers[providerIndex])))
                    .font(MopeliumType.caption(11, .medium))
                    .foregroundStyle(MopeliumTheme.softText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                activeModelPicker(providerIndex: providerIndex, layout: layout)
                modelList(providerIndex: providerIndex, layout: layout)
            } else {
                Text("Add a provider to configure models.")
                    .font(MopeliumType.body(14))
                    .foregroundStyle(MopeliumTheme.softText(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerRow(_ provider: AppProviderSettings) -> some View {
        let selected = provider.id == catalog.selectedProviderID
        return Button {
            selectProvider(provider)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected ? MopeliumTheme.accent(scheme) : MopeliumTheme.tertiaryText(scheme))
                    Text(provider.title)
                        .font(MopeliumType.body(13, .semibold))
                        .foregroundStyle(MopeliumTheme.deepText(scheme))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(providerSubtitle(provider))
                    .font(MopeliumType.caption(11))
                    .foregroundStyle(MopeliumTheme.softText(scheme))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(selected ? MopeliumTheme.selectedStroke(scheme) : MopeliumTheme.separator(scheme),
                            lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func activeModelPicker(providerIndex: Int, layout: MopeliumMacScreenLayout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Active model")
                .font(MopeliumType.caption(12, .semibold))
                .foregroundStyle(MopeliumTheme.softText(scheme))
            Picker("", selection: $catalog.selectedModelID) {
                ForEach(catalog.providers[providerIndex].models) { model in
                    MopeliumModelTitleLabel(model: model).tag(model.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: layout.settingsUsesColumns ? 280 : .infinity, alignment: .leading)
        }
    }

    private func modelList(providerIndex: Int, layout: MopeliumMacScreenLayout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Models")
                    .font(MopeliumType.caption(12, .semibold))
                    .foregroundStyle(MopeliumTheme.softText(scheme))
                Spacer()
                Button(action: { addModel(providerIndex: providerIndex) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Add model")
            }

            ForEach(Array(catalog.providers[providerIndex].models.indices), id: \.self) { modelIndex in
                modelEditorRow(providerIndex: providerIndex,
                               modelIndex: modelIndex,
                               layout: layout)
            }

            HStack {
                Spacer()
                Button(action: { removeProvider(providerIndex) }) {
                    Label("Delete provider", systemImage: "trash")
                        .font(MopeliumType.caption(12, .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(catalog.providers.count == 1)
            }
        }
    }

    @ViewBuilder private func modelEditorRow(providerIndex: Int,
                                             modelIndex: Int,
                                             layout: MopeliumMacScreenLayout) -> some View {
        if layout.settingsUsesColumns {
            HStack(spacing: 8) {
                modelIDField(providerIndex: providerIndex, modelIndex: modelIndex)
                modelDisplayNameField(providerIndex: providerIndex, modelIndex: modelIndex)
                removeModelButton(providerIndex: providerIndex, modelIndex: modelIndex)
                    .padding(.top, 20)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                modelIDField(providerIndex: providerIndex, modelIndex: modelIndex)
                modelDisplayNameField(providerIndex: providerIndex, modelIndex: modelIndex)
                HStack {
                    Spacer()
                    removeModelButton(providerIndex: providerIndex, modelIndex: modelIndex)
                }
            }
        }
    }

    private func modelIDField(providerIndex: Int, modelIndex: Int) -> some View {
        field("Model ID",
              text: modelFieldBinding(providerIndex: providerIndex,
                                      modelIndex: modelIndex,
                                      keyPath: \.id),
              placeholder: AppConfig.defaultModel)
    }

    private func modelDisplayNameField(providerIndex: Int, modelIndex: Int) -> some View {
        field("Display name",
              text: modelFieldBinding(providerIndex: providerIndex,
                                      modelIndex: modelIndex,
                                      keyPath: \.displayName),
              placeholder: "GPT-4o mini")
    }

    private func removeModelButton(providerIndex: Int, modelIndex: Int) -> some View {
        Button(action: { removeModel(providerIndex: providerIndex, modelIndex: modelIndex) }) {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
        }
        .buttonStyle(.plain)
        .disabled(catalog.providers[providerIndex].models.count == 1)
        .help("Remove model")
    }

    private func save() {
        do {
            try env.saveSettings(
                catalog: catalog,
                apiKeyEnvironmentNamesByProviderID: apiKeyEnvironmentNamesByProviderID)
            catalog = AppConfig.providerCatalog
            apiKeyEnvironmentNamesByProviderID = [:]
            settingsError = nil
            providerHealthReports = []
            withAnimation { saved = true }
        } catch {
            saved = false
            settingsError = MopeliumLocalization.format(
                "Could not save settings: %@",
                error.localizedDescription)
        }
    }

    private func openJSONConfig() {
        do {
            let url = try AppConfig.prepareEditableConfigFile()
            catalog = AppConfig.providerCatalog
            settingsError = nil
            providerHealthReports = []
            saved = false
            #if canImport(AppKit)
            if !NSWorkspace.shared.open(url) {
                settingsError = MopeliumLocalization.format(
                    "Could not open JSON config at %@",
                    url.path)
            }
            #else
            settingsError = MopeliumLocalization.string(
                "Opening JSON config is not available on this platform.")
            #endif
        } catch {
            saved = false
            settingsError = MopeliumLocalization.format(
                "Could not open JSON config: %@",
                error.localizedDescription)
        }
    }

    private func testProvider() {
        guard !isTestingProvider else { return }
        isTestingProvider = true
        settingsError = nil
        providerHealthReports = []
        Task { @MainActor in
            defer { isTestingProvider = false }
            do {
                try env.saveSettings(
                    catalog: catalog,
                    apiKeyEnvironmentNamesByProviderID: apiKeyEnvironmentNamesByProviderID)
                catalog = AppConfig.providerCatalog
                apiKeyEnvironmentNamesByProviderID = [:]
                withAnimation { saved = true }
                providerHealthReports = await env.healthCheckSelectedProvider()
            } catch {
                saved = false
                settingsError = MopeliumLocalization.format(
                    "Could not test provider: %@",
                    error.localizedDescription)
            }
        }
    }

    private var selectedProviderIndex: Int? {
        catalog.providers.firstIndex { $0.id == catalog.selectedProviderID } ?? catalog.providers.indices.first
    }

    private func selectProvider(_ provider: AppProviderSettings) {
        catalog.selectedProviderID = provider.id
        if !provider.models.contains(where: { $0.id == catalog.selectedModelID }) {
            catalog.selectedModelID = provider.models.first?.id ?? AppConfig.defaultModel
        }
        saved = false
    }

    private func addProvider() {
        let provider = AppConfig.newProvider()
        catalog.providers.append(provider)
        selectProvider(provider)
        saved = false
    }

    private func removeProvider(_ index: Int) {
        guard catalog.providers.count > 1, catalog.providers.indices.contains(index) else { return }
        let removedID = catalog.providers[index].id
        catalog.providers.remove(at: index)
        apiKeyEnvironmentNamesByProviderID[removedID] = nil
        if catalog.selectedProviderID == removedID {
            let provider = catalog.providers[min(index, catalog.providers.count - 1)]
            selectProvider(provider)
        }
        saved = false
    }

    private func addModel(providerIndex: Int) {
        guard catalog.providers.indices.contains(providerIndex) else { return }
        let existing = Set(catalog.providers[providerIndex].models.map(\.id))
        let modelID = existing.contains(AppConfig.defaultModel) ? "model-id" : AppConfig.defaultModel
        catalog.providers[providerIndex].models.append(AppProviderModel(id: modelID, displayName: modelID))
        catalog.selectedModelID = modelID
        saved = false
    }

    private func removeModel(providerIndex: Int, modelIndex: Int) {
        guard catalog.providers.indices.contains(providerIndex),
              catalog.providers[providerIndex].models.count > 1,
              catalog.providers[providerIndex].models.indices.contains(modelIndex) else { return }
        let removedID = catalog.providers[providerIndex].models[modelIndex].id
        catalog.providers[providerIndex].models.remove(at: modelIndex)
        if catalog.selectedModelID == removedID {
            catalog.selectedModelID = catalog.providers[providerIndex].models[0].id
        }
        saved = false
    }

    private func providerSubtitle(_ provider: AppProviderSettings) -> String {
        let host = URL(string: provider.baseURL)?.host ?? provider.baseURL
        let format = provider.models.count == 1
            ? "1 model · %@ · %@"
            : "%lld models · %@ · %@"
        if provider.models.count == 1 {
            return MopeliumLocalization.format(
                format,
                host,
                apiKeySourceLabel(for: provider))
        }
        return MopeliumLocalization.format(
            format,
            Int64(provider.models.count),
            host,
            apiKeySourceLabel(for: provider))
    }

    private func providerFieldBinding(_ providerIndex: Int,
                                      _ keyPath: WritableKeyPath<AppProviderSettings, String>) -> Binding<String> {
        Binding(
            get: { catalog.providers[providerIndex][keyPath: keyPath] },
            set: {
                catalog.providers[providerIndex][keyPath: keyPath] = $0
                saved = false
            })
    }

    private func baseURLBinding(_ providerIndex: Int) -> Binding<String> {
        Binding(
            get: { catalog.providers[providerIndex].baseURL },
            set: {
                let baseURL = AppConfig.baseURL(fromChatEndpoint: $0)
                catalog.providers[providerIndex].baseURL = baseURL
                catalog.providers[providerIndex].chatEndpoint = AppConfig.chatEndpoint(forBaseURL: baseURL)
                saved = false
            })
    }

    private func chatEndpointBinding(_ providerIndex: Int) -> Binding<String> {
        Binding(
            get: { catalog.providers[providerIndex].chatEndpoint },
            set: {
                let endpoint = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                catalog.providers[providerIndex].chatEndpoint = endpoint
                catalog.providers[providerIndex].baseURL = AppConfig.baseURL(fromChatEndpoint: endpoint)
                saved = false
            })
    }

    private func modelFieldBinding(providerIndex: Int,
                                   modelIndex: Int,
                                   keyPath: WritableKeyPath<AppProviderModel, String>) -> Binding<String> {
        Binding(
            get: { catalog.providers[providerIndex].models[modelIndex][keyPath: keyPath] },
            set: {
                let oldID = catalog.providers[providerIndex].models[modelIndex].id
                catalog.providers[providerIndex].models[modelIndex][keyPath: keyPath] = $0
                if keyPath == \AppProviderModel.id, catalog.selectedModelID == oldID {
                    catalog.selectedModelID = $0
                }
                saved = false
            })
    }

    private func apiKeyEnvironmentBinding(for provider: AppProviderSettings) -> Binding<String> {
        Binding(
            get: {
                apiKeyEnvironmentNamesByProviderID[provider.id]
                    ?? AppConfig.apiKeyEnvironmentName(for: provider)
            },
            set: {
                apiKeyEnvironmentNamesByProviderID[provider.id] = $0
                saved = false
            })
    }

    private func apiKeyStatusLabel(for provider: AppProviderSettings) -> String {
        let environmentName = AppConfig.apiKeyEnvironmentName(for: provider)
        let status = env.hasAPIKey(for: provider)
            ? MopeliumLocalization.string("available")
            : MopeliumLocalization.string("not set")
        return MopeliumLocalization.format("env %@ · %@", environmentName, status)
    }

    private func apiKeySourceLabel(for provider: AppProviderSettings) -> String {
        MopeliumLocalization.format(
            "env %@",
            AppConfig.apiKeyEnvironmentName(for: provider))
    }

    private var settingsStorageNote: String {
        let credentialNote = MopeliumLocalization.string(
            "API keys are read only from environment variables; only variable names are saved.")
        if let path = AppConfig.externalConfigDescription {
            return MopeliumLocalization.format("Config: %@. %@", path, credentialNote)
        }
        return MopeliumLocalization.format(
            "Config: %@. %@",
            AppConfig.editableConfigDescription,
            credentialNote)
    }

    @ViewBuilder private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(MopeliumLocalization.string(label))
                .font(MopeliumType.caption(12, .semibold))
                .foregroundStyle(MopeliumTheme.softText(scheme))
            TextField(MopeliumLocalization.string(placeholder), text: text)
                .textFieldStyle(.plain)
                .font(MopeliumType.mono(13))
                .foregroundStyle(MopeliumTheme.deepText(scheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .overlay(inputBackground)
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(MopeliumTheme.separator(scheme), lineWidth: 1)
    }
}

struct MopeliumModelTitleLabel: View {
    let model: AppProviderModel

    var body: some View {
        HStack(spacing: 5) {
            Text(model.title)
                .foregroundStyle(.primary)
            if let reasoningLabel = model.reasoningLabel {
                Text(reasoningLabel)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
