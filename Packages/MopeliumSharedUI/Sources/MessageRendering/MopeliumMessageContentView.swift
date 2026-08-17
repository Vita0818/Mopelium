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
    private var viewportDwellTask: Task<Void, Never>?
    private(set) var pendingViewportDwellGeneration: UInt64?
    private(set) var completedViewportDwellGeneration: UInt64?
    private(set) var richAdmissionCount = 0

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
        cancelViewportDwell()
        completedViewportDwellGeneration = nil
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
        guard input.usesRichRenderer else {
            cancelViewportDwell()
            richState.deactivate()
            return
        }

        switch input.viewportAdmission {
        case .immediate:
            cancelViewportDwell()
            richAdmissionCount += 1
            richState.submit(request: input.richRequest)
        case .suspended:
            cancelViewportDwell()
            richState.suspend(keepingExact: input.richRequest)
        case let .idleDwell(generation):
            if completedViewportDwellGeneration == generation {
                cancelViewportDwell()
                richAdmissionCount += 1
                richState.submit(request: input.richRequest)
                return
            }
            richState.suspend(keepingExact: input.richRequest)
            scheduleViewportDwell(
                generation: generation,
                richState: richState)
        }
    }

    private func scheduleViewportDwell(
        generation: UInt64,
        richState: MopeliumMicrosoftMarkdownRenderState
    ) {
        guard pendingViewportDwellGeneration != generation
                || viewportDwellTask == nil else {
            return
        }
        cancelViewportDwell()
        pendingViewportDwellGeneration = generation
        viewportDwellTask = Task { @MainActor [weak self, weak richState] in
            do {
                try await Task.sleep(
                    for: MopeliumMarkdownRendererLimits.viewportIdleDwell)
            } catch {
                return
            }
            guard let self, let richState else { return }
            self.viewportDwellDidElapse(
                generation: generation,
                richState: richState)
        }
    }

    /// Kept internal so deterministic tests can drive the exact-revision gate
    /// without relying on wall-clock sleeps.
    func viewportDwellDidElapse(
        generation: UInt64,
        richState: MopeliumMicrosoftMarkdownRenderState
    ) {
        guard isVisible,
              pendingViewportDwellGeneration == generation,
              let input = lastAppliedInput,
              input.viewportAdmission
                == .idleDwell(generation: generation) else {
            return
        }
        viewportDwellTask?.cancel()
        viewportDwellTask = nil
        pendingViewportDwellGeneration = nil
        completedViewportDwellGeneration = generation
        richAdmissionCount += 1
        richState.submit(request: input.richRequest)
    }

    private func cancelViewportDwell() {
        viewportDwellTask?.cancel()
        viewportDwellTask = nil
        pendingViewportDwellGeneration = nil
    }
}

struct MopeliumMessageProjectionInput: Equatable {
    let rawRevision: MopeliumRawTextProjectionRevision
    let richRequest: MopeliumMarkdownRenderRequest
    let usesRichRenderer: Bool
    let viewportAdmission: MopeliumMessageViewportAdmission

    init(
        rawRevision: MopeliumRawTextProjectionRevision,
        richRequest: MopeliumMarkdownRenderRequest,
        usesRichRenderer: Bool,
        viewportAdmission: MopeliumMessageViewportAdmission = .immediate
    ) {
        self.rawRevision = rawRevision
        self.richRequest = richRequest
        self.usesRichRenderer = usesRichRenderer
        self.viewportAdmission = viewportAdmission
    }
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
    @Environment(\.mopeliumMessageViewportAdmission)
    private var viewportAdmission
    @Environment(\.mopeliumThreadScrollCoordinator)
    private var threadScrollCoordinator
    @Environment(\.mopeliumThreadRichSettleSource)
    private var threadRichSettleSource
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
                    .font(MopeliumTypography.chat(
                        MopeliumTypography.spec(for: .chat).nominalPointSize
                            * typographyRevision.scale))
                    .foregroundStyle(style.primaryText)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("mopelium.message.plain.\(messageID)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: finalRichSettleToken) { _, token in
            notifyRichDocumentCommit(token: token)
        }
        .onChange(of: threadRichSettleSource) { _, _ in
            notifyRichDocumentCommit(token: finalRichSettleToken)
        }
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
            notifyRichDocumentCommit(token: finalRichSettleToken)
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
            usesRichRenderer: renderPlan.usesRichRenderer,
            viewportAdmission: viewportAdmission)
    }

    private var finalRichSettleToken: MopeliumThreadRichSettleToken? {
        guard let published = richState.publishedDocument else {
            return nil
        }
        let revision = published.revision
        guard revision.isComplete,
              published.request == richRequest else {
            return nil
        }
        return .finalDocument(
            messageID: revision.messageID,
            contentUTF8Count: revision.rawText.utf8.count,
            contentHash: revision.rawText.hashValue,
            appearance: revision.appearance.rawValue,
            typography: revision.typography.rawValue,
            configurationRevision: revision.configurationRevision)
    }

    private func notifyRichDocumentCommit(
        token: MopeliumThreadRichSettleToken?
    ) {
        guard let token,
              let threadRichSettleSource else {
            return
        }
        threadScrollCoordinator?.richDocumentDidCommit(
            token: token,
            source: threadRichSettleSource)
    }
}
#endif
