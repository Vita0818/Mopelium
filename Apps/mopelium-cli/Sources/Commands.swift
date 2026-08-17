import Foundation
import MopeliumProviders

func printConfig(_ config: CLIConfig) {
    out("""
    endpoint : (configured, hidden) · \(config.selectedRouteLabel)
    model    : \(config.model)
    wire     : \(config.wire.rawValue)
    reasoning: \(config.reasoningEffort?.rawValue ?? "off")
    mode     : \(config.mode.rawValue)
    api key  : \(config.hasConfiguredCredential ? "(configured, hidden)" : "(unset)")
    routes   : \(config.providerRoutes.count)
    config   : \(config.configurationFileURL == nil ? ConfigFile.url.path : "(advanced Mopelium config, path hidden)")

    """)
}

func printHelp() {
    out("""
    Mopelium CLI — a local AI agent for ANY OpenAI-compatible endpoint.

    USAGE
      mopelium                 Start your default mode (set via `mopelium settings`)
      mopelium chat            Streaming chat (no tools)
      mopelium code [dir]      Coding agent: read/search/edit files, git/shell (with approval)
      mopelium cowork [dir]    Multi-agent work; use /goal <objective> for durable Goal execution
      mopelium settings        Interactive settings (endpoint, key, model, reasoning, mode)
      mopelium config          Print the resolved config
      mopelium selftest        Offline smoke test (no key)
      mopelium mcp help        Manage external MCP servers and session access
      mopelium exec --session <id> --agent <id> [--task <id>] --prompt <text> [--yes]
                              Run one exact durable Code/MCP turn
      mopelium diagnose-hang --pid <pid> [--output <directory>]
                              Capture a 10s sample and 5m Mopelium logs into an owner-only bundle
      mopelium help

    CONFIG  (env var > advanced Mopelium config > legacy config > default)
      MOPELIUM_CONFIG     optional mopelium.json/jsonc using model + enabled_providers + provider map
      MOPELIUM_BASE_URL   default https://api.openai.com/v1
      MOPELIUM_API_KEY    required (any non-empty for local servers)
      MOPELIUM_MODEL      default gpt-4o-mini
      MOPELIUM_REASONING  minimal | low | medium | high
      MOPELIUM_MODE       chat | code | cowork

    In a session, type /help for slash commands (/model, /reasoning, /mode, /clear …).

    FIRST RUN
      mopelium settings        # set endpoint + API key once
      mopelium                 # then just run it — uses your saved config

    ANY VENDOR (same binary)
      MOPELIUM_BASE_URL=http://localhost:11434/v1 MOPELIUM_API_KEY=ollama MOPELIUM_MODEL=llama3.1 mopelium chat
      MOPELIUM_BASE_URL=https://api.deepseek.com/v1 MOPELIUM_API_KEY=sk-... MOPELIUM_MODEL=deepseek-chat mopelium chat

    """)
}
