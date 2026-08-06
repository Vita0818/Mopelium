import Foundation
import MopeliumCore
import MopeliumProviders

enum Mode: String { case chat, code, cowork }

/// Persistent config at `~/.config/mopelium/config.json` (all values are strings).
/// `mopelium settings` writes it; env vars override it; both override defaults.
enum ConfigFile {
    private static let plaintextCredentialKeys: Set<String> = [
        "apikey", "api_key", "api-key",
    ]
    private static let nonEnvironmentCredentialKeys: Set<String> = [
        "apikeyfile", "api_key_file", "api-key-file",
        "authfile", "auth_file", "auth-file",
        "providerconfig", "provider_config", "provider-config",
        "credentialref", "credential_ref", "credential-ref",
        "apikeyref", "api_key_ref", "api-key-ref",
    ]

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mopelium/config.json")
    }

    static func read() -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else {
            return [:]
        }
        var sanitized = object.filter { !isDisallowedCredentialKey($0.key) }
        if sanitized["apiKeyEnv"] == nil {
            sanitized["apiKeyEnv"] = sanitized["api_key_env"]
                ?? sanitized["api-key-env"]
        }
        sanitized.removeValue(forKey: "api_key_env")
        sanitized.removeValue(forKey: "api-key-env")
        return sanitized
    }

    static func write(_ dict: [String: String]) throws {
        guard !dict.keys.contains(where: isDisallowedCredentialKey) else {
            throw MopeliumError.config(
                "Refusing to store API keys or non-environment credential references in CLI config")
        }
        var sanitized = dict
        if sanitized["apiKeyEnv"] == nil {
            sanitized["apiKeyEnv"] = sanitized["api_key_env"]
                ?? sanitized["api-key-env"]
        }
        sanitized.removeValue(forKey: "api_key_env")
        sanitized.removeValue(forKey: "api-key-env")
        if let configuredName = sanitized["apiKeyEnv"] {
            if configuredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sanitized.removeValue(forKey: "apiKeyEnv")
            } else {
                sanitized["apiKeyEnv"] = try CLIConfig.validatedAPIKeyEnvironmentName(
                    configuredName)
            }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: sanitized,
            options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func isDisallowedCredentialKey(_ rawKey: String) -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return plaintextCredentialKeys.contains(key)
            || nonEnvironmentCredentialKeys.contains(key)
    }
}

/// Connect to ANY OpenAI-compatible endpoint. Resolution precedence per field:
/// environment variable → config file → built-in default.
struct CLIConfig {
    let baseURL: URL
    let model: String
    let wire: WireFormat
    let reasoningEffort: ReasoningEffort?
    let mode: Mode
    let includeUsage: Bool
    let maxSteps: Int
    /// Every host-configured route eligible for this CLI process. Chat/Code
    /// continue to use the selected route while Cowork compiles all routes into
    /// exact, versioned inference profiles.
    let providerRoutes: [CLIProviderRoute]
    let selectedProviderID: String
    let selectedVariantID: String?
    /// The explicitly selected Mopelium config is retained for safe local
    /// reporting only. Credentials are resolved exclusively through the
    /// environment references compiled into `providerRoutes`.
    let configurationFileURL: URL?

    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"
    static let defaultAPIKeyEnvironment = "MOPELIUM_API_KEY"
    static let apiKeyEnvironmentSelector = "MOPELIUM_API_KEY_ENV"

    init(baseURL: URL,
         apiKeyEnvironment: String,
         model: String,
         wire: WireFormat,
         reasoningEffort: ReasoningEffort?,
         mode: Mode,
         includeUsage: Bool,
         maxSteps: Int,
         providerRoutes: [CLIProviderRoute]? = nil,
         selectedProviderID: String? = nil,
         selectedVariantID: String? = nil,
         configurationFileURL: URL? = nil) {
        self.baseURL = baseURL
        self.model = model
        self.wire = wire
        self.reasoningEffort = reasoningEffort
        self.mode = mode
        self.includeUsage = includeUsage
        self.maxSteps = maxSteps
        let legacy = CLIProviderRoute.legacy(
            baseURL: baseURL,
            apiKeyEnvironment: apiKeyEnvironment,
            model: model,
            wire: wire)
        self.providerRoutes = providerRoutes?.isEmpty == false ? providerRoutes! : [legacy]
        self.selectedProviderID = selectedProviderID ?? legacy.id
        self.selectedVariantID = selectedVariantID
        self.configurationFileURL = configurationFileURL
    }

