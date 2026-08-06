import Foundation
import MopeliumCore
import MopeliumProtocol
import MopeliumProviders

/// One named variant from the shared Mopelium/OpenCode-compatible provider
/// configuration. The raw configuration name stays local; durable bindings use
/// an opaque derived variant identifier.
struct CLIProviderVariant: Equatable, Sendable {
    let id: String
    let requestOptions: [String: JSONValue]
}

struct CLIProviderModel: Equatable, Sendable {
    let id: String
    let displayName: String
    let requestOptions: [String: JSONValue]
    let variants: [CLIProviderVariant]

    init(id: String,
         displayName: String,
         requestOptions: [String: JSONValue] = [:],
         variants: [CLIProviderVariant] = []) {
        self.id = id
        self.displayName = displayName
        self.requestOptions = requestOptions
        self.variants = variants
    }
}

/// A logical provider route. `id` is used only as local configuration input;
/// catalog/EventLog identifiers are opaque hashes. CLI credentials are always
/// lazy environment-variable references; secret material is never retained in
/// this route value.
struct CLIProviderRoute: Equatable, Sendable {
    let id: String
    let displayName: String
    var baseURL: URL
    var chatEndpoint: URL?
    let wire: WireFormat
    var credentialRef: KeychainRef
    var models: [CLIProviderModel]

    var safeDisplayName: String {
        "route \(CLIInferenceRouteIdentity.logicalDigest(routeID: id).prefix(8))"
    }

    static func legacy(baseURL: URL,
                       apiKeyEnvironment: String,
                       model: String,
                       wire: WireFormat) -> CLIProviderRoute {
        let routeID = "legacy-default"
        let variants = CLIInferenceProfiles.reasoningLevels.map { effort in
            CLIProviderVariant(
                id: "reasoning-\(effort.rawValue)",
                requestOptions: ["reasoning_effort": .string(effort.rawValue)])
        }
        return CLIProviderRoute(
            id: routeID,
            displayName: "CLI legacy route",
            baseURL: baseURL,
            chatEndpoint: nil,
            wire: wire,
            credentialRef: .environment(apiKeyEnvironment),
            models: [CLIProviderModel(
                id: model,
                displayName: model,
                variants: variants)])
    }

    static func validHTTPURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }
}

/// Decoder for the same advanced configuration shape used by the macOS app:
/// `model`, `enabled_providers`, and a `provider.<id>` map containing
/// connection options plus model `options` and named `variants`.
struct CLIModernProviderConfig: Sendable {
    let routes: [CLIProviderRoute]
    let selectedProviderID: String
    let selectedModelID: String
    let sourceURL: URL

    static func existingURL(environment: [String: String]) -> URL? {
        if let override = environment["MOPELIUM_CONFIG"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: expandedPath(override)).standardizedFileURL
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let config = home.appendingPathComponent(".config/mopelium", isDirectory: true)
        var candidates = [
            config.appendingPathComponent("mopelium.json"),
            config.appendingPathComponent("mopelium.jsonc"),
        ]
        if let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask).first {
            let directory = support.appendingPathComponent("Mopelium", isDirectory: true)
            candidates.append(directory.appendingPathComponent("mopelium.json"))
            candidates.append(directory.appendingPathComponent("mopelium.jsonc"))
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func load(from url: URL,
                     environment: [String: String]) throws -> CLIModernProviderConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MopeliumError.config("selected Mopelium provider config is unavailable")
        }
        let data = try JSONC.data(contentsOf: url)
        guard case .object(let root) = try JSONDecoder().decode(JSONValue.self, from: data),
              let providerMap = root.object("provider"),
              !providerMap.isEmpty else {
            throw MopeliumError.config("selected Mopelium provider config has no provider map")
        }

        let enabled = Set((root.stringArray("enabled_providers")
            ?? root.stringArray("enabledProviders") ?? []).map(normalizedID))
        let disabled = Set((root.stringArray("disabled_providers")
            ?? root.stringArray("disabledProviders") ?? []).map(normalizedID))
        let selectedRaw = resolvedConfigValue(
            root.string("model") ?? root.string("small_model") ?? root.string("smallModel"),
            environment: environment,
            configDirectory: url.deletingLastPathComponent())

