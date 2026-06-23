import Foundation
import MopeliumCore
import MopeliumProviders

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
            try runSelfTest()
        default:
            printHelp()
            throw MopeliumError.usage("Unknown command: \(command)")
        }
    }

    private static func printHelp() {
        out("""
        Mopelium v0.1

        Usage:
          mopelium ask [--no-stream] [--model MODEL] [--base-url URL] [--api-key-env ENV] "prompt"
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

        if config.stream {
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

    private static func runSelfTest() throws {
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
            out("Mopelium selftest: OK\n")
        }
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
