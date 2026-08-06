#if canImport(SwiftUI)
import Foundation
import MopeliumCore
import MopeliumProviders

/// Resolves every provider credential from the process environment.
///
/// Non-environment references are retained in the shared wire model for
/// backwards-compatible decoding, but the macOS app deliberately maps them to
/// `MOPELIUM_API_KEY` (or the variable named by `MOPELIUM_API_KEY_ENV`). It
/// never reads credentials from config files, auth files, arbitrary files, or
/// the macOS Keychain.
public final class ConfigSecretResolver: SecretResolver, @unchecked Sendable {
    public static let fallbackAPIKeyEnvironmentName = "MOPELIUM_API_KEY"
    public static let APIKeyEnvironmentOverrideName = "MOPELIUM_API_KEY_ENV"

    public init() {}

    public func secret(for ref: KeychainRef) async throws -> String {
        let environmentName = Self.environmentName(for: ref)
        guard let value = ProcessInfo.processInfo.environment[environmentName],
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MopeliumError.notFound("environment secret '\(environmentName)'")
        }
        return value
    }

    /// Kept for callers that refresh settings. Environment values are never
    /// cached, so changes made before the next process launch are not persisted.
    public func clearCache() {}

    public static func exists(_ ref: KeychainRef) -> Bool {
        let environmentName = environmentName(for: ref)
        return !(ProcessInfo.processInfo.environment[environmentName] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func environmentName(for ref: KeychainRef,
                                environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if ref.source == .environment,
           let explicitName = validEnvironmentName(ref.account) {
            return explicitName
        }
        return defaultAPIKeyEnvironmentName(environment: environment)
    }

    static func defaultAPIKeyEnvironmentName(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        validEnvironmentName(environment[APIKeyEnvironmentOverrideName])
            ?? fallbackAPIKeyEnvironmentName
    }

    static func validEnvironmentName(_ raw: String?) -> String? {
        guard let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              name.range(
                  of: #"^[A-Za-z_][A-Za-z0-9_]*$"#,
                  options: .regularExpression) != nil else {
            return nil
        }
        return name
    }
}
#endif
