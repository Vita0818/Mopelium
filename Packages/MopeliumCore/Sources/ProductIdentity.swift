import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Canonical product-owned names plus the bounded predecessor identity used
/// only at explicit migration and compatibility boundaries.
public enum MopeliumProductIdentity {
    public static let applicationSupportDirectoryName = "Mopelium"
    public static let configurationDirectoryName = "mopelium"
    public static let configurationFileName = "mopelium.json"
    public static let configurationJSONCFileName = "mopelium.jsonc"
    public static let workspaceStateDirectoryName = ".mopelium"

    public enum Legacy {
        public static let applicationSupportDirectoryName = "Intatis"
        public static let configurationDirectoryName = "intatis"
        public static let configurationFileName = "intatis.json"
        public static let configurationJSONCFileName = "intatis.jsonc"
        public static let workspaceStateDirectoryName = ".intatis"
        public static let configurationEnvironmentKey = "INTATIS_CONFIG"
        public static let authorizationFileEnvironmentKey = "INTATIS_AUTH_FILE"
    }
}

public enum ProductIdentityMigrationError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    case conflictingApplicationSupportRoots
    case unsafeApplicationSupportRoot
    case migrationFailed
    case commitUncertain

    public var errorDescription: String? {
        switch self {
        case .conflictingApplicationSupportRoots:
            return "Both Mopelium and legacy application-support roots exist; automatic merging is unsafe."
        case .unsafeApplicationSupportRoot:
            return "The application-support identity root is not a safe current-user directory."
        case .migrationFailed:
            return "The legacy application-support root could not be atomically migrated to Mopelium."
        case .commitUncertain:
            return "The application-support identity migration may have committed and requires disk reconciliation."
        }
    }
}

public enum ApplicationSupportIdentityMigrationResult:
    Equatable,
    Sendable
{
    case canonical(URL)
    case fresh(URL)
    case migrated(URL)
}

/// Performs the one-time top-level identity cutover without rewriting any
/// session or credential bytes. Both roots share one parent, so a successful
/// rename preserves every EventLog and projection inode while changing only
/// the product-owned directory entry.
public enum ApplicationSupportIdentityMigrator {
    public static let markerFileName =
        ".mopelium-product-identity-migration-v1.json"

    public static func prepare(
        in baseDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> ApplicationSupportIdentityMigrationResult {
        try fileManager.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true)
        let canonicalBase = try DurableOwnerOnlyFile.validateOwnedDirectory(
            at: baseDirectory)
        let canonical = canonicalBase.appendingPathComponent(
            MopeliumProductIdentity.applicationSupportDirectoryName,
            isDirectory: true)
        let legacy = canonicalBase.appendingPathComponent(
            MopeliumProductIdentity.Legacy.applicationSupportDirectoryName,
            isDirectory: true)
        let lock = canonicalBase.appendingPathComponent(
            ".mopelium-product-identity-migration.lock",
            isDirectory: false)

        return try DurableOwnerOnlyFile.withExclusiveLock(at: lock) {
            let canonicalExists = entryExistsNoFollow(canonical)
            let legacyExists = entryExistsNoFollow(legacy)

            if canonicalExists && legacyExists {
                throw ProductIdentityMigrationError
                    .conflictingApplicationSupportRoots
            }
            if canonicalExists {
                guard (try? DurableOwnerOnlyFile.validateOwnedDirectory(
                    at: canonical)) != nil else {
                    throw ProductIdentityMigrationError
                        .unsafeApplicationSupportRoot
                }
                return .canonical(canonical)
            }
            guard legacyExists else {
                return .fresh(canonical)
            }

            let validatedLegacy: URL
            do {
                validatedLegacy = try DurableOwnerOnlyFile
                    .validateOwnedDirectory(at: legacy)
            } catch {
                throw ProductIdentityMigrationError
                    .unsafeApplicationSupportRoot
            }
            guard let before = directoryIdentity(validatedLegacy) else {
                throw ProductIdentityMigrationError
                    .unsafeApplicationSupportRoot
            }

            guard rename(validatedLegacy.path, canonical.path) == 0 else {
                throw ProductIdentityMigrationError.migrationFailed
            }
            guard let after = directoryIdentity(canonical),
                  before.device == after.device,
                  before.inode == after.inode else {
                throw ProductIdentityMigrationError.commitUncertain
            }
            guard synchronizeDirectory(canonicalBase) else {
                throw ProductIdentityMigrationError.commitUncertain
            }

            let marker = canonical.appendingPathComponent(
                markerFileName,
                isDirectory: false)
            let markerObject: [String: Any] = [
                "schema": 1,
                "source": "legacy-intatis",
                "destination": "Mopelium",
            ]
            do {
                let data = try JSONSerialization.data(
                    withJSONObject: markerObject,
                    options: [.sortedKeys])
                try DurableOwnerOnlyFile.writeAtomically(
                    data,
                    to: marker)
            } catch {
                throw ProductIdentityMigrationError.commitUncertain
            }
            return .migrated(canonical)
        }
    }

    private static func entryExistsNoFollow(_ url: URL) -> Bool {
        var status = stat()
        if lstat(url.path, &status) == 0 { return true }
        return errno != ENOENT
    }

    private static func directoryIdentity(
        _ url: URL
    ) -> (device: UInt64, inode: UInt64)? {
        var status = stat()
        guard lstat(url.path, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFDIR else {
            return nil
        }
        return (UInt64(status.st_dev), UInt64(status.st_ino))
    }

    private static func synchronizeDirectory(_ url: URL) -> Bool {
        let descriptor = open(
            url.path,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return false }
        defer { _ = close(descriptor) }
        return fsync(descriptor) == 0
    }
}
