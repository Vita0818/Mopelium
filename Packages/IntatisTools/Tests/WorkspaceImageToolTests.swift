import Foundation
import XCTest
import IntatisCore
import IntatisProtocol
@testable import IntatisTools

private actor RecordingWorkspaceImageViewer:
    WorkspaceImageViewingService
{
    private var viewedURLs: [URL] = []
    private let result: ViewedWorkspaceImage

    init(result: ViewedWorkspaceImage) {
        self.result = result
    }

    func viewImage(at url: URL) async throws -> ViewedWorkspaceImage {
        viewedURLs.append(url)
        return result
    }

    func urls() -> [URL] {
        viewedURLs
    }
}

final class WorkspaceImageToolTests: XCTestCase {
    func testDescriptorIsPathOnlyAndReadOnly() {
        XCTAssertEqual(ViewImageTool.descriptor.name, "view_image")
        XCTAssertEqual(ViewImageTool.descriptor.sideEffect, .readOnly)
        XCTAssertEqual(ViewImageTool.canonicalPermission, "filesystem.read")
        XCTAssertEqual(
            ViewImageTool.descriptor.parameters,
            Schema.object(
                ["path": Schema.nonEmptyString],
                required: ["path"]))

        let intent = ViewImageTool().permissionIntent(
            ToolArgs(raw: #"{"path":"page.png"}"#),
            workspaceRoot: URL(fileURLWithPath: "/workspace"))
        XCTAssertEqual(intent.action, "filesystem.read")
        XCTAssertEqual(intent.dataEffects, [.read])
        XCTAssertEqual(intent.replayPolicy, .safeToReplay)
        XCTAssertEqual(intent.resources, [
            PermissionResource(
                kind: .workspacePath,
                value: "page.png",
                access: .readOnly),
        ])
    }

    func testExecutionOnlyForwardsResolvedPathAndReturnsImageReference()
        async throws
    {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let path = workspace.appendingPathComponent("page.png")
        try Data([0x00]).write(to: path)
        let result = ViewedWorkspaceImage(
            artifactID: ArtifactID(rawValue: "artifact-viewed-image"),
            mimeType: "image/png",
            byteCount: 123,
            sha256: String(repeating: "a", count: 64))
        let viewer = RecordingWorkspaceImageViewer(result: result)
        let context = ToolContext(
            workspaceRoot: workspace,
            imageViewer: viewer)

        let observation = try await ViewImageTool().execute(
            ToolArgs(raw: #"{"path":"page.png"}"#),
            in: context)

        let viewedURLs = await viewer.urls()
        XCTAssertEqual(viewedURLs, [path.standardizedFileURL])
        XCTAssertEqual(observation.changedFiles, nil)
        XCTAssertEqual(observation.structuredResult?.totalByteCount, 123)
        XCTAssertEqual(observation.structuredResult?.content.count, 2)
        XCTAssertEqual(
            observation.structuredResult?.content.last,
            MCPContentBlock(
                kind: .imageReference,
                artifactID: result.artifactID,
                mimeType: result.mimeType,
                byteCount: result.byteCount,
                sha256: result.sha256))
    }

    func testExecutionFailsClosedWhenSessionViewerIsMissing() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try Data([0x00]).write(
            to: workspace.appendingPathComponent("page.png"))

        do {
            _ = try await ViewImageTool().execute(
                ToolArgs(raw: #"{"path":"page.png"}"#),
                in: ToolContext(workspaceRoot: workspace))
            XCTFail("view_image unexpectedly ran without a session viewer")
        } catch let error as ToolExecutionRejectedWithoutSideEffect {
            XCTAssertEqual(error.code, "view_image_unavailable")
        }
    }

    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "intatis-view-image-tool-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true)
        return url
    }
}
