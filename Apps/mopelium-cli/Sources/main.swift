import Foundation
import MopeliumAgent
import MopeliumCore
import MopeliumProviders
import MopeliumTools

@main
struct MopeliumCLI {
    static func main() async {
        do {
            var args = Array(CommandLine.arguments.dropFirst())
            if args.first == "--" { args.removeFirst() }
            try await run(args)
        } catch {
            errOut("\(error.localizedDescription)\n")
            exit(1)
        }
    }

    private static func run(_ args: [String]) async throws {
        let command = args.first ?? "help"
        switch command {
        case "help", "--help", "-h":
            printHelp()
        case "config":
            try runConfig(Array(args.dropFirst()))
        case "ask":
            try await runAsk(Array(args.dropFirst()))
        case "selftest":
            try await runSelfTest()
        default:
            printHelp()
            throw MopeliumError.usage("Unknown command: \(command)")
        }
    }

    private static func printHelp() {
        out("""
        Mopelium v0.4

        Usage:
          mopelium ask [--no-stream] [--model MODEL] [--base-url URL] [--api-key-env ENV] [--tools PATH|--tools-current] [--allow-write] [--allow-destructive] [--allow-shell] [--max-tool-iterations N] "prompt"
          mopelium config show
          mopelium config set base_url URL
          mopelium config set model MODEL
          mopelium config set api_key_env ENV
          mopelium selftest
          mopelium help

        """)
    }