        var routes: [CLIProviderRoute] = []
        for providerID in providerMap.keys.sorted() {
            let normalized = normalizedID(providerID)
            if disabled.contains(normalized) || (!enabled.isEmpty && !enabled.contains(normalized)) {
                continue
            }
            guard case .object(let provider) = providerMap[providerID] else { continue }
            let options = provider.object("options") ?? [:]
            guard let rawBase = options.string("baseURL") ?? provider.string("baseURL"),
                  let baseURL = CLIProviderRoute.validHTTPURL(rawBase) else {
                continue
            }
            let chatEndpoint: URL?
            if let rawChat = options.string("chatEndpoint") ?? provider.string("chatEndpoint") {
                guard let validated = CLIProviderRoute.validHTTPURL(rawChat) else {
                    throw MopeliumError.config("invalid CLI provider chat endpoint")
                }
                chatEndpoint = validated
            } else {
                chatEndpoint = nil
            }
            let credentialRef = try credentialReference(
                providerID: providerID,
                provider: provider,
                options: options,
                environment: environment)
            let models = parseModels(provider.object("models") ?? [:])
            guard !models.isEmpty else { continue }
            routes.append(CLIProviderRoute(
                id: providerID,
                displayName: provider.string("displayName")
                    ?? provider.string("name")
                    ?? providerID,
                baseURL: baseURL,
                chatEndpoint: chatEndpoint,
                wire: .openai,
                credentialRef: credentialRef,
                models: models))
        }
        guard !routes.isEmpty else {
            throw MopeliumError.config("selected Mopelium provider config has no usable routes")
        }