    static func load() throws -> CLIConfig {
        let env = ProcessInfo.processInfo.environment
        if let modernURL = CLIModernProviderConfig.existingURL(environment: env) {
            return try load(configurationFileURL: modernURL, environment: env)
        }
        let file = ConfigFile.read()
        func value(_ envKey: String, _ fileKey: String, fallback: String?) -> String? {
            if let e = env[envKey], !e.isEmpty { return e }
            if let f = file[fileKey], !f.isEmpty { return f }
            return fallback
        }

        let baseString = value("MOPELIUM_BASE_URL", "baseURL", fallback: defaultBaseURL)!
        guard let baseURL = CLIProviderRoute.validHTTPURL(baseString) else {
            throw MopeliumError.config("invalid CLI provider endpoint")
        }
        let configuredAPIKeyEnvironment = file["apiKeyEnv"]
            ?? file["api_key_env"]
            ?? file["api-key-env"]
        let apiKeyEnvironment = try apiKeyEnvironmentName(
            environment: env,
            configured: configuredAPIKeyEnvironment)
        guard let apiKey = env[apiKeyEnvironment]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty else {
            throw MopeliumError.config(
                "no API key — set environment variable \(apiKeyEnvironment)")
        }
        let model = value("MOPELIUM_MODEL", "model", fallback: defaultModel)!
        let rawReasoning = value("MOPELIUM_REASONING", "reasoning", fallback: nil)
        let reasoning = try parsedReasoningEffort(rawReasoning)
        let mode = Mode(rawValue: value("MOPELIUM_MODE", "mode", fallback: "chat")!.lowercased()) ?? .chat
        // Ask the endpoint for token usage (default on). Set MOPELIUM_USAGE=0 if an
        // endpoint rejects the stream_options field.
        let usageStr = value("MOPELIUM_USAGE", "usage", fallback: "1")!.lowercased()
        let includeUsage = !(usageStr == "0" || usageStr == "false" || usageStr == "off")
        // How many tool round-trips one turn may take before giving up. Long
        // agentic tasks need plenty; override with MOPELIUM_MAX_STEPS.
        let maxSteps = max(1, Int(value("MOPELIUM_MAX_STEPS", "maxSteps", fallback: "50")!) ?? 50)

        return CLIConfig(baseURL: baseURL,
                         apiKeyEnvironment: apiKeyEnvironment,
                         model: model, wire: .openai,
                         reasoningEffort: reasoning, mode: mode, includeUsage: includeUsage,
                         maxSteps: maxSteps,
                         selectedVariantID: reasoning.map { "reasoning-\($0.rawValue)" })
    }

