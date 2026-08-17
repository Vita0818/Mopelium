import Foundation
import MopeliumCore
import MopeliumProtocol

/// One model operation mapped to one host image-viewing operation. This tool
/// only validates the reviewed workspace path and forwards it to the injected
/// exact-session service; image decoding and durable media transport stay out
/// of the model-facing adapter.
public struct ViewImageTool: Tool {
    public init() {}

    public static let canonicalPermission: String? = "filesystem.read"
    public static let descriptor = ToolDescriptor(
        name: "view_image",
        description: "View one existing PNG or JPEG file in the workspace by passing its pixels to the current model. This tool does not perform OCR, editing, resizing, or conversion.",
        sideEffect: .readOnly,
        parameters: Schema.object(
            ["path": Schema.nonEmptyString],
            required: ["path"]))

    struct Args: Decodable {
        let path: String
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        (try? args.decode(Args.self).path).map { [$0] } ?? []
    }

    public func permissionIntent(
        _ args: ToolArgs,
        workspaceRoot: URL
    ) -> PermissionIntent {
        PermissionIntent(
            action: "filesystem.read",
            resources: touchedPaths(args).map {
                PermissionResource(
                    kind: .workspacePath,
                    value: $0,
                    access: .readOnly)
            },
            metadata: ["operation": .string("view_existing_image")],
            dataEffects: [.read],
            replayPolicy: .safeToReplay)
    }

    public func execute(
        _ args: ToolArgs,
        in context: ToolContext
    ) async throws -> ToolObservation {
        let value = try args.decode(Args.self)
        _ = try validateManagedWorkspaceAccess(
            readablePaths: [value.path],
            writablePaths: [],
            cwd: context.workspaceRoot,
            workspaceLease: context.workspaceLease,
            subject: Self.descriptor.name)
        let url = try PathConfinement.resolve(
            value.path,
            within: context.workspaceRoot)
        guard let imageViewer = context.imageViewer else {
            throw ToolExecutionRejectedWithoutSideEffect(
                code: "view_image_unavailable",
                message: "view_image is not configured for this session")
        }

        let image = try await imageViewer.viewImage(at: url)
        let text = "Viewed \(value.path) as \(image.mimeType) (\(image.byteCount) bytes)."
        return ToolObservation(
            text: text,
            structuredResult: MCPStructuredToolResult(
                content: [
                    MCPContentBlock(kind: .text, text: text),
                    MCPContentBlock(
                        kind: .imageReference,
                        artifactID: image.artifactID,
                        mimeType: image.mimeType,
                        byteCount: image.byteCount,
                        sha256: image.sha256),
                ],
                totalByteCount: image.byteCount))
    }
}
