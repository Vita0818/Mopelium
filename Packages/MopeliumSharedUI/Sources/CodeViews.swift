#if canImport(SwiftUI)
import Foundation
import SwiftUI
import MopeliumCore
import MopeliumProtocol
import MopeliumConversation

private func mopeliumLocalizedAgentState(_ state: String) -> String {
    switch state {
    case AgentState.idle.rawValue:
        return MopeliumLocalization.string("Idle")
    case AgentState.thinking.rawValue:
        return MopeliumLocalization.string("Thinking")
    case AgentState.tool.rawValue:
        return MopeliumLocalization.string("Tool")
    case AgentState.blocked.rawValue:
        return MopeliumLocalization.string("Blocked")
    default:
        return state
    }
}

/// Presentational Code thread (v0.2). All data + callbacks are injected, so the
/// kernel-driving view model lives in the app, not here (keeps SharedUI free of
/// Tools/Permission/AgentKernel dependencies).
public struct CodeShell: View {
    private let displayedItems: [CodeItem]
    private let threadErrors: [MopeliumThreadErrorEntry]
    private let presentationScope: MopeliumThreadPresentationScope
    private let sessionTitle: String
    private let thinkingPhaseID: String
    private let pending: PendingPermission?
    private let permissionNotice: PermissionResolutionNotice?
    private let latestTurnStats: TurnStatsSnapshot?
    private let isWorking: Bool
    private let workspaceName: String
    private let agentState: String
    private let threadStyle: MopeliumThreadStyle
    private let onShowSessions: (() -> Void)?
    private let onNewSession: (() -> Void)?
    private let composerAccessory: AnyView?
    private let composerTrailingAction:
        MopeliumThreadComposerSecondaryAction?
    private let headerActions: [MopeliumThreadHeaderAction]
    @Binding private var input: String
    private let onSend: () -> Void
    private let onCancelCurrent: (() -> Void)?
    private let onResolve: (PermissionResponseAction) -> Void
    @Binding private var showsInspector: Bool
    @StateObject private var scrollCoordinator = MopeliumThreadScrollCoordinator()
    @State private var historySelection: MopeliumThreadHistorySelection?

    public init(items: [CodeItem],
                presentationScope: MopeliumThreadPresentationScope,
                sessionTitle: String = MopeliumLocalization.string("Code"),
                thinkingScopeID: String = "code",
                pending: PendingPermission?,
                permissionNotice: PermissionResolutionNotice? = nil,
                latestTurnStats: TurnStatsSnapshot? = nil,
                isWorking: Bool,
                workspaceName: String,
                agentState: String,
                errorTexts: [String] = [],
                threadStyle: MopeliumThreadStyle = .standard(.light),
                splitLayout: MopeliumSplitColumnLayout = .workspace,
                onShowSessions: (() -> Void)? = nil,
                onNewSession: (() -> Void)? = nil,
                composerAccessory: AnyView? = nil,
                composerTrailingAction:
                    MopeliumThreadComposerSecondaryAction? = nil,
                headerActions: [MopeliumThreadHeaderAction] = [],
                showsInspector: Binding<Bool>,
                input: Binding<String>,
                onSend: @escaping () -> Void,
                onCancelCurrent: (() -> Void)? = nil,
                onResolve: @escaping (PermissionResponseAction) -> Void) {
        self.displayedItems = MopeliumThreadErrorPresentation.transcriptItems(
            MopeliumExecutionTracePresentation.displayedItems(items))
        self.threadErrors = MopeliumThreadErrorPresentation.errors(
            items: items,
            errorTexts: errorTexts)
        self.presentationScope = presentationScope
        self.sessionTitle = sessionTitle
        self.thinkingPhaseID = "\(thinkingScopeID):\(items.last?.id ?? "initial")"
        self.pending = pending
        self.permissionNotice = permissionNotice
        self.latestTurnStats = latestTurnStats
        self.isWorking = isWorking
        self.workspaceName = workspaceName
        self.agentState = agentState
        self.threadStyle = threadStyle
        self.onShowSessions = onShowSessions
        self.onNewSession = onNewSession
        self.composerAccessory = composerAccessory
        self.composerTrailingAction = composerTrailingAction
        self.headerActions = headerActions
        self._showsInspector = showsInspector
        self._input = input
        self.onSend = onSend
        self.onCancelCurrent = onCancelCurrent
        self.onResolve = onResolve
        _ = splitLayout
    }

    private var permissionBlocksComposer: Bool {
        guard let pending else { return false }
        return pending.state == .livePending || pending.state == .resolving
    }

