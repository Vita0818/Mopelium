import XCTest
@testable import MopeliumCore

final class ProductIdentityMigrationTests: XCTestCase {
    func testFreshRootReturnsCanonicalDestinationWithoutCreatingIt() throws {
        let base = try temporaryBase()
        defer { try? FileManager.default.removeItem(at: base) }

        let result = try ApplicationSupportIdentityMigrator.prepare(in: base)
        let expected = base.appendingPathComponent("Mopelium", isDirectory: true)

        XCTAssertEqual(result, .fresh(expected))
        XCTAssertFalse(FileManager.default.fileExists(atPath: expected.path))
    }

    func testLegacyRootMovesAtomicallyAndPreservesSessionBytes() throws {
        let base = try temporaryBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = base.appendingPathComponent("Intatis", isDirectory: true)
        try FileManager.default.createDirectory(
            at: legacy.appendingPathComponent("sess_legacy", isDirectory: true),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let eventBytes = Data("{\"seq\":1}\n".utf8)
        let eventURL = legacy
            .appendingPathComponent("sess_legacy", isDirectory: true)
            .appendingPathComponent("events.jsonl")
        try eventBytes.write(to: eventURL)

        let result = try ApplicationSupportIdentityMigrator.prepare(in: base)
        let canonical = base.appendingPathComponent("Mopelium", isDirectory: true)

        XCTAssertEqual(result, .migrated(canonical))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(
            try Data(contentsOf: canonical
                .appendingPathComponent("sess_legacy", isDirectory: true)
                .appendingPathComponent("events.jsonl")),
            eventBytes)
        XCTAssertNotNil(try DurableOwnerOnlyFile.read(from: canonical
            .appendingPathComponent(
                ApplicationSupportIdentityMigrator.markerFileName)))
    }

    func testCanonicalAndLegacyRootsFailClosedInsteadOfMerging() throws {
        let base = try temporaryBase()
        defer { try? FileManager.default.removeItem(at: base) }
        for name in ["Mopelium", "Intatis"] {
            try FileManager.default.createDirectory(
                at: base.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }

        XCTAssertThrowsError(
            try ApplicationSupportIdentityMigrator.prepare(in: base)
        ) { error in
            XCTAssertEqual(
                error as? ProductIdentityMigrationError,
                .conflictingApplicationSupportRoots)
        }
    }

    func testLegacyLeafSymlinkIsRejected() throws {
        let base = try temporaryBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.createSymbolicLink(
            at: base.appendingPathComponent("Intatis", isDirectory: true),
            withDestinationURL: outside)

        XCTAssertThrowsError(
            try ApplicationSupportIdentityMigrator.prepare(in: base)
        ) { error in
            XCTAssertEqual(
                error as? ProductIdentityMigrationError,
                .unsafeApplicationSupportRoot)
        }
    }

    private func temporaryBase() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "mopelium-product-identity-tests-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return base
    }
}
