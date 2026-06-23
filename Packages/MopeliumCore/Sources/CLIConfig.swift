import Foundation

public struct CLIConfig: Codable, Equatable, Sendable {
    public var baseURL: String
    public var apiKeyEnv: String
    public var model: String
    public var stream: Bool

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case apiKeyEnv = "api_key_env"
        case model
        case stream
    }

    public init(baseURL: String, apiKeyEnv: String, model: String, stream: Bool) {
        self.baseURL = baseURL
        self.apiKeyEnv = apiKeyEnv
        self.model = model
        self.stream = stream
    }

    public static let defaultBaseURL = "https://api.openai.com/v1"
    public static let defaultAPIKeyEnv = "MOPELIUM_API_KEY"
    public static let defaultModel = "gpt-4o-mini"

    public static var defaultConfig: CLIConfig {
        CLIConfig(
            baseURL: defaultBaseURL,
            apiKeyEnv: defaultAPIKeyEnv,
            model: defaultModel,
            stream: true
        )
    }
}

public struct CLIConfigOverrides: Equatable, Sendable {
    public var baseURL: String?
    public var apiKeyEnv: String?
    public var model: String?
    public var stream: Bool?

    public init(baseURL: String? = nil, apiKeyEnv: String? = nil, model: String? = nil, stream: Bool? = nil) {
        self.baseURL = baseURL
        self.apiKeyEnv = apiKeyEnv
        self.model = model
        self.stream = stream
    }
}

public struct ResolvedCLIConfig: Equatable, Sendable {
    public var baseURL: URL
    public var baseURLString: String
    public var apiKeyEnv: String
    public var apiKey: String?
    public var model: String
    public var stream: Bool

    public var apiKeyLoaded: Bool {
        !(apiKey ?? "").isEmpty
    }

    public func requireAPIKey() throws -> String {
        guard let apiKey, !apiKey.isEmpty else {
            throw MopeliumError.config("Missing API key. Set environment variable \(apiKeyEnv) or change api_key_env in config.")
        }
        return apiKey
    }
}

public enum CLIConfigField: String, Equatable, Sendable {
    case baseURL = "base_url"
    case model
    case apiKeyEnv = "api_key_env"
}

public enum CLIConfigStore {
    public static func defaultURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("mopelium", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public static func read(from url: URL = defaultURL()) throws -> CLIConfig? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CLIConfig.self, from: data)
        } catch let error as DecodingError {
            throw MopeliumError.decoding("invalid config at \(url.path): \(error)")
        } catch {
            throw MopeliumError.io("cannot read config at \(url.path): \(error.localizedDescription)")
        }
    }

    public static func write(_ config: CLIConfig, to url: URL = defaultURL()) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(config)
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch let error as EncodingError {
            throw MopeliumError.decoding("cannot encode config: \(error)")
        } catch {
            throw MopeliumError.io("cannot write config at \(url.path): \(error.localizedDescription)")
        }
    }

    public static func resolve(
        fileURL: URL = defaultURL(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        overrides: CLIConfigOverrides = CLIConfigOverrides()
    ) throws -> ResolvedCLIConfig {
        let fileConfig = try read(from: fileURL) ?? CLIConfig.defaultConfig

        let baseURLString = firstNonEmpty(
            overrides.baseURL,
            environment["MOPELIUM_BASE_URL"],
            fileConfig.baseURL,
            CLIConfig.defaultBaseURL
        )
        guard let baseURL = URL(string: baseURLString), baseURL.scheme != nil else {
            throw MopeliumError.config("Invalid base_url: \(baseURLString)")
        }

        let apiKeyEnv = firstNonEmpty(
            overrides.apiKeyEnv,
            environment["MOPELIUM_API_KEY_ENV"],
            fileConfig.apiKeyEnv,
            CLIConfig.defaultAPIKeyEnv
        )
        let model = firstNonEmpty(
            overrides.model,
            environment["MOPELIUM_MODEL"],
            fileConfig.model,
            CLIConfig.defaultModel
        )
        let stream = overrides.stream
            ?? parseBool(environment["MOPELIUM_STREAM"])
            ?? fileConfig.stream

        let apiKey = environment[apiKeyEnv]
        return ResolvedCLIConfig(
            baseURL: baseURL,
            baseURLString: baseURLString,
            apiKeyEnv: apiKeyEnv,
            apiKey: apiKey,
            model: model,
            stream: stream
        )
    }

    public static func writableField(named name: String) throws -> CLIConfigField {
        switch name {
        case "base_url", "baseURL", "base-url":
            return .baseURL
        case "model":
            return .model
        case "api_key_env", "apiKeyEnv", "api-key-env":
            return .apiKeyEnv
        case "api_key", "apiKey", "api-key":
            throw MopeliumError.config("Refusing to store API keys in config. Use `config set api_key_env ENV` instead.")
        default:
            throw MopeliumError.config("Unknown config key: \(name)")
        }
    }

    @discardableResult
    public static func set(_ key: String, value: String, fileURL: URL = defaultURL()) throws -> CLIConfig {
        let field = try writableField(named: key)
        var config = try read(from: fileURL) ?? CLIConfig.defaultConfig
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MopeliumError.config("Config value for \(key) cannot be empty.")
        }

        switch field {
        case .baseURL:
            guard let url = URL(string: trimmed), url.scheme != nil else {
                throw MopeliumError.config("Invalid base_url: \(trimmed)")
            }
            config.baseURL = trimmed
        case .model:
            config.model = trimmed
        case .apiKeyEnv:
            config.apiKeyEnv = trimmed
        }
        try write(config, to: fileURL)
        return config
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            if let value, !value.isEmpty { return value }
        }
        return ""
    }

    private static func parseBool(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off": return false
        default: return nil
        }
    }
}