    public var body: some View {
        GeometryReader { proxy in
            content(rawWidth: proxy.size.width)
        }
    }

    private func content(rawWidth: CGFloat) -> some View {
        let inspectorLayout = MopeliumWorkspaceInspectorLayoutPolicy.resolve(
            availableWidth: rawWidth,
            isRequested: showsInspector,
            activationWidth: 940,
            minimumThreadWidth: 620,
            minimumInspectorWidth: 260,
            idealInspectorWidth: 292,
            maximumInspectorWidth: 360)

        return HStack(spacing: 0) {
            threadColumn(
                layout: MopeliumThreadContentLayout(
                    rawWidth: inspectorLayout.threadWidth),
                inspectorIsAvailable: rawWidth >= 940)
                .frame(width: inspectorLayout.threadWidth)
                .frame(maxHeight: .infinity)
            if inspectorLayout.isVisible {
                Divider()
                CodeInspectorView(
                    workspaceName: workspaceName,
                    agentState: agentState,
                    itemCount: displayedItems.count,
                    pending: pending,
                    errors: threadErrors,
                    style: threadStyle)
                    .frame(width: inspectorLayout.inspectorWidth)
                    .frame(maxHeight: .infinity)
                    .background(.bar)
                    .accessibilityIdentifier("code.inspector")
            }
        }
    }

