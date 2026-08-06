#if canImport(SwiftUI) && canImport(SwiftStreamingMarkdown)
import Combine
import Foundation
import SwiftUI
import SwiftStreamingMarkdown

public enum MopeliumMessageRenderingPolicy: Sendable {
    case plainText
    case richText
}

/// A non-publishing lifecycle gate for one message facade. SwiftUI may rebuild
/// the value view for changes emitted by either projection; those rebuilds must
/// not resubmit the same raw snapshot or restart the same Markdown parse.
@MainActor
final class MopeliumMessageProjectionLifecycleGate: ObservableObject {
    private var isVisible = false
    private var lastAppliedInput: MopeliumMessageProjectionInput?

    func activate(
        _ input: MopeliumMessageProjectionInput,
        rawState: MopeliumRawTextProjectionState,
        richState: MopeliumMicrosoftMarkdownRenderState
    ) {
        guard !isVisible else {
            receive(input, rawState: rawState, richState: richState)
            return
        }
        isVisible = true
        lastAppliedInput = nil
        apply(input, rawState: rawState, richState: richState)
    }

    func receive(
        _ input: MopeliumMessageProjectionInput,
        rawState: MopeliumRawTextProjectionState,
        richState: MopeliumMicrosoftMarkdownRenderState
    ) {
        guard isVisible else { return }
        apply(input, rawState: rawState, richState: richState)
    }

    func deactivate(
        rawState: MopeliumRawTextProjectionState,
        richState: MopeliumMicrosoftMarkdownRenderState
    ) {
        isVisible = false
        lastAppliedInput = nil
        richState.deactivate()
        rawState.deactivate()
    }

    private func apply(
        _ input: MopeliumMessageProjectionInput,
        rawState: MopeliumRawTextProjectionState,
        richState: MopeliumMicrosoftMarkdownRenderState
    ) {
        guard input != lastAppliedInput else { return }
        // Record before touching either ObservableObject so a SwiftUI rebuild
        // caused by publication is already a no-op when its Just emits.
        lastAppliedInput = input
        rawState.submit(input.rawRevision)
        if input.usesRichRenderer {
            richState.submit(request: input.richRequest)
        } else {
            richState.deactivate()
        }
    }
}

struct MopeliumMessageProjectionInput: Equatable {
    let rawRevision: MopeliumRawTextProjectionRevision
    let richRequest: MopeliumMarkdownRenderRequest
    let usesRichRenderer: Bool
}

/// Renderer-neutral product facade shared by Chat, Code, Cowork, and iOS.
/// Raw text remains visible until an admitted upstream projection is ready.
public struct MopeliumMessageContentView: View {
    let messageID: String
    let rawText: String
    let isComplete: Bool
    let policy: MopeliumMessageRenderingPolicy
    let style: MopeliumThreadStyle

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var lifecycleGate = MopeliumMessageProjectionLifecycleGate()
    @StateObject private var richState = MopeliumMicrosoftMarkdownRenderState()
    @StateObject private var rawState: MopeliumRawTextProjectionState
    @AppStorage(MopeliumMessageRendererMode.defaultsKey)
    private var persistedRendererMode = MopeliumMessageRendererMode.microsoft.rawValue

    public init(
        messageID: String,
        rawText: String,
        isComplete: Bool,
        policy: MopeliumMessageRenderingPolicy,
        style: MopeliumThreadStyle
    ) {
        self.messageID = messageID
        self.rawText = rawText
        self.isComplete = isComplete
        self.policy = policy
        self.style = style
        _rawState = StateObject(wrappedValue: MopeliumRawTextProjectionState(
            revision: MopeliumRawTextProjectionRevision(
                activation: MopeliumRawTextProjectionActivation(
                    messageID: messageID,
                    lane: policy == .richText ? .richFallback : .plain),
                rawText: rawText,
                isComplete: isComplete)))
    }

    public var body: some View {
        Group {
            if renderPlan.usesRichRenderer,
               let published = richState.publishedDocument,
               published.request == richRequest {
                DocumentView(
                    renderableDocument: published.document,
                    config: published.displayConfiguration)
                    .environment(\.openURL, OpenURLAction { url in
                        guard MopeliumMarkdownLinkPolicy.allows(url) else { return .discarded }
                        return .systemAction(url)
                    })
                    .accessibilityIdentifier("mopelium.message.microsoft.\(messageID)")
            } else {
                Text(verbatim: rawState.text(for: rawProjectionRevision))
                    .font(.system(size: 15 * typographyRevision.scale))
                    .foregroundStyle(style.primaryText)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("mopelium.message.plain.\(messageID)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(Just(projectionInput)) { input in
            lifecycleGate.receive(
                input,
                rawState: rawState,
                richState: richState)
        }
        .onAppear {
            // Keep one raw projection alive even while a rich document is on
            // screen. A rich→fallback transition therefore inherits the same
            // bounded stream instead of recreating an exact Text every token.
            lifecycleGate.activate(
                projectionInput,
                rawState: rawState,
                richState: richState)
        }
        .onDisappear {
            lifecycleGate.deactivate(
                rawState: rawState,
                richState: richState)
        }
    }

    private var rendererMode: MopeliumMessageRendererMode {
        MopeliumMessageRendererMode.resolve(persistedRawValue: persistedRendererMode)
    }

    private var renderPlan: MopeliumMessageRenderPlan {
        MopeliumMessageRenderPlan.resolve(
            rawText: rawText,
            isComplete: isComplete,
            policyIsRich: policy == .richText,
            rendererMode: rendererMode)
    }

    private var rawProjectionRevision: MopeliumRawTextProjectionRevision {
        MopeliumRawTextProjectionRevision(
            activation: MopeliumRawTextProjectionActivation(
                messageID: messageID,
                lane: renderPlan.usesRichRenderer ? .richFallback : .plain),
            rawText: rawText,
            isComplete: isComplete)
    }

    private var renderRevision: MopeliumMarkdownRenderRevision {
        MopeliumMarkdownRenderRevision(
            messageID: messageID,
            rawText: rawText,
            isComplete: isComplete,
            appearance: MopeliumMarkdownAppearanceRevision(colorScheme),
            typography: typographyRevision,
            configurationRevision: MopeliumMarkdownRendererLimits.configurationRevision)
    }

    private var typographyRevision: MopeliumMarkdownTypographyRevision {
        MopeliumMarkdownTypographyRevision(dynamicTypeSize)
    }

    private var richRequest: MopeliumMarkdownRenderRequest {
        MopeliumMarkdownRenderRequest(
            revision: renderRevision,
            style: MopeliumMarkdownStyleSnapshot(style))
    }

    private var projectionInput: MopeliumMessageProjectionInput {
        MopeliumMessageProjectionInput(
            rawRevision: rawProjectionRevision,
            richRequest: richRequest,
            usesRichRenderer: renderPlan.usesRichRenderer)
    }
}
#endif
