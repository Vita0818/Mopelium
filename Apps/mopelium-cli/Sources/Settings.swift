import Foundation

private let bold = "\u{001B}[1m", dim = "\u{001B}[2m", reset = "\u{001B}[0m", green = "\u{001B}[32m"

/// `mopelium settings` — interactive editor for the persistent config file
/// (~/.config/mopelium/config.json). API key material is never stored here;
/// only the name of the environment variable that owns it may be persisted.
func runSettings() throws {
    var cfg = ConfigFile.read()

    func display(_ fileKey: String, default def: String) -> String {
        if let v = cfg[fileKey], !v.isEmpty { return v }
        return "\(dim)\(def) (default)\(reset)"
    }

    while true {
        out("""

        \(bold)Mopelium settings\(reset)  \(dim)\(ConfigFile.url.path)\(reset)

          1) Endpoint (base URL) : \(display("baseURL", default: CLIConfig.defaultBaseURL))
          2) API key environment : \(display("apiKeyEnv", default: CLIConfig.defaultAPIKeyEnvironment))
          3) Default model       : \(display("model", default: CLIConfig.defaultModel))
          4) Reasoning effort     : \(display("reasoning", default: "off"))
          5) Default mode        : \(display("mode", default: "chat"))

          s) Save   q) Quit without saving

        Select [1-5/s/q]:
        """)

        guard let choice = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else { return }
        switch choice {
        case "1":
            out("Base URL (e.g. https://api.openai.com/v1): ")
            if let v = readLine() { cfg["baseURL"] = v.trimmingCharacters(in: .whitespaces) }
        case "2":
            out("Environment variable name (the API key itself is never stored): ")
            if let value = readLine() {
                let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                cfg["apiKeyEnv"] = name.isEmpty
                    ? CLIConfig.defaultAPIKeyEnvironment
                    : try CLIConfig.validatedAPIKeyEnvironmentName(name)
            }
        case "3":
            out("Default model (e.g. gpt-4o-mini, deepseek-chat, llama3.1): ")
            if let v = readLine() { cfg["model"] = v.trimmingCharacters(in: .whitespaces) }
        case "4":
            out("Reasoning [minimal|low|medium|high, empty = off]: ")
            if let v = readLine() {
                let t = v.trimmingCharacters(in: .whitespaces).lowercased()
                if t.isEmpty || t == "off" { cfg["reasoning"] = nil } else { cfg["reasoning"] = t }
            }
        case "5":
            out("Default mode [chat|code|cowork]: ")
            if let v = readLine() { cfg["mode"] = v.trimmingCharacters(in: .whitespaces).lowercased() }
        case "s":
            try ConfigFile.write(cfg.filter { !$0.value.isEmpty })
            out("\n\(green)Saved.\(reset) Now just run `mopelium` (or `mopelium chat`).\n")
            return
        case "q", "":
            out("\nNo changes saved.\n")
            return
        default:
            out("\n?\n")
        }
    }
}