    private func threadColumn(
        layout: MopeliumThreadContentLayout,
        inspectorIsAvailable: Bool
    ) -> some View {
        VStack(spacing: 0) {
            header(
                layout: layout,
                inspectorIsAvailable: inspectorIsAvailable)
            thread(layout: layout)
            permissionArea(layout: layout)
            composerArea(layout: layout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(
        layout: MopeliumThreadContentLayout,
        inspectorIsAvailable: Bool
    ) -> some View {
        MopeliumWorkspaceThreadHeader(
            title: sessionTitle,
            subtitle: nil,
            style: threadStyle,
            actions: headerActions + [inspectorAction(
                isAvailable: inspectorIsAvailable)])
        .frame(maxWidth: layout.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private func inspectorAction(
        isAvailable: Bool
    ) -> MopeliumThreadHeaderAction {
        let title = showsInspector && isAvailable
            ? MopeliumLocalization.string("Hide Inspector")
            : MopeliumLocalization.string("Show Inspector")
        return MopeliumThreadHeaderAction(
            title: title,
            systemImage: "sidebar.right",
            isDisabled: !isAvailable,
            isIconOnly: true,
            help: title,
            accessibilityIdentifier: "code.inspector.toggle") {
                guard isAvailable else { return }
                showsInspector.toggle()
            }
    }

    @ViewBuilder private func thread(layout: MopeliumThreadContentLayout) -> some View {
        if displayedItems.isEmpty && !showsThinkingIndicator {
            CodeEmptyThreadView(style: threadStyle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, layout.horizontalPadding)
        } else {
            let historyWindow = threadHistoryWindow
            let pageScope = threadPresentationScope
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if historyWindow.hasEarlier || historyWindow.hasLater {
                            MopeliumThreadHistoryPager(
                                lowerBound: historyWindow.lowerBound,
                                upperBound: historyWindow.upperBound,
                                totalCount: historyWindow.totalCount,
                                hasEarlier: historyWindow.hasEarlier,
                                hasLater: historyWindow.hasLater,
                                accessibilityPrefix: "code.history",
                                onEarlier: {
                                    selectHistoryWindow(
                                        historyWindow.earlierRequestedUpperBound)
                                },
                                onNewer: {
                                    selectHistoryWindow(
                                        historyWindow.newerRequestedUpperBound)
                                },
                                onLatest: {
                                    selectHistoryWindow(nil)
                                })
                        }
                        ForEach(historyWindow.items) { item in
                            CodeItemRow(item: item, style: threadStyle, layout: layout)
                                .id(item.id)
                        }
                        if showsVisibleThinkingIndicator {
                            MopeliumThreadThinkingRow(
                                layout: layout,
                                style: threadStyle,
                                phaseID: thinkingPhaseID)
                                .id("mopelium-code-thinking-\(thinkingPhaseID)")
                        }
                        Color.clear
                            .frame(height: 1)
                            .padding(.bottom, 16)
                            .id(MopeliumThreadBottomAnchorID(scope: pageScope))
                            .onScrollVisibilityChange(threshold: 0.99) {
                                isVisible in
                                scrollCoordinator
                                    .enqueueBottomAnchorVisibility(
                                        isVisible,
                                        scope: pageScope)
                            }
                    }
                    .environment(
                        \.mopeliumMessageViewportAdmission,
                        scrollCoordinator.effectiveViewportAdmission(
                            for: pageScope,
                            defersUntilInitialRestore:
                                defersRichUntilInitialRestore))
                    .environment(
                        \.mopeliumThreadScrollCoordinator,
                        scrollCoordinator)
                    .environment(
                        \.mopeliumThreadRichSettleSource,
                        scrollCoordinator.effectiveRichSettleSource(
                            for: pageScope))
                    .frame(width: layout.contentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.top, 16)
                }
                .scrollContentBackground(.hidden)
                .overlay(alignment: .bottomTrailing) {
                    if historyWindow.hasLater
                        || scrollCoordinator.followState == .detachedByUser {
                        MopeliumJumpToLatestButton(
                            accessibilityIdentifier: "code.jump-to-latest"
                        ) {
                            if historyWindow.hasLater {
                                selectHistoryWindow(nil)
                            } else {
                                scrollCoordinator.jumpToLatest(
                                    scope: pageScope,
                                    perform: scrollPerformer(proxy))
                            }
                        }
                    }
                }
                .onAppear {
                    scrollCoordinator.activate(
                        scope: pageScope,
                        defersRichUntilInitialRestore:
                            defersRichUntilInitialRestore)
                    requestScroll(
                        proxy,
                        reason: .initialRestore,
                        scope: pageScope)
                }
                .onChange(of: itemScrollSignature) { _, _ in
                    guard historyWindow.isLatest else { return }
                    requestScroll(
                        proxy,
                        reason: scrollReason,
                        scope: pageScope)
                }
                .onChange(of: layout.contentWidth) { _, _ in
                    scrollCoordinator.openWidthSettleEpoch(
                        scope: pageScope,
                        width: layout.contentWidth,
                        perform: scrollPerformer(proxy))
                }
                .onScrollGeometryChange(
                    for: MopeliumThreadScrollGeometry.self
                ) { geometry in
                    MopeliumThreadScrollGeometry.measure(
                        contentOffsetY: geometry.contentOffset.y,
                        containerHeight: geometry.containerSize.height,
                        bottomInset: geometry.contentInsets.bottom,
                        contentHeight: geometry.contentSize.height)
                } action: { _, current in
                    scrollCoordinator.enqueueGeometryObservation(
                        current.isAtBottom,
                        contentHeight: current.contentHeight,
                        scope: pageScope)
                }
                .onScrollPhaseChange { _, newPhase in
                    switch newPhase {
                    case .tracking, .interacting, .decelerating:
                        scrollCoordinator.userInteractionDidBegin(
                            scope: pageScope)
                    case .idle:
                        scrollCoordinator.userInteractionDidEnd(
                            scope: pageScope)
                    case .animating:
                        break
                    }
                }
                .onDisappear {
                    scrollCoordinator.deactivate(scope: pageScope)
                }
            }
            .id(pageScope)
        }
    }

    private var showsThinkingIndicator: Bool {
        MopeliumThreadActivity.isAwaitingModelOutput(
            items: displayedItems,
            isWorking: isWorking,
            permissionBlocksResponse: permissionBlocksComposer)
    }

    private var defersRichUntilInitialRestore: Bool {
        MopeliumThreadRichEntryPolicy.defersUntilInitialRestore(
            richRowCount: threadHistoryWindow.items.count)
    }

    private var threadHistoryWindow: MopeliumThreadHistoryWindow<CodeItem> {
        .resolve(
            allItems: displayedItems,
            requestedUpperBound: requestedHistoryWindowUpperBound)
    }

    private var requestedHistoryWindowUpperBound: Int? {
        historySelection?.upperBound(for: presentationScope)
    }

    private var threadPresentationScope: MopeliumThreadPresentationScope {
        presentationScope.historyWindowScope(
            requestedUpperBound: requestedHistoryWindowUpperBound)
    }

    private func selectHistoryWindow(_ requestedUpperBound: Int?) {
        historySelection = MopeliumThreadHistorySelection(
            scope: presentationScope,
            requestedUpperBound: requestedUpperBound)
    }

    private var showsVisibleThinkingIndicator: Bool {
        threadHistoryWindow.isLatest && showsThinkingIndicator
    }

    private var itemScrollSignature: MopeliumThreadScrollSignature {
        let historyWindow = threadHistoryWindow
        let last = historyWindow.items.last
        return MopeliumThreadScrollSignature(
            visibleItemCount: historyWindow.items.count,
            lastItemID: last?.id,
            lastBodyUTF8Count: last?.body.utf8.count ?? 0,
            lastItemComplete: last?.complete ?? false,
            isWorking: historyWindow.isLatest && isWorking,
            showsThinkingIndicator: showsVisibleThinkingIndicator)
    }

    private var scrollReason: MopeliumThreadScrollReason {
        let historyWindow = threadHistoryWindow
        guard let last = historyWindow.items.last else {
            return .liveUpdate
        }
        let visibleIsWorking = historyWindow.isLatest && isWorking
        return last.complete && !visibleIsWorking
            ? .completion
            : .liveUpdate
    }

    private func requestScroll(
        _ proxy: ScrollViewProxy,
        reason: MopeliumThreadScrollReason,
        scope: MopeliumThreadPresentationScope
    ) {
        scrollCoordinator.request(
            scope: scope,
            reason: reason,
            perform: scrollPerformer(proxy))
    }

    private func scrollPerformer(
        _ proxy: ScrollViewProxy
    ) -> @MainActor (MopeliumThreadScrollRequest) -> Void {
        { request in
            let anchorID = MopeliumThreadBottomAnchorID(scope: request.scope)
            proxy.scrollTo(anchorID, anchor: .bottom)
        }
    }

    @ViewBuilder private func permissionArea(layout: MopeliumThreadContentLayout) -> some View {
        if let pending {
            PermissionCard(permission: pending, onResolve: onResolve)
                .frame(maxWidth: layout.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, layout.horizontalPadding)
        } else if let permissionNotice {
            PermissionResolutionNoticeView(notice: permissionNotice)
                .frame(maxWidth: layout.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, layout.horizontalPadding)
        }
    }

    private func composerArea(layout: MopeliumThreadContentLayout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MopeliumThreadComposer(
                placeholder: MopeliumLocalization.string("Message Coder..."),
                input: $input,
                canSend: !isWorking
                    && !permissionBlocksComposer
                    && composerTrailingAction?.blocksSubmission != true
                    && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                isInputDisabled: isWorking || permissionBlocksComposer,
                style: threadStyle,
                leadingAccessory: composerAccessory,
                trailingAction: composerTrailingAction,
                stopAction: isWorking
                    ? onCancelCurrent.map { onCancelCurrent in
                        MopeliumThreadComposerSecondaryAction(
                            systemImage: "stop.fill",
                            help: MopeliumLocalization.string("Stop"),
                            action: onCancelCurrent)
                    }
                    : nil,
                accessory: {
                    MopeliumComposerUsageStrip(
                        stats: latestTurnStats,
                        style: threadStyle)
                },
                onSend: {
                    selectHistoryWindow(nil)
                    onSend()
                })
        }
        .frame(maxWidth: layout.contentMaxWidth)
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 22)
    }
}