        let selection = try selectModel(selectedRaw, routes: routes)
        return CLIModernProviderConfig(
            routes: routes,
            selectedProviderID: selection.providerID,
            selectedModelID: selection.modelID,
            sourceURL: url.standardizedFileURL)
    }

    func providerQualifiedModel(_ raw: String) throws -> (providerID: String, modelID: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = routes.filter { route in
            route.models.contains(where: { $0.id == trimmed })
        }
        if exact.count == 1, let route = exact.first {
            return (route.id, trimmed)
        }
        if exact.count > 1 {
            if let selected = exact.first(where: { $0.id == selectedProviderID }) {
                return (selected.id, trimmed)
            }
            throw MopeliumError.config(
                "ambiguous CLI model override; qualify a model that is not also a complete configured model ID")
        }
        for route in routes.sorted(by: { $0.id.count > $1.id.count }) {
            let prefix = route.id + "/"
            if trimmed.hasPrefix(prefix) {
                let model = String(trimmed.dropFirst(prefix.count))
                if !model.isEmpty { return (route.id, model) }
            }
        }
        return nil
    }

    func selectedVariantID(providerID: String,
                           modelID: String,
                           reasoningEffort: ReasoningEffort?) throws -> String? {
        guard let reasoningEffort,
              let model = routes.first(where: { $0.id == providerID })?
                .models.first(where: { $0.id == modelID }) else {
            return nil
        }
        let matchingVariants = model.variants.filter {
            Self.reasoningEffort(in: $0.requestOptions) == reasoningEffort
        }
        let baseMatches = Self.reasoningEffort(in: model.requestOptions) == reasoningEffort
        guard matchingVariants.count + (baseMatches ? 1 : 0) <= 1 else {
            throw MopeliumError.config(
                "selected CLI reasoning effort matches multiple configured profiles; select an exact profile instead")
        }
        return matchingVariants.first?.id
    }

    func baseModel(providerID: String,
                   modelID: String,
                   hasReasoningEffort effort: ReasoningEffort) -> Bool {
        guard let model = routes.first(where: { $0.id == providerID })?
            .models.first(where: { $0.id == modelID }) else {
            return false
        }
        return Self.reasoningEffort(in: model.requestOptions) == effort
    }

    private static func selectModel(
        _ raw: String?,
        routes: [CLIProviderRoute]
    ) throws -> (providerID: String, modelID: String) {
        if let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            // A configured model ID may itself contain `/` (for example a
            // gateway model namespace). Exact model keys therefore win over
            // Mopelium's provider/model shorthand.
            let exact = routes.compactMap { route -> (String, String)? in
                route.models.contains(where: { $0.id == raw }) ? (route.id, raw) : nil
            }
            if exact.count == 1, let only = exact.first { return only }
            if exact.count > 1 {
                throw MopeliumError.config(
                    "ambiguous configured model ID across CLI provider routes")
            }
            for route in routes.sorted(by: { $0.id.count > $1.id.count }) {
                let prefix = route.id + "/"
                if raw.hasPrefix(prefix) {
                    let model = String(raw.dropFirst(prefix.count))
                    if !model.isEmpty { return (route.id, model) }
                }
            }
        }
        let route = routes[0]
        return (route.id, route.models[0].id)
    }

    private static func parseModels(
        _ map: [String: JSONValue]
    ) -> [CLIProviderModel] {
        map.keys.sorted().compactMap { configuredID in
            guard let value = map[configuredID] else { return nil }
            switch value {
            case .string(let name):
                return CLIProviderModel(id: configuredID, displayName: name)
            case .object(let object):
                let modelID = object.string("id") ?? configuredID
                let name = object.string("displayName")
                    ?? object.string("name")
                    ?? modelID
                let modelOptions = object.object("options") ?? [:]
                var variants: [CLIProviderVariant] = []
                if let variantMap = object.object("variants") {
                    for variantID in variantMap.keys.sorted() {
                        guard case .object(var variantOptions) = variantMap[variantID],
                              variantOptions["disabled"] != .bool(true) else {
                            continue
                        }
                        variantOptions.removeValue(forKey: "disabled")
                        variants.append(CLIProviderVariant(
                            id: variantID,
                            requestOptions: variantOptions))
                    }
                }
                return CLIProviderModel(
                    id: modelID,
                    displayName: name,
                    requestOptions: modelOptions,
                    variants: variants)
            default:
                return nil
            }
        }
    }

    private static func credentialReference(
        providerID: String,
        provider: [String: JSONValue],
        options: [String: JSONValue],
        environment: [String: String]
    ) throws -> KeychainRef {
        let inlineSecretKeys = ["apiKey", "api_key", "api-key"]
        let nonEnvironmentReferenceKeys = [
            "apiKeyFile", "api_key_file", "api-key-file",
            "authFile", "auth_file", "auth-file",
            "providerConfig", "provider_config", "provider-config",
            "credentialRef", "credential_ref", "credential-ref",
            "apiKeyRef", "api_key_ref", "api-key-ref",
        ]
        if options.contains(anyOf: nonEnvironmentReferenceKeys)
            || provider.contains(anyOf: nonEnvironmentReferenceKeys) {
            throw MopeliumError.config(
                "provider \(providerID) uses a forbidden non-environment credential reference")
        }
        var inlineEnvironment: String?
        for container in [options, provider] {
            for key in inlineSecretKeys where container[key] != nil {
                guard case .string(let raw) = container[key],
                      let variable = configVariable(in: raw),
                      variable.kind == "env" else {
                    throw MopeliumError.config(
                        "provider \(providerID) apiKey must be an {env:NAME} reference")
                }
                let environmentName = try CLIConfig.validatedAPIKeyEnvironmentName(
                    variable.value)
                if let inlineEnvironment, inlineEnvironment != environmentName {
                    throw MopeliumError.config(
                        "provider \(providerID) has conflicting API key environment references")
                }
                inlineEnvironment = environmentName
            }
        }
        let namedEnvironment = options.string(anyOf: [
            "apiKeyEnv", "api_key_env", "api-key-env",
        ]) ?? provider.string(anyOf: [
            "apiKeyEnv", "api_key_env", "api-key-env",
        ])
        let configuredEnvironment = inlineEnvironment ?? namedEnvironment
        let environmentName = try CLIConfig.apiKeyEnvironmentName(
            environment: environment,
            configured: configuredEnvironment)
        return .environment(environmentName)
    }

    private static func reasoningEffort(
        in options: [String: JSONValue]
    ) -> ReasoningEffort? {
        if case .string(let value) = options["reasoning_effort"] {
            return ReasoningEffort(rawValue: value.lowercased())
        }
        if case .object(let reasoning) = options["reasoning"],
           case .string(let value) = reasoning["effort"] {
            return ReasoningEffort(rawValue: value.lowercased())
        }
        return nil
    }

    private static func normalizedID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Exact multi-route credential resolver. Every catalog connection revision