    /// Deterministic seam used by the offline self-test and by `MOPELIUM_CONFIG`.
    /// The schema is the same Mopelium/OpenCode-compatible provider map used by
    /// the macOS app; no CLI-only provider format is introduced.
    static func load(configurationFileURL: URL,
                     environment: [String: String]) throws -> CLIConfig {
        let document = try CLIModernProviderConfig.load(
            from: configurationFileURL,
            environment: environment)
        func value(_ envKey: String, fallback: String?) -> String? {
            if let e = environment[envKey], !e.isEmpty { return e }
            return fallback
        }

        let requestedModel = value(
            "MOPELIUM_MODEL",
            fallback: document.selectedModelID) ?? document.selectedModelID
        var selectedProviderID = document.selectedProviderID
        var selectedModelID = requestedModel
        if let split = try document.providerQualifiedModel(requestedModel) {
            selectedProviderID = split.providerID
            selectedModelID = split.modelID
        } else {
            // An unqualified host override may name a model that exists on one
            // configured route other than the document default. Preserve that
            // exact route instead of silently inventing the model on the
            // current provider. Ambiguous IDs stay on the explicitly selected
            // provider when possible; otherwise the host must qualify them.
            let matchingRoutes = document.routes.filter { route in
                route.models.contains(where: { $0.id == requestedModel })
            }
            if matchingRoutes.count == 1, let only = matchingRoutes.first {
                selectedProviderID = only.id
            } else if matchingRoutes.count > 1,
                      !matchingRoutes.contains(where: { $0.id == selectedProviderID }) {
                throw MopeliumError.config(
                    "ambiguous CLI model override; qualify it with a provider ID")
            }
        }

        guard var selectedRoute = document.routes.first(where: {
            $0.id == selectedProviderID
        }) ?? document.routes.first else {
            throw MopeliumError.config("no usable CLI provider routes")
        }
        if !selectedRoute.models.contains(where: { $0.id == selectedModelID }) {
            selectedRoute.models.append(CLIProviderModel(
                id: selectedModelID,
                displayName: selectedModelID))
        }

        var routes = document.routes
        if let baseOverride = environment["MOPELIUM_BASE_URL"], !baseOverride.isEmpty {
            guard let url = CLIProviderRoute.validHTTPURL(baseOverride) else {
                throw MopeliumError.config("invalid CLI provider endpoint")
            }
            selectedRoute.baseURL = url
            selectedRoute.chatEndpoint = nil
        }
        if let index = routes.firstIndex(where: { $0.id == selectedRoute.id }) {
            routes[index] = selectedRoute
        }
        guard selectedRoute.credentialRef.source == .environment else {
            throw MopeliumError.config(
                "CLI provider credentials must reference an environment variable")
        }
        let apiKeyEnvironment = try validatedAPIKeyEnvironmentName(
            selectedRoute.credentialRef.account)
        guard let apiKey = environment[apiKeyEnvironment]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty else {
            throw MopeliumError.config(
                "no API key — set environment variable \(apiKeyEnvironment)")
        }

        let rawReasoning = value("MOPELIUM_REASONING", fallback: nil)
        let reasoning = try parsedReasoningEffort(rawReasoning)
        let mode = Mode(rawValue: value("MOPELIUM_MODE", fallback: "chat")!.lowercased()) ?? .chat
        let usageStr = value("MOPELIUM_USAGE", fallback: "1")!.lowercased()
        let includeUsage = !(usageStr == "0" || usageStr == "false" || usageStr == "off")
        let maxSteps = max(1, Int(value("MOPELIUM_MAX_STEPS", fallback: "50")!) ?? 50)
        let selectedVariantID = try document.selectedVariantID(
            providerID: selectedRoute.id,
            modelID: selectedModelID,
            reasoningEffort: reasoning)
        if let reasoning,
           selectedVariantID == nil,
           !document.baseModel(
                providerID: selectedRoute.id,
                modelID: selectedModelID,
                hasReasoningEffort: reasoning) {
            throw MopeliumError.config(
                "selected CLI reasoning effort has no configured variant for the selected model")
        }

        return CLIConfig(
            baseURL: selectedRoute.baseURL,
            apiKeyEnvironment: apiKeyEnvironment,
            model: selectedModelID,
            wire: selectedRoute.wire,
            reasoningEffort: reasoning,
            mode: mode,
            includeUsage: includeUsage,
            maxSteps: maxSteps,
            providerRoutes: routes,
            selectedProviderID: selectedRoute.id,
            selectedVariantID: selectedVariantID,
            configurationFileURL: configurationFileURL.standardizedFileURL)
    }

    static func apiKeyEnvironmentName(
        environment: [String: String],
        configured: String?
    ) throws -> String {
        let selected = environment[apiKeyEnvironmentSelector]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let configured = configured?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if let selected, !selected.isEmpty {
            candidate = selected
        } else if let configured, !configured.isEmpty {
            candidate = configured
        } else {
            candidate = defaultAPIKeyEnvironment
        }
        return try validatedAPIKeyEnvironmentName(
            candidate)
    }

    static func validatedAPIKeyEnvironmentName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.range(
            of: #"^[A-Za-z_][A-Za-z0-9_]*$"#,
            options: .regularExpression) != nil else {
            throw MopeliumError.config("invalid API key environment variable name")
        }
        return name
    }

    private static func parsedReasoningEffort(_ raw: String?) throws -> ReasoningEffort? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        guard let effort = ReasoningEffort(rawValue: normalized) else {
            throw MopeliumError.config("invalid CLI reasoning effort")
        }
        return effort
    }

    func providerConfig() -> ProviderConfig {
        let endpoints = providerRoutes.map { route in
            ProviderEndpoint(
                id: CLIInferenceRouteIdentity.endpointID(route: route),
                baseURL: route.baseURL,
                chatEndpoint: route.chatEndpoint,
                apiKeyRef: route.credentialRef,
                wire: route.wire,
                modelRequestOptions: Dictionary(uniqueKeysWithValues: route.models.map {
                    ($0.id, $0.requestOptions)
                }))
        }
        let selectedRoute = providerRoutes.first { $0.id == selectedProviderID }
            ?? providerRoutes[0]
        let ref = ModelRef(
            endpoint: CLIInferenceRouteIdentity.endpointID(route: selectedRoute),
            model: ModelID(rawValue: model))
        return ProviderConfig(endpoints: endpoints, models: ResolvedModels(chat: ref, agent: ref))
    }

    var selectedRouteLabel: String {
        let route = providerRoutes.first { $0.id == selectedProviderID } ?? providerRoutes[0]
        return route.safeDisplayName
    }

    var hasConfiguredCredential: Bool {
        let route = providerRoutes.first { $0.id == selectedProviderID } ?? providerRoutes[0]
        guard route.credentialRef.source == .environment else { return false }
        return ProcessInfo.processInfo.environment[route.credentialRef.account]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
    }
}