struct CodeItemRow: View {
    let item: CodeItem
    let style: MopeliumThreadStyle
    let layout: MopeliumThreadContentLayout
    let onRetrySubmission: ((SubmissionID) -> Void)?

    init(item: CodeItem,
         style: MopeliumThreadStyle = .standard(.light),
         layout: MopeliumThreadContentLayout = MopeliumThreadContentLayout(rawWidth: 900),
         onRetrySubmission: ((SubmissionID) -> Void)? = nil) {
        self.item = item
        self.style = style
        self.layout = layout
        self.onRetrySubmission = onRetrySubmission
    }

    var body: some View {
        switch item.kind {
        case .user:
            bubble(
                title: nil,
                body: item.body,
                isUser: true,
                tags: item.tags)
        case .agent:
            bubble(title: item.title, body: item.body.isEmpty && !item.complete ? "…" : item.body,
                   isUser: false)
        case .toolCall:
            if item.isFailure || item.recoveryAdvice != nil {
                EmptyView()
            } else {
                card(
                    icon: "wrench.and.screwdriver",
                    title: MopeliumLocalization.format("tool · %@", item.title),
                    body: item.body,
                    tint: .blue)
            }
        case .toolResult:
            if item.isFailure || item.recoveryAdvice != nil {
                EmptyView()
            } else {
                card(
                    icon: "arrow.turn.down.right",
                    title: item.title,
                    body: item.body,
                    tint: .gray)
            }
        case .patch:
            if item.isFailure || item.recoveryAdvice != nil {
                EmptyView()
            } else {
                card(
                    icon: "doc.badge.gearshape",
                    title: MopeliumLocalization.format(
                        "patch · %@",
                        item.files.joined(separator: ", ")),
                    body: item.body,
                    tint: .purple)
            }
        case .note:
            if item.isFailure || item.recoveryAdvice != nil {
                EmptyView()
            } else {
                Text(item.body).font(.caption).foregroundStyle(.secondary)
            }
        case .error:
            EmptyView()
        case .agentToAgent:
            bubble(
                title: item.title,
                body: item.body.isEmpty && !item.complete ? "…" : item.body,
                isUser: false)
        }
    }

