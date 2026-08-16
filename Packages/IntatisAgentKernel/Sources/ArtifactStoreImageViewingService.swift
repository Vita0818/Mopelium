import Foundation
import IntatisArtifacts
import IntatisTools

public enum WorkspaceImageViewingError:
    Error,
    Equatable,
    Sendable,
    LocalizedError
{
    case unsupportedFileType
    case notRegularFile
    case emptyFile
    case fileTooLarge(maximumBytes: Int)
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "view_image supports only workspace .png, .jpg, and .jpeg files"
        case .notRegularFile:
            return "view_image requires one regular workspace file"
        case .emptyFile:
            return "view_image cannot view an empty file"
        case .fileTooLarge(let maximumBytes):
            return "view_image input exceeds the \(maximumBytes)-byte image limit"
        case .unreadable:
            return "view_image could not read the workspace image"
        }
    }
}

/// Thin exact-session adapter from a reviewed workspace file to the existing
/// ArtifactStore/ImageIO image pipeline. It performs bounded byte transport;
/// image type, completeness, dimensions, and pixels are validated by the
/// shared `ArtifactImageResolver` rather than by a second parser here.
public struct ArtifactStoreImageViewingService:
    WorkspaceImageViewingService,
    Sendable
{
    private let store: ArtifactStore
    private let policy: ArtifactImageValidationPolicy

    public init(
        store: ArtifactStore,
        policy: ArtifactImageValidationPolicy = ArtifactImageValidationPolicy()
    ) {
        self.store = store
        self.policy = policy
    }

    public func viewImage(
        at url: URL
    ) async throws -> ViewedWorkspaceImage {
        let type = try Self.imageType(for: url)
        let maximumBytes = min(
            policy.maximumImageBytes,
            policy.maximumTotalBytes)
        guard maximumBytes > 0, maximumBytes < Int.max else {
            throw ArtifactImageResolutionError.invalidPolicy
        }

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
            ])
        } catch {
            throw WorkspaceImageViewingError.unreadable
        }
        guard values.isRegularFile == true else {
            throw WorkspaceImageViewingError.notRegularFile
        }
        if let fileSize = values.fileSize {
            guard fileSize > 0 else {
                throw WorkspaceImageViewingError.emptyFile
            }
            guard fileSize <= maximumBytes else {
                throw WorkspaceImageViewingError.fileTooLarge(
                    maximumBytes: maximumBytes)
            }
        }

        let data = try await Self.readBounded(
            url,
            maximumBytes: maximumBytes)
        try Task.checkCancellation()
        let reference = try await store.add(
            kind: .image,
            mime: type.mimeType,
            data: data,
            ext: type.fileExtension,
            producedBy: "view_image")
        let verified = try await ArtifactImageResolver(
            store: store,
            policy: policy
        ).resolve(reference.id)
        return ViewedWorkspaceImage(
            artifactID: verified.artifactID,
            mimeType: verified.mimeType,
            byteCount: verified.byteCount,
            sha256: verified.sha256)
    }

    private static func imageType(
        for url: URL
    ) throws -> (mimeType: String, fileExtension: String) {
        switch url.pathExtension.lowercased() {
        case "png":
            return ("image/png", "png")
        case "jpg", "jpeg":
            return ("image/jpeg", "jpg")
        default:
            throw WorkspaceImageViewingError.unsupportedFileType
        }
    }

    private static func readBounded(
        _ url: URL,
        maximumBytes: Int
    ) async throws -> Data {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw WorkspaceImageViewingError.unreadable
        }
        defer { try? handle.close() }

        var data = Data()
        do {
            while data.count <= maximumBytes {
                try Task.checkCancellation()
                let remaining = maximumBytes + 1 - data.count
                guard remaining > 0,
                      let chunk = try handle.read(
                        upToCount: min(1_048_576, remaining)),
                      !chunk.isEmpty else {
                    break
                }
                data.append(chunk)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WorkspaceImageViewingError.unreadable
        }
        guard !data.isEmpty else {
            throw WorkspaceImageViewingError.emptyFile
        }
        guard data.count <= maximumBytes else {
            throw WorkspaceImageViewingError.fileTooLarge(
                maximumBytes: maximumBytes)
        }
        return data
    }
}