    private static func runConfig(_ args: [String]) throws {
        guard let subcommand = args.first else {
            throw MopeliumError.usage("Usage: mopelium config show | mopelium config set KEY VALUE")
        }

        switch subcommand {
        case "show":
            let config = try CLIConfigStore.resolve()
            let show = ConfigShow(
                baseURL: config.baseURLString,
                apiKeyEnv: config.apiKeyEnv,
                apiKeyLoaded: config.apiKeyLoaded,
                model: config.model,
                stream: config.stream
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(show)
            out(String(decoding: data, as: UTF8.self) + "\n")
        case "set":
            guard args.count >= 3 else {
                throw MopeliumError.usage("Usage: mopelium config set base_url URL | model MODEL | api_key_env ENV")
            }
            let key = args[1]
            let value = args[2]
            _ = try CLIConfigStore.set(key, value: value)
            out("Updated \(key) in \(CLIConfigStore.defaultURL().path)\n")
        default:
            throw MopeliumError.usage("Unknown config command: \(subcommand)")
        }
    }

    private static func runAsk(_ args: [String]) async throws {
        var overrides = CLIConfigOverrides()
        var promptParts: [String] = []
        var toolWorkspace: URL?
        var allowWrite = false
        var allowDestructive = false
        var allowShell = false
        var maxToolIterations = 12
        var index = 0

        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--no-stream":
                overrides.stream = false
            case "--model":
                index += 1
                guard index < args.count else { throw MopeliumError.usage("--model requires a value") }
                overrides.model = args[index]
            case "--base-url":
                index += 1
                guard index < args.count else { throw MopeliumError.usage("--base-url requires a value") }
                overrides.baseURL = args[index]
            case "--api-key-env":
                index += 1
                guard index < args.count else { throw MopeliumError.usage("--api-key-env requires a value") }
                overrides.apiKeyEnv = args[index]
            case "--tools":
                index += 1
                guard index < args.count else { throw MopeliumError.usage("--tools requires a workspace path") }
                toolWorkspace = URL(fileURLWithPath: args[index]).standardizedFileURL
            case "--tools-current":
                toolWorkspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).standardizedFileURL
            case "--allow-write":
                allowWrite = true
            case "--allow-destructive":
                allowDestructive = true
            case "--allow-shell":
                allowShell = true
            case "--max-tool-iterations":
                index += 1
                guard index < args.count, let value = Int(args[index]), value > 0 else {
                    throw MopeliumError.usage("--max-tool-iterations requires a positive integer")
                }
                maxToolIterations = value
            case "--help", "-h":
                printHelp()
                return
            default:
                if arg.hasPrefix("--") {
                    throw MopeliumError.usage("Unknown ask option: \(arg)")
                }
                promptParts.append(arg)
            }
            index += 1
        }

        let prompt = promptParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw MopeliumError.usage("ask requires a prompt")
        }

        let config = try CLIConfigStore.resolve(overrides: overrides)
        let apiKey = try config.requireAPIKey()
        let provider = OpenAICompatibleProvider(baseURL: config.baseURL, apiKey: apiKey)
        let request = ChatRequest(
            model: config.model,
            messages: [ChatMessage(role: "user", content: prompt)],
            stream: config.stream
        )

        if let toolWorkspace {
            try await runAgentAsk(
                request: request,
                provider: provider,
                workspace: toolWorkspace,
                allowWrite: allowWrite,
                allowDestructive: allowDestructive,
                allowShell: allowShell,
                maxToolIterations: maxToolIterations
            )
        } else if config.stream {
            let chunks = try await provider.stream(request: request)
            for try await chunk in chunks {
                out(chunk.content)
            }
            out("\n")
        } else {
            let response = try await provider.complete(request: request)
            out(response.content)
            if !response.content.hasSuffix("\n") { out("\n") }
        }
    }

    private static func runAgentAsk(request: ChatRequest,
                                    provider: OpenAICompatibleProvider,
                                    workspace: URL,
                                    allowWrite: Bool,
                                    allowDestructive: Bool,
                                    allowShell: Bool,
                                    maxToolIterations: Int) async throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workspace.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw MopeliumError.config("--tools workspace must be an existing directory: \(workspace.path)")
        }

        var allowed: Set<SideEffect> = [.readOnly, .network, .exec]
        if allowWrite { allowed.insert(.write) }
        if allowDestructive { allowed.insert(.destructive) }
        let policy = MopeliumAgentToolPolicy(
            allowedSideEffects: allowed,
            allowShellTool: allowShell,
            maxIterations: maxToolIterations
        )
        let toolProvider = OpenAICompatibleToolCallingProvider(provider: provider)
        let loop = MopeliumAgentLoop(
            provider: toolProvider,
            registry: .standard(),
            workspaceRoot: workspace,
            policy: policy
        )

        var bufferedText = ""
        let events = loop.stream(model: request.model, messages: request.messages)
        for try await event in events {
            switch event {
            case .textDelta(let text):
                if request.stream {
                    out(text)
                } else {
                    bufferedText += text
                }
            case .toolCall(_, let name, _):
                errOut("\n[mopelium tool] \(name)\n")
            case .toolResult(_, let name, let observation, let changedFiles):
                let changed = changedFiles.isEmpty ? "" : " changed: \(changedFiles.joined(separator: ", "))"
                errOut("[mopelium tool result] \(name): \(truncated(observation, limit: 500))\(changed)\n")
            }
        }

        if request.stream {
            out("\n")
        } else {
            out(bufferedText)
            if !bufferedText.hasSuffix("\n") { out("\n") }
        }
    }

    private static func runSelfTest() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mopelium-selftest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
        let config = try CLIConfigStore.resolve(fileURL: tempURL, environment: [:])
        guard config.baseURLString == CLIConfig.defaultBaseURL,
              config.apiKeyEnv == CLIConfig.defaultAPIKeyEnv,
              config.model == CLIConfig.defaultModel,
              config.stream == true else {
            throw MopeliumError.config("default config selftest failed")
        }

        let parser = SSEParser()
        let sample = """
        data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}

        data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}

        data: [DONE]

        """
        let events = parser.consume(Data(sample.utf8)) + parser.flush()
        let text = events.compactMap { event -> String? in
            if case .content(let content) = event { return content }
            return nil
        }.joined()
        guard text == "Hello", events.contains(.done) else {
            throw MopeliumError.decoding("SSE parser selftest failed")
        }

        do {
            _ = try CLIConfigStore.writableField(named: "api_key")
            throw MopeliumError.config("api_key rejection selftest failed")
        } catch MopeliumError.config(let message) where message.contains("Refusing to store API keys") {
        }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("mopelium-agent-selftest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try Data("hello".utf8).write(to: workspace.appendingPathComponent("fixture.txt"), options: .atomic)

        let toolProvider = SelfTestToolProvider([
            [
                .toolCalls([ToolCall(id: "call_list", name: "list_files", arguments: #"{"path":"."}"#)]),
                .done(finishReason: "tool_calls"),
            ],
            [
                .textDelta("agent ok"),
                .done(finishReason: "stop"),
            ],
        ])
        let loop = MopeliumAgentLoop(
            provider: toolProvider,
            registry: .standard(),
            workspaceRoot: workspace,
            policy: .readOnly
        )
        var agentText = ""
        for try await event in loop.stream(model: "selftest-model", messages: [ChatMessage(role: "user", content: "list files")]) {
            if case .textDelta(let text) = event {
                agentText += text
            }
        }
        guard agentText == "agent ok" else {
            throw MopeliumError.provider("agent loop selftest failed")
        }
        let requests = await toolProvider.capturedRequests()
        guard requests.count == 2,
              requests[1].messages.contains(where: { $0.role == .tool && ($0.content?.contains("fixture.txt") ?? false) }) else {
            throw MopeliumError.provider("agent loop did not feed tool observation back to provider")
        }

        out("Mopelium selftest: OK\n")
    }
}

private final class SelfTestToolProvider: ToolCallingChatProvider, @unchecked Sendable {
    private let state: SelfTestToolProviderState

    init(_ scripts: [[ToolChatChunk]]) {
        self.state = SelfTestToolProviderState(scripts)
    }

    func capturedRequests() async -> [ToolChatRequest] {
        await state.capturedRequests()
    }

    func streamToolCalls(request: ToolChatRequest) async throws -> AsyncThrowingStream<ToolChatChunk, Error> {
        let script = await state.nextScript(for: request)
        return AsyncThrowingStream { continuation in
            for chunk in script {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

private actor SelfTestToolProviderState {
    private var scripts: [[ToolChatChunk]]
    private var requests: [ToolChatRequest] = []

    init(_ scripts: [[ToolChatChunk]]) {
        self.scripts = scripts
    }

    func capturedRequests() -> [ToolChatRequest] {
        requests
    }

    func nextScript(for request: ToolChatRequest) -> [ToolChatChunk] {
        requests.append(request)
        if scripts.isEmpty {
            return [.done(finishReason: "stop")]
        }
        return scripts.removeFirst()
    }
}

private struct ConfigShow: Encodable {
    let baseURL: String
    let apiKeyEnv: String
    let apiKeyLoaded: Bool
    let model: String
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case apiKeyEnv = "api_key_env"
        case apiKeyLoaded = "api_key_loaded"
        case model
        case stream
    }
}
