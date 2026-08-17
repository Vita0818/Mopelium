#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import MopeliumSharedUI

/// The macOS composer attachment control shared verbatim by Chat and Cowork.
/// Surface-specific code supplies only the current draft and its callbacks.
struct MopeliumMacComposerAttachmentAccessory: View {
    let attachments: [MopeliumComposerDraftAttachment]
    let accessibilityPrefix: String
    var isBusy = false
    var isDisabled = false
    let onAttach: () -> Void
    let onRemove: (MopeliumComposerDraftAttachment.ID) -> Void

    var body: some View {
        HStack(
            alignment: .center,
            spacing: MopeliumComposerControlMetrics.rowSpacing
        ) {
            Button(action: onAttach) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(
                            width: MopeliumComposerControlMetrics.iconLabelExtent,
                            height: MopeliumComposerControlMetrics.iconLabelExtent)
                } else {
                    Label(
                        MopeliumLocalization.string("Attach files"),
                        systemImage: "paperclip")
                        .mopeliumComposerIconLabel()
                }
            }
            .mopeliumCompactIconButton()
            .help(MopeliumLocalization.string("Attach files"))
            .accessibilityLabel(MopeliumLocalization.string("Attach files"))
            .accessibilityIdentifier("\(accessibilityPrefix).composer.attach")
            .disabled(isDisabled || isBusy)

            if !attachments.isEmpty {
                Menu {
                    ForEach(attachments) { attachment in
                        Button(MopeliumLocalization.format(
                            "Remove %@",
                            attachment.name)) {
                            onRemove(attachment.id)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(MopeliumLocalization.format(
                            "%lld attached",
                            Int64(attachments.count)))
                            .font(MopeliumTypography.body(13, .semibold))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .mopeliumComposerSelectionLabel()
                }
                .mopeliumComposerSelectionMenu()
                .accessibilityIdentifier(
                    "\(accessibilityPrefix).composer.attachments")
                .disabled(isDisabled || isBusy)
            }
        }
        .frame(
            minHeight: MopeliumComposerControlMetrics.controlHeight,
            alignment: .center)
    }
}

private struct MopeliumMacComposerAttachmentImportModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onImport: ([URL]) -> Void
    let onFailure: (Error) -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.data, .content],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    onImport(urls)
                case .failure(let error):
                    onFailure(error)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard !urls.isEmpty else { return false }
                onImport(urls)
                return true
            }
    }
}

extension View {
    func mopeliumComposerAttachmentImport(
        isPresented: Binding<Bool>,
        onImport: @escaping ([URL]) -> Void,
        onFailure: @escaping (Error) -> Void
    ) -> some View {
        modifier(MopeliumMacComposerAttachmentImportModifier(
            isPresented: isPresented,
            onImport: onImport,
            onFailure: onFailure))
    }
}
#endif