/// must identify an environment variable. Retained revisions that reference
/// files, auth stores, provider configs, or legacy keychain values fail closed.
struct CLIExactSecretResolver: SecretResolver {
    private let environment: [String: String]

    init(
        config _: CLIConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.environment = environment
    }

    func secret(for ref: KeychainRef) async throws -> String {
        guard ref.source == .environment else {
            throw MopeliumError.config(
                "CLI credentials may only be resolved from environment variables")
        }
        let environmentName = try CLIConfig.validatedAPIKeyEnvironmentName(ref.account)
        let value = environment[environmentName]
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            throw MopeliumError.config(
                "credential unavailable for the exact CLI inference route")
        }
        return trimmed
    }
}

private enum JSONC {
    static func data(contentsOf url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { return data }
        return Data(stripTrailingCommas(stripComments(text)).utf8)
    }

    private static func stripComments(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        var inString = false
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if inString {
                output.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                index = next
                continue
            }
            if character == "\"" {
                inString = true
                output.append(character)
                index = next
                continue
            }
            if character == "/", next < text.endIndex {
                if text[next] == "/" {
                    index = text.index(after: next)
                    while index < text.endIndex, text[index] != "\n" {
                        index = text.index(after: index)
                    }
                    continue
                }
                if text[next] == "*" {
                    index = text.index(after: next)
                    while index < text.endIndex {
                        let lookahead = text.index(after: index)
                        if text[index] == "\n" { output.append("\n") }
                        if text[index] == "*", lookahead < text.endIndex, text[lookahead] == "/" {
                            index = text.index(after: lookahead)
                            break
                        }
                        index = lookahead
                    }
                    continue
                }
            }
            output.append(character)
            index = next
        }
        return output
    }

    private static func stripTrailingCommas(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        var inString = false
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            if inString {
                output.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                index = text.index(after: index)
                continue
            }
            if character == "\"" {
                inString = true
                output.append(character)
                index = text.index(after: index)
                continue
            }
            if character == "," {
                var lookahead = text.index(after: index)
                while lookahead < text.endIndex, text[lookahead].isWhitespace {
                    lookahead = text.index(after: lookahead)
                }
                if lookahead < text.endIndex,
                   text[lookahead] == "}" || text[lookahead] == "]" {
                    index = text.index(after: index)
                    continue
                }
            }
            output.append(character)
            index = text.index(after: index)
        }
        return output
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? {
        guard case .string(let value) = self[key] else { return nil }
        return value
    }

    func string(anyOf keys: [String]) -> String? {
        for key in keys {
            if let value = string(key) { return value }
        }
        return nil
    }

    func contains(anyOf keys: [String]) -> Bool {
        keys.contains { self[$0] != nil }
    }

    func object(_ key: String) -> [String: JSONValue]? {
        guard case .object(let value) = self[key] else { return nil }
        return value
    }

    func stringArray(_ key: String) -> [String]? {
        guard case .array(let values) = self[key] else { return nil }
        return values.compactMap {
            guard case .string(let string) = $0 else { return nil }
            return string
        }
    }

}

private func configVariable(in raw: String) -> (kind: String, value: String)? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
    let body = trimmed.dropFirst().dropLast()
    guard let separator = body.firstIndex(of: ":") else { return nil }
    let kind = body[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let value = body[body.index(after: separator)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !kind.isEmpty, !value.isEmpty else { return nil }
    return (kind, value)
}

private func resolvedConfigValue(_ raw: String?,
                                 environment: [String: String],
                                 configDirectory: URL) -> String? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else { return nil }
    guard let variable = configVariable(in: raw) else { return raw }
    switch variable.kind {
    case "env":
        return environment[variable.value]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    case "file":
        let path = resolvedPath(variable.value, relativeTo: configDirectory)
        return try? String(contentsOfFile: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    default:
        return raw
    }
}

private func resolvedPath(_ raw: String, relativeTo directory: URL) -> String {
    let expanded = expandedPath(raw)
    if expanded.hasPrefix("/") { return expanded }
    return directory.appendingPathComponent(expanded).standardizedFileURL.path
}

private func expandedPath(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed == "~" { return FileManager.default.homeDirectoryForCurrentUser.path }
    if trimmed.hasPrefix("~/") {
        return FileManager.default.homeDirectoryForCurrentUser.path
            + String(trimmed.dropFirst())
    }
    return trimmed
}
