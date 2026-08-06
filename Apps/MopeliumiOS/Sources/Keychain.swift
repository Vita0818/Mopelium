#if canImport(SwiftUI)
import Foundation
import MopeliumCore
import MopeliumProviders

/// Resolves provider secrets exclusively from process environment variables.
///
/// The resolver intentionally treats every legacy non-environment reference as
/// the configured default environment variable. It never reads Keychain,
/// config, auth, or arbitrary secret files and never accepts a secret for
/// persistence.
public final class ConfigSecretResolver: SecretResolver, @unchecked Sendable {
    public static let defaultAPIKeyEnvironmentVariable = "MOPELIUM_API_KEY"
    public static let APIKeyEnvironmentVariableSelector = "MOPELIUM_API_KEY_ENV"

    public init() {}

    public func secret(for ref: KeychainRef) async throws -> String {
        let variableName = Self.environmentVariableName(for: ref)
        guard let value = ProcessInfo.processInfo.environment[variableName],
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MopeliumError.notFound("environment secret '\(variableName)'")
        }
        return value
    }

    public static func exists(_ ref: KeychainRef) -> Bool {
        let variableName = environmentVariableName(for: ref)
        return !(ProcessInfo.processInfo.environment[variableName] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func defaultAPIKeyEnvironmentVariableName(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        normalizedEnvironmentVariableName(
            environment[APIKeyEnvironmentVariableSelector],
            fallback: defaultAPIKeyEnvironmentVariable)
    }

    public static func environmentVariableName(for ref: KeychainRef) -> String {
        let fallback = defaultAPIKeyEnvironmentVariableName()
        switch ref.source {
        case .environment:
            return normalizedEnvironmentVariableName(ref.account, fallback: fallback)
        default:
            return fallback
        }
    }

    public static func normalizedEnvironmentRef(_ ref: KeychainRef) -> KeychainRef {
        .environment(environmentVariableName(for: ref))
    }

    public static func normalizedEnvironmentVariableName(
        _ rawValue: String?,
        fallback: String? = nil
    ) -> String {
        let fallbackName = fallback.flatMap(validEnvironmentVariableName)
            ?? defaultAPIKeyEnvironmentVariable
        return validEnvironmentVariableName(rawValue) ?? fallbackName
    }

    public static func isValidEnvironmentVariableName(_ value: String) -> Bool {
        validEnvironmentVariableName(value) != nil
    }

    private static func validEnvironmentVariableName(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              let first = value.unicodeScalars.first,
              first == "_" || CharacterSet.letters.contains(first),
              value.unicodeScalars.dropFirst().allSatisfy({
                  $0 == "_" || CharacterSet.alphanumerics.contains($0)
              }) else {
            return nil
        }
        return value
    }
}
#endif