    private func bubble(title: String?, body: String, isUser: Bool, tags: [String] = []) -> some View {
        MopeliumThreadBubbleRow(
            isTrailing: isUser,
            fillsAvailableWidth: !isUser,
            rowWidth: layout.contentWidth,
            maxWidth: layout.messageMaxWidth,
            gutter: layout.messageGutter) {
                bubbleContent(title: title, body: body, isUser: isUser, tags: tags)
            }
    }

    @ViewBuilder private func bubbleContent(title: String?,
                                            body: String,
                                            isUser: Bool,
                                            tags: [String]) -> some View {
        if isUser {
            bubbleBody(title: title, body: body, isUser: isUser, tags: tags)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .mopeliumLiquidGlass(cornerRadius: 16)
        } else {
            bubbleBody(title: title, body: body, isUser: false, tags: tags)
                .padding(.vertical, 8)
        }
    }

    private func bubbleBody(title: String?,
                            body: String,
                            isUser: Bool,
                            tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if title != nil || !tags.isEmpty {
                HStack(spacing: 6) {
                    if let title {
                        Text(displayTitle(title))
                            .font(.caption2.bold())
                            .foregroundStyle(
                                isUser ? style.accent : style.tertiaryText)
                    }
                    if !isUser, let timestamp = item.timestamp {
                        Text(MopeliumMessageTimestampPresentation.string(for: timestamp))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(style.tertiaryText)
                    }
                    ForEach(tags, id: \.self) { tag in
                        tagBadge(tag)
                    }
                }
            }
            if isUser {
                if !body.isEmpty {
                    Text(body)
                        .font(.system(size: 15))
                        .foregroundStyle(style.primaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.attachments.isEmpty {
                    Label(
                        item.attachments.count == 1
                            ? MopeliumLocalization.format(
                                "%lld attachment",
                                Int64(item.attachments.count))
                            : MopeliumLocalization.format(
                                "%lld attachments",
                                Int64(item.attachments.count)),
                        systemImage: "paperclip")
                        .font(.caption)
                        .foregroundStyle(style.secondaryText)
                }
            } else {
                MopeliumMessageContentView(
                    messageID: item.id,
                    rawText: item.body,
                    isComplete: item.complete,
                    policy: .richText,
                    style: style)
            }
            if isUser,
               let submissionID = item.submissionID,
               let submissionStatus = item.submissionStatus,
               submissionStatus != .failed,
               item.submissionFailure == nil {
                submissionStatusView(
                    id: submissionID,
                    status: submissionStatus,
                    failure: item.submissionFailure)
            }
        }
    }

    private func displayTitle(_ title: String) -> String {
        title == "Agent" ? "Mopelium" : title
    }

    private func submissionStatusView(
        id: SubmissionID,
        status: SubmissionStatus,
        failure: SubmissionFailure?
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: submissionStatusIcon(status))
                .foregroundStyle(status == .failed || status == .cancelled
                    ? style.error
                    : style.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(submissionStatusLabel(status))
                    .font(.caption2.bold())
                    .foregroundStyle(status == .failed || status == .cancelled
                        ? style.error
                        : style.secondaryText)
                if let failure {
                    Text(failure.message)
                        .font(.caption2)
                        .foregroundStyle(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if failure?.retryable == true, let onRetrySubmission {
                Button("Retry") { onRetrySubmission(id) }
                    .buttonStyle(.borderless)
                    .font(.caption.bold())
                    .accessibilityIdentifier("submission.\(id.rawValue).retry")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("submission.\(id.rawValue).status")
    }

    private func submissionStatusLabel(_ status: SubmissionStatus) -> String {
        switch status {
        case .queued: return MopeliumLocalization.string("Queued locally")
        case .running: return MopeliumLocalization.string("Running")
        case .completed: return MopeliumLocalization.string("Completed")
        case .failed: return MopeliumLocalization.string("Needs attention")
        case .cancelled: return MopeliumLocalization.string("Cancelled")
        }
    }

    private func submissionStatusIcon(_ status: SubmissionStatus) -> String {
        switch status {
        case .queued: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    private func card(icon: String, title: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(tint)
            Text(body).font(.system(.caption, design: .monospaced))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .mopeliumContentSurface(cornerRadius: 8)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(tint.opacity(0.25)))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: min(layout.contentMaxWidth, 740), alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagBadge(_ tag: String) -> some View {
        Text(tag.uppercased())
            .font(.caption2.bold())
            .foregroundStyle(style.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay { Capsule().stroke(style.stroke, lineWidth: 1) }
    }
}

private struct CodeEmptyThreadView: View {
    let style: MopeliumThreadStyle

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(style.accent)
                .frame(width: 76, height: 76)
            Spacer()
        }
        .multilineTextAlignment(.center)
    }
}

private struct PermissionReviewSurfaceModifier: ViewModifier {
    let isEnabled: Bool
    let cornerRadius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        if isEnabled {
            content.mopeliumSubtleContentSurface(cornerRadius: cornerRadius)
        } else {
            content
        }
    }
}

public enum PermissionReviewCardStyle: Equatable, Sendable {
    case standard
    case compactRail
}

public struct PermissionResolutionNoticeView: View {
    let notice: PermissionResolutionNotice
    private let embedsSurface: Bool
    private let presentationStyle: PermissionReviewCardStyle

    public init(notice: PermissionResolutionNotice,
                embedsSurface: Bool = true,
                presentationStyle: PermissionReviewCardStyle = .standard) {
        self.notice = notice
        self.embedsSurface = embedsSurface
        self.presentationStyle = presentationStyle
    }

    @ViewBuilder public var body: some View {
        Group {
            switch presentationStyle {
            case .standard:
                standardContent
            case .compactRail:
                compactRailContent
            }
        }
        .modifier(PermissionReviewSurfaceModifier(
            isEnabled: embedsSurface,
            cornerRadius: presentationStyle == .compactRail ? 14 : 10))
        .accessibilityIdentifier("permission.resolution")
    }

    private var standardContent: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: statusIcon)
                .font(.caption)
                .foregroundStyle(statusColor)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(notice.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var compactRailContent: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: statusIcon)
                .font(.body.weight(.semibold))
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(notice.reason)
        .accessibilityHint(notice.reason)
    }

    private var statusIcon: String {
        notice.decision == .allow
            ? "checkmark.circle.fill"
            : "xmark.circle.fill"
    }

    private var statusColor: Color {
        notice.decision == .allow ? .green : .orange
    }

    private var title: String {
        if notice.decision == .allow {
            return MopeliumLocalization.format("%@ approved", notice.tool)
        }
        if notice.action == .cancelTurn {
            return MopeliumLocalization.string("Turn cancelled")
        }
        switch notice.failureSource {
        case .userDenied:
            return MopeliumLocalization.format("%@ call declined", notice.tool)
        case .userCancelled, .turnCancelled:
            return MopeliumLocalization.string("Turn cancelled")
        case .policyDenied:
            return MopeliumLocalization.format("%@ call denied by policy", notice.tool)
        case .reviewerTimedOut:
            return MopeliumLocalization.string("Automatic review timed out")
        case .reviewerFailed:
            return MopeliumLocalization.string("Automatic review failed")
        case .sandboxDenied:
            return MopeliumLocalization.format("Sandbox denied %@", notice.tool)
        case .runtimeFailed:
            return MopeliumLocalization.format("%@ runtime failed", notice.tool)
        case nil:
            return MopeliumLocalization.format("%@ denied", notice.tool)
        }
    }
}

struct PermissionReviewDetail: Equatable, Identifiable {
    let id: String
    let systemImage: String
    let text: String
}

enum PermissionReviewPresentation {
    /// Builds a small, secret-safe review summary from the structured
    /// authorization snapshot. Raw JSON arguments are deliberately excluded.
    static func details(
        for request: PermissionRequestPayload
    ) -> [PermissionReviewDetail] {
        if let preview = request.context?.authorization?.actionPreview {
            let previewDetails: [PermissionReviewDetail] = preview.fields.keys
                .sorted()
                .compactMap { key -> PermissionReviewDetail? in
                guard let value = preview.fields[key], !value.isEmpty else {
                    return nil
                }
                return PermissionReviewDetail(
                    id: "preview.\(key)",
                    systemImage: "info.circle",
                    text: "\(humanized(key)): \(value)")
            }
            if !previewDetails.isEmpty {
                return previewDetails
            }
        }

        let intent = request.context?.intent
            ?? request.context?.authorization?.intent
        var details: [PermissionReviewDetail] = []
        if let action = intent?.action, !action.isEmpty {
            details.append(PermissionReviewDetail(
                id: "action",
                systemImage: "bolt",
                text: action))
        }

        let resources = intent?.resources.map(\.value).filter { !$0.isEmpty }
            ?? []
        if !resources.isEmpty {
            details.append(PermissionReviewDetail(
                id: "resources",
                systemImage: "scope",
                text: resources.joined(separator: ", ")))
        } else if let paths = request.context?.touchedPaths,
                  !paths.isEmpty {
            details.append(PermissionReviewDetail(
                id: "paths",
                systemImage: "folder",
                text: paths.joined(separator: ", ")))
        }
        return details
    }

    static func compactSummary(
        for request: PermissionRequestPayload
    ) -> String {
        let reason = request.reason.trimmingCharacters(
            in: .whitespacesAndNewlines)
        if !reason.isEmpty {
            return reason
        }
        return details(for: request).first?.text ?? request.tool
    }

    private static func humanized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

public struct PermissionCard: View {
    let permission: PendingPermission
    let onResolve: (PermissionResponseAction) -> Void
    private let embedsSurface: Bool
    private let presentationStyle: PermissionReviewCardStyle
    @State private var showsDetails = false

    public init(permission: PendingPermission,
                embedsSurface: Bool = true,
                presentationStyle: PermissionReviewCardStyle = .standard,
                onResolve: @escaping (PermissionResponseAction) -> Void) {
        self.permission = permission
        self.embedsSurface = embedsSurface
        self.presentationStyle = presentationStyle
        self.onResolve = onResolve
    }

    private var request: PermissionRequestPayload { permission.request }
    private var reviewDetails: [PermissionReviewDetail] {
        PermissionReviewPresentation.details(for: request)
    }
    private var proposedDiff: String? { Self.diff(from: request.args) }
    private var hasDetails: Bool {
        !reviewDetails.isEmpty || proposedDiff != nil
    }

    @ViewBuilder public var body: some View {
        Group {
            switch presentationStyle {
            case .standard:
                standardContent
            case .compactRail:
                compactRailContent
            }
        }
        .modifier(PermissionReviewSurfaceModifier(
            isEnabled: embedsSurface,
            cornerRadius: presentationStyle == .compactRail ? 18 : 14))
        .onChange(of: request.requestId) { _, _ in
            showsDetails = false
        }
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(riskColor)
                    .frame(width: 18)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(MopeliumLocalization.string("Permission needed"))
                            .font(.callout.weight(.semibold))
                        Text(riskLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(riskColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(riskColor.opacity(0.10), in: Capsule())
                    }
                    Text(request.tool)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(request.reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if hasDetails {
                DisclosureGroup(
                    isExpanded: $showsDetails,
                    content: {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(reviewDetails) { detail in
                                Label {
                                    Text(detail.text)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                } icon: {
                                    Image(systemName: detail.systemImage)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            if let proposedDiff {
                                ScrollView {
                                    Text(proposedDiff)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(
                                            maxWidth: .infinity,
                                            alignment: .leading)
                                }
                                .frame(maxHeight: 150)
                                .padding(8)
                                .mopeliumSubtleContentSurface(cornerRadius: 7)
                            }
                        }
                        .padding(.top, 6)
                        .padding(.leading, 4)
                    },
                    label: {
                        Text(MopeliumLocalization.string("Details"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                )
                .tint(.secondary)
                .accessibilityIdentifier("permission.details")
            }

            permissionFooter
        }
        .padding(13)
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var compactRailContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(riskColor)
                    .frame(width: 20)
                    .padding(.top, 1)
                    .accessibilityLabel(
                        MopeliumLocalization.format("%@ risk", riskLabel))
                VStack(alignment: .leading, spacing: 3) {
                    Text(MopeliumLocalization.string("Permission Review"))
                        .font(.body.weight(.semibold))
                    Text(request.tool)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(PermissionReviewPresentation.compactSummary(
                        for: request))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            compactRailFooter
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var compactRailFooter: some View {
        if permission.state.isActionable {
            ViewThatFits(in: .horizontal) {
                horizontalPermissionActions
                compactPermissionActions
            }
            .controlSize(.small)
        } else {
            permissionStatus
        }
    }

    private var permissionFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                permissionStatus
                Spacer(minLength: 8)
                if permission.state.isActionable {
                    horizontalPermissionActions
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                permissionStatus
                if permission.state.isActionable {
                    compactPermissionActions
                }
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder private var permissionStatus: some View {
        if permission.state == .resolving {
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text(request.effectiveApprovalMode == .automaticReviewer
                     ? MopeliumLocalization.string("Automatic review in progress…")
                     : MopeliumLocalization.string("Resolving…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var horizontalPermissionActions: some View {
        HStack(spacing: 8) {
            cancelTurnButton
            declineCallButton
            approveCallButton
            if permitsRememberedApproval {
                rememberApprovalButton
            }
        }
    }

    private var compactPermissionActions: some View {
        VStack(alignment: .trailing, spacing: 7) {
            approveCallButton
                .frame(maxWidth: .infinity, alignment: .trailing)
            if permitsRememberedApproval {
                rememberApprovalButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(spacing: 8) {
                cancelTurnButton
                Spacer(minLength: 8)
                declineCallButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var cancelTurnButton: some View {
        Button("Cancel Turn") { onResolve(.cancelTurn) }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("permission.cancel-turn")
    }

    private var declineCallButton: some View {
        Button("Decline Call") { onResolve(.decline) }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("permission.decline-call")
    }

    private var approveCallButton: some View {
        Button(
            request.context?.authorization?.mcp == nil
                ? "Approve Call"
                : "Allow Call Once"
        ) {
            onResolve(.approve)
        }
        .mopeliumGlassButton(prominent: true)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("permission.approve-call")
    }

    private var rememberApprovalButton: some View {
        Button("Remember Exact Tool Approval") {
            onResolve(.approveAndRemember)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("permission.approve-and-remember")
    }

    private var permitsRememberedApproval: Bool {
        request.context?.authorization?.permitsMCPRememberedApproval == true
    }

    private var riskColor: Color {
        switch request.risk {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    private var riskLabel: String {
        switch request.risk {
        case .low: return MopeliumLocalization.string("LOW")
        case .medium: return MopeliumLocalization.string("MEDIUM")
        case .high: return MopeliumLocalization.string("HIGH")
        }
    }

    private var statusText: String {
        switch permission.state {
        case .livePending:
            return MopeliumLocalization.string("Waiting for your decision.")
        case .resolving:
            return request.effectiveApprovalMode == .automaticReviewer
                ? MopeliumLocalization.string(
                    "The reserved permission reviewer is evaluating this call.")
                : MopeliumLocalization.string("Applying your decision.")
        case .approved:
            return MopeliumLocalization.string("Approved.")
        case .rejected:
            return MopeliumLocalization.string("Rejected.")
        case .expired:
            return MopeliumLocalization.string(
                "This approval channel expired. Rerun the task to continue.")
        case .needsRerun:
            return MopeliumLocalization.string(
                "This request was restored from history. Rerun the task to continue.")
        }
    }

    public static func diff(from args: String) -> String? {
        struct A: Decodable { let diff: String? }
        return (try? JSONDecoder().decode(A.self, from: Data(args.utf8)))?.diff
    }
}

private struct CodeInspectorView: View {
    let workspaceName: String
    let agentState: String
    let itemCount: Int
    let pending: PendingPermission?
    let errors: [MopeliumThreadErrorEntry]
    let style: MopeliumThreadStyle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                inspectorHeader
                inspectorSection(MopeliumLocalization.string("Plan")) {
                    inspectorRow(
                        MopeliumLocalization.string("Current task"),
                        value: mopeliumLocalizedAgentState(agentState))
                    inspectorRow(MopeliumLocalization.string("Thread events"), value: "\(itemCount)")
                    if let pending {
                        inspectorRow(
                            MopeliumLocalization.string("Permission"),
                            value: pending.request.tool)
                    } else {
                        inspectorRow(
                            MopeliumLocalization.string("Permission"),
                            value: MopeliumLocalization.string("none pending"))
                    }
                }
                inspectorSection(MopeliumLocalization.string("Workspace")) {
                    inspectorRow(MopeliumLocalization.string("Root"), value: workspaceName)
                    inspectorRow(
                        MopeliumLocalization.string("Git"),
                        value: MopeliumLocalization.string("status only"))
                    Text("Commit, branch, PR, CI, and review workflows are deferred.")
                        .font(.caption2)
                        .foregroundStyle(style.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !errors.isEmpty {
                    inspectorSection(MopeliumLocalization.string("Error Information")) {
                        MopeliumThreadErrorList(
                            errors: errors,
                            style: style,
                            onRetrySubmission: nil)
                    }
                    .accessibilityIdentifier("code.error.card")
                }
            }
            .padding(16)
        }
    }

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Inspector")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(style.primaryText)
            Text("Task and workspace status")
                .font(.caption)
                .foregroundStyle(style.secondaryText)
        }
    }

    private func inspectorSection<Content: View>(_ title: String,
                                                 @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(style.tertiaryText)
            content()
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mopeliumContentSurface(cornerRadius: 8)
    }

    private func inspectorRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(style.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
#endif
