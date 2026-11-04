import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import QuickLook

@MainActor final class TimelineEntryFrameStore {
    var frames: [String: CGRect] = [:]
}

/// Native session content; the owning pane supplies its composition dock.
struct AgentTimelineView: View {
    let paneId: String
    var agent: String? = nil
    let connection: HerdrConnection
    let timeline: AgentTimelineState
    var bridgeUpgrade: TimelineBridgeUpgrade = TimelineBridgeUpgrade()
    let topOverlayInset: CGFloat
    let bottomOverlayInset: CGFloat
    let onOutputInteraction: () -> Void
    let setupTarget: ConnectionIdentity
    let onUseTerminal: () -> Void
    let onSetupComplete: () -> Void
    var onFocusComposer: () -> Void = {}
    @Environment(AppModel.self) var appModel
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var waitingKey: WaitingTaskKey?
    @State var phoneAnswersSelection: PhoneAnswersSelection?
    @State var approvalResponse = ApprovalResponseState()
    @State var questionResponse = QuestionAnswerState()
    @State var waitingRowHeight: CGFloat = 0
    @State var sheetState = TimelineSheetState()
    @State var approvalViewVisible = false
    @State var activeClient: AgentBridgeClient?
    @State var activeOwner: UUID?
    @State var showsSetup = false
    @State var setupReason: HostHelperSetupReason = .missing
    @State var setupShouldUseTerminal = true
    @State var isCheckingSetup = false
    @State var setupFeedback: String?
    @State var helperStage: HostHelperSetupStage = .idle
    @State var helperInstallTask: Task<Void, Never>?
    @State var helperInstallToken: UUID?
    @State var fixtureHelperInstalled = false
    @State var helperMayHaveInstalled = false
    @State var retry = 0
    @State private var contentFiles = TimelineContentFiles()
    @State private var blockCache = TimelineBlockCache()
    @State var historyLoader = TimelineHistoryLoader()
    @State var isPaging = false
    @State var pageError: String?
    @State var following = true
    @State var atBottom = true
    @State var entryFrames = TimelineEntryFrameStore()
    @State var viewportHeight: CGFloat = 0
    @State private var focusedQuestionField: QuestionFieldTarget?
    @State private var questionFieldFrames: [QuestionFieldTarget: CGRect] = [:]
    @State private var questionKeyboardFrame: CGRect = .null
    @State var historyScrollAnchor: TimelineHistoryScrollAnchor?
    /// Messages that arrived while you were scrolled up.
    @State private var unseen = TimelineUnseenCounter()
    @Environment(\.paneIsFocused) private var paneIsFocused
    @State var bridgeCapabilities: AgentBridgeCapabilities?
    @State var bridgeVersion: String?
    @State var showsCodexDaemonConfirm = false
    @State var isDisablingCodexDaemon = false
    @State var codexDaemonStopOutcome: CodexDaemonStopOutcome?
    /// Episode token for the recorded outcome: bumped on every clear, so a
    /// stop command still in flight can detect that its episode ended.
    @State var codexDaemonEpisode = 0
    /// Sequence of `codex_daemon` report changes; lets a completing stop tell
    /// an unchanged pre-stop report from one that changed while it ran.
    @State var codexDaemonReportSeq = 0
    @State var copiedCodexConfig = false
    @State var copiedCodexStop = false
    @State var copiedCodexUpdaterStop = false

    var approvalInset: CGFloat { showsWaitingRow ? waitingRowHeight + 8 : 0 }
    private var hooksKey: PhoneAnswersStore.Key? {
        guard let generation = connectionState.generation,
            let agent = timeline.identity?.agent, ApprovalAgent(rawValue: agent) != nil else { return nil }
        return .init(target: setupTarget, generation: generation, agent: agent)
    }
    struct WaitingTaskKey: Equatable {
        let hooks: PhoneAnswersStore.Key?
        let owner: UUID?
        let identity: AgentTimelineIdentity?
        let generation: UInt64?
        let eligible: Bool
    }
    var waitingTaskKey: WaitingTaskKey {
        WaitingTaskKey(hooks: hooksKey, owner: activeOwner, identity: timeline.identity, generation: timeline.generation,
            eligible: PhoneAnswersPresentation.eligible(approvals: bridgeCapabilities?.approvals,
                ready: matchesLiveTimeline && timeline.phase == .ready && connectionState.isReady,
                blocked: timeline.agentStatus == "blocked", pending: timeline.pendingApproval != nil || showsQuestion,
                active: scenePhase == .active && appModel.isSceneActive))
    }
    private var showsWaitingRow: Bool { waitingTaskKey.eligible && waitingKey == waitingTaskKey }
    func hooksContextIsCurrent(_ key: PhoneAnswersStore.Key) -> Bool {
        matchesLiveTimeline && scenePhase == .active && appModel.isSceneActive && connectionState.isReady
            && setupTarget == key.target && connectionState.generation == key.generation
            && bridgeCapabilities?.approvals == true
    }
    var matchesLiveTimeline: Bool { timeline.matchesLivePane(paneId: paneId, agent: agent, connection: connectionState) }

    var showsApproval: Bool {
        matchesLiveTimeline && scenePhase == .active && connectionState.isReady && timeline.phase == .ready
            && ApprovalResponseState.isVisible(pending: timeline.pendingApproval, approvals: bridgeCapabilities?.approvals)
    }

    var showsQuestion: Bool {
        matchesLiveTimeline && scenePhase == .active && connectionState.isReady && timeline.phase == .ready
            && QuestionAnswerState.isVisible(pending: timeline.pendingQuestion, questions: bridgeCapabilities?.questions)
    }

    var conversationItems: [TimelineConversationItem] {
        TimelineConversationItem.group(timeline.entries, showsRecords: agent == "codex" || agent == "pi")
    }

    /// The widest the conversation column gets.
    static let readingWidth: CGFloat = 720
    /// Space between the conversation and the views before and after it.
    static let sectionGap: CGFloat = 16

    /// The pane's agent names each turn. Agy's pane says "agy" while its
    /// timeline identity says "antigravity_cli"; both name and icon handle either.
    private var speakerAgent: String { agent ?? timeline.identity?.agent ?? "" }

    /// The row that carries an item's scroll id and reports its frame for
    /// keeping the reading position when older messages load.
    private func itemRow(_ item: TimelineConversationItem) -> some View {
        let scope = contentScope
        return Group {
            if item.isActivity {
                TimelineActivityView(entries: item.entries,
                    loadContent: { reference in try await loadContent(reference, scope: scope) })
            } else if let entry = item.entries.first {
                AgentTimelineEntryView(entry: entry, files: contentFiles, scope: scope, blockCache: blockCache,
                    loadContent: { reference in try await loadContent(reference, scope: scope) })
            }
        }
        .id("\(scope):\(item.id)")
        .background {
            GeometryReader { row in
                Color.clear.preference(
                    key: TimelineEntryFramesPreferenceKey.self,
                    value: [item.id: row.frame(in: .named("timeline-viewport"))])
            }
        }
    }

    var connectionState: AgentTimelineConnectionState {
        AgentTimelineConnectionState(
            phase: appModel.phase, generation: appModel.ownership.transportGeneration)
    }
    struct TaskKey: Equatable {
        let paneId: String
        let agent: String?
        let connection: AgentTimelineConnectionState
        let isActive: Bool
        let retry: Int
    }
    var taskKey: TaskKey {
        TaskKey(paneId: paneId, agent: agent, connection: connectionState, isActive: scenePhase == .active, retry: retry)
    }
    var canPinnedInstallerSupportAgent: Bool {
        Self.canPinnedInstallerSupport(agent: agent)
    }
    static func canPinnedInstallerSupport(agent: String?, supportedAgents: Set<String> = Set(HostHelperSetupPlan.agents)) -> Bool {
        agent.map { supportedAgents.contains(TimelineAgentAvailability.canonical($0) ?? $0) } ?? true
    }
    static func installLabel(
        stage: HostHelperSetupStage,
        reason: HostHelperSetupReason = .missing,
        pinnedVersion: String = HostHelperSetupPlan.version
    ) -> String {
        HostHelperSetupPlan.installLabel(stage: stage, reason: reason, pinnedVersion: pinnedVersion)
    }
    static func replacementFeedback(probe: HostHelperProbe) -> String? {
        HostHelperSetupPlan.replacementFeedback(probe: probe)
    }
    private func revealQuestionField(using proxy: ScrollViewProxy, viewport: GeometryProxy) {
        guard let target = focusedQuestionField, showsQuestion,
              target.scope == contentScope,
              target.requestId == timeline.pendingQuestion?.requestId else { return }
        let height = viewport.size.height
        let viewportFrame = viewport.frame(in: .global)
        var visibleBottom = height - viewport.safeAreaInsets.bottom
        if questionKeyboardFrame.intersects(viewportFrame) {
            visibleBottom = min(visibleBottom, questionKeyboardFrame.minY - viewportFrame.minY)
        }
        let top = topOverlayInset + 8
        let bottom = visibleBottom - bottomOverlayInset - approvalInset - 8
        if let frame = questionFieldFrames[target], frame.minY >= top, frame.maxY <= bottom { return }
        // Center the selected field in the usable area, not the card's bottom:
        // a later question can be much taller than the keyboard viewport.
        let anchorY = height > 0 ? max(0, min(1, (top + max(top, bottom)) / (2 * height))) : 0.5
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
            proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: anchorY))
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    // Spacing is 0: the conversation's own gap rows space it,
                    // and the views around it pad themselves by `sectionGap`.
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if timeline.hasSnapshot(for: connectionState, paneId: paneId, agent: agent) {
                            let items = conversationItems
                            let rows = TimelineRows.build(items: items, agent: speakerAgent)
                            if timeline.hasMore {
                                TimelineNotice(isPaging ? "Loading earlier messages…" : (pageError ?? "Pull down to load earlier messages"),
                                    systemImage: isPaging ? "hourglass" : (pageError == nil ? "arrow.down" : "exclamationmark.circle"),
                                    kind: pageError != nil && !isPaging ? .error : .info)
                                    .accessibilityIdentifier("timeline-history-hint")
                                    .accessibilityAction(named: "Load earlier messages") {
                                        Task { await refreshHistory() }
                                    }
                                    .padding(.bottom, Self.sectionGap)
                            }
                            if items.isEmpty {
                                ContentUnavailableView("No messages yet", systemImage: "bubble.left")
                            }
                            ForEach(rows) { row in
                                switch row {
                                case .gap(_, let height):
                                    TimelineGapRow(height: height)
                                case .speaker(let firstItemID, let agent):
                                    TimelineSpeakerRow(agent: agent, firstItemID: firstItemID)
                                case .item(let item):
                                    itemRow(item)
                                }
                            }
                            if timeline.delayed {
                                TimelineNotice("Source update delayed; showing verified history.",
                                    systemImage: "clock.badge.exclamationmark", kind: .warning)
                                    .padding(.top, Self.sectionGap)
                            }
                            if let dialog = timeline.pendingPiDialog {
                                PiDialogCard(dialog: dialog, isSending: timeline.isPiActionPending,
                                    onSubmit: { answer in Task { await timeline.respondPiDialog(dialog, value: answer) } },
                                    onUseTerminal: onUseTerminal)
                                    .id("\(contentScope):pi-dialog:\(dialog.requestId)")
                                    .padding(.top, Self.sectionGap)
                            }
                            if let message = timeline.piActionError {
                                TimelineNotice(message, systemImage: "exclamationmark.circle", kind: .error)
                                    .padding(.top, Self.sectionGap)
                            }
                            if showsApproval, let pending = timeline.pendingApproval {
                                ApprovalCard(pending: pending, response: approvalResponse) { option in
                                    respondToApproval(pending, option: option)
                                }
                                .id("\(contentScope):approval:\(pending.requestId)")
                                .disabled(approvalResponse.isDisabled)
                                .padding(.top, Self.sectionGap)
                            }
                            if showsQuestion, let pending = timeline.pendingQuestion {
                                let questionScope = contentScope
                                QuestionCard(pending: pending, response: questionResponse,
                                    onSubmit: { respondToQuestion(pending) },
                                    onSkip: { respondToQuestion(pending, skip: true) },
                                    scope: questionScope,
                                    onFieldFocus: { target in
                                        if let target {
                                            guard target.scope == contentScope,
                                                  target.requestId == timeline.pendingQuestion?.requestId else { return }
                                            focusedQuestionField = target
                                        } else if focusedQuestionField?.scope == questionScope,
                                                  focusedQuestionField?.requestId == pending.requestId {
                                            focusedQuestionField = nil
                                        }
                                    })
                                    .id("\(contentScope):question:\(pending.requestId)")
                                    .padding(.top, Self.sectionGap)
                            }
                            if TimelineLiveState.showsWorkingRow(
                                agentStatus: timeline.agentStatus, lastItem: items.last,
                                pendingApproval: timeline.pendingApproval != nil,
                                pendingQuestion: timeline.pendingQuestion != nil,
                                pendingPiDialog: timeline.pendingPiDialog != nil) {
                                TimelineWorkingRow(agent: speakerAgent)
                                    .padding(.top, Self.sectionGap)
                            }
                        } else {
                            availability
                        }
                        // Clear scroll space lets the final entry sit above the
                        // floating Compose bubble without an opaque dock panel.
                        Color.clear
                            .frame(height: bottomOverlayInset + approvalInset)
                            .padding(.top, Self.sectionGap)
                            .padding(.bottom, DesignSystem.Spacing.base)
                            .id("timeline-bottom")
                    }
                    .scrollTargetLayout()
                    // A readable line length on iPad and the Duo's inner screen.
                    .frame(maxWidth: Self.readingWidth)
                    .frame(maxWidth: .infinity)
                    .padding([.horizontal, .top], DesignSystem.Spacing.base)
                    .padding(.top, topOverlayInset)
                    .frame(minHeight: viewport.size.height + 1, alignment: .top)
                    .background {
                        GeometryReader { content in
                            Color.clear.preference(key: TimelineAtBottomPreferenceKey.self,
                                value: content.frame(in: .named("timeline-viewport")).maxY <= viewport.size.height + 8)
                        }
                    }
                }
                .coordinateSpace(name: "timeline-viewport")
                .onChange(of: viewport.size.height, initial: true) { _, height in
                    viewportHeight = height
                    if focusedQuestionField != nil {
                        revealQuestionField(using: proxy, viewport: viewport)
                    } else if following && showsApproval { proxy.scrollTo("timeline-bottom", anchor: .bottom) }
                }
                .onChange(of: viewport.safeAreaInsets.bottom) { _, _ in
                    revealQuestionField(using: proxy, viewport: viewport)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                    guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                    questionKeyboardFrame = frame
                    revealQuestionField(using: proxy, viewport: viewport)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    questionKeyboardFrame = .null
                }
                .onChange(of: timeline.pendingPiDialog?.requestId, initial: true) { _, requestId in
                    guard requestId != nil else { return }
                    following = true
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) {
                        proxy.scrollTo("timeline-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: timeline.pendingApproval?.requestId, initial: true) { _, requestId in
                    guard requestId != nil, showsApproval else { return }
                    following = true
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) {
                        proxy.scrollTo("timeline-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: showsQuestion ? timeline.pendingQuestion?.requestId : nil, initial: true) { _, requestId in
                    focusedQuestionField = nil
                    guard requestId != nil, showsQuestion else { return }
                    following = true
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) {
                        proxy.scrollTo("timeline-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: focusedQuestionField) { _, target in
                    guard target != nil else { return }
                    following = false
                    revealQuestionField(using: proxy, viewport: viewport)
                }
                .onChange(of: contentScope) { _, _ in
                    focusedQuestionField = nil
                    questionFieldFrames = [:]
                }
                .onPreferenceChange(QuestionFieldFramesPreferenceKey.self) { frames in
                    questionFieldFrames = frames
                    revealQuestionField(using: proxy, viewport: viewport)
                }
                .onPreferenceChange(TimelineEntryFramesPreferenceKey.self) { entryFrames.frames = $0 }
                .onChange(of: historyScrollAnchor) { _, anchor in
                    guard let anchor else { return }
                    following = false
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo("\(contentScope):\(anchor.id)", anchor: UnitPoint(x: 0, y: anchor.unitY))
                    }
                }
                .onPreferenceChange(TimelineAtBottomPreferenceKey.self) { bottom in
                    atBottom = bottom
                    if bottom { following = true }
                }
                .accessibilityIdentifier("agent-timeline-scroll")
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard abs(value.translation.height) > abs(value.translation.width) else { return }
                            following = false
                            onOutputInteraction()
                        }
                        .onEnded { value in
                            guard abs(value.translation.height) > abs(value.translation.width) else { return }
                            let firstFrame = conversationItems.first.flatMap { entryFrames.frames[$0.id] }
                            let atHistoryTop = conversationItems.isEmpty || (firstFrame.map { $0.minY >= topOverlayInset - 8 } ?? false)
                            let loadHistory = atHistoryTop && value.translation.height > 60
                            if loadHistory && timeline.hasMore {
                                Task { await refreshHistory() }
                            } else if atBottom { following = true }
                        }
                )
                .onChange(of: timeline.revision) { _, _ in
                    guard following, timeline.pendingQuestion == nil, timeline.pendingPiDialog == nil, (!conversationItems.isEmpty || showsApproval) else { return }
                    proxy.scrollTo("timeline-bottom", anchor: .bottom)
                }
                .onChange(of: timeline.identity) { _, _ in
                    following = true
                    #if DEBUG && targetEnvironment(simulator)
                        if ScreenshotFixtures.enabled && AgentTimelineScreenshotFixture.holdsHistoryPosition {
                            following = false
                        }
                    #endif
                }
                .onChange(of: bottomOverlayInset) { _, _ in
                    if focusedQuestionField != nil {
                        revealQuestionField(using: proxy, viewport: viewport)
                    } else if following && (!conversationItems.isEmpty || showsApproval) {
                        proxy.scrollTo("timeline-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: approvalInset) { _, _ in
                    if focusedQuestionField != nil {
                        revealQuestionField(using: proxy, viewport: viewport)
                    } else if following && (!conversationItems.isEmpty || showsApproval) {
                        proxy.scrollTo("timeline-bottom", anchor: .bottom)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Group {
                    if !atBottom && timeline.phase == .ready {
                        JumpToLatestButton(label: "Jump to latest messages", badge: .count(unseen.count)) {
                            following = true
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) {
                                proxy.scrollTo("timeline-bottom", anchor: .bottom)
                            }
                        }
                        .accessibilityIdentifier("timeline-latest")
                        .padding(.trailing, 16)
                        .padding(.bottom, bottomOverlayInset + approvalInset + 8)
                        .transition(.opacity)
                    }
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: !atBottom && timeline.phase == .ready)
                }
            }
        }
        // Let messages scroll behind the pane cards, but keep them below
        // the navigation bar and status area.
        .overlay(alignment: .bottom) {
            Group {
                if showsWaitingRow, let key = hooksKey, let agent = ApprovalAgent(rawValue: key.agent) {
                    PhoneAnswersWaitingRow(agent: agent, result: appModel.phoneAnswers.result(for: key)) { mode in
                        phoneAnswersSelection = PhoneAnswersSelection(key: key, mode: mode)
                    }
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.size.height, initial: true) { _, height in waitingRowHeight = height }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, bottomOverlayInset + 8)
        }
        .clipped()
        .background(Theme.background)
        .onChange(of: timeline.pendingApproval, initial: true) { _, pending in approvalResponse.sync(pending) }
        .onChange(of: timeline.pendingQuestion, initial: true) { _, pending in questionResponse.sync(pending) }
        .task(id: taskKey) { await run() }
        .task(id: "\(activeClient?.id.uuidString ?? "none"):\(contentScope)") {
            await timeline.modelControl.refresh()
        }
        .task(id: waitingTaskKey) { await prepareWaitingRow() }
        .onAppear { approvalViewVisible = true; updateTimelineSheet() }
        .onChange(of: bridgeCapabilities?.approvals) { _, _ in updateTimelineSheet() }
        .onChange(of: phoneAnswersSelection?.id) { _, _ in updateTimelineSheet() }
        .onChange(of: showsSetup) { _, _ in updateTimelineSheet() }
        .onChange(of: showsCodexDaemonConfirm) { _, _ in updateTimelineSheet() }
        .onChange(of: timeline.revision, initial: true) { _, _ in
            switch timeline.phase {
            case .ready:
                onSetupComplete()
                isCheckingSetup = false
                if showsSetup {
                    setupShouldUseTerminal = false
                    showsSetup = false
                }
            case .unavailable(let code):
                if isCheckingSetup {
                    isCheckingSetup = false
                    setupFeedback = code == "helper_missing"
                        ? "Herdcats Bridge was not found yet. Run the command on your SSH host, then check again."
                        : explanation(code)
                }
                let isNeedsUpgrade = Self.isNeedsUpgrade(code: code, agent: agent, bridgeVersion: bridgeVersion)
                let isMissing = code == "helper_missing"
                if (isMissing || isNeedsUpgrade) && !showsSetup && canPinnedInstallerSupportAgent {
                    #if DEBUG && targetEnvironment(simulator)
                    if ScreenshotFixtures.enabled && ProcessInfo.processInfo.arguments.contains("-hc.timeline-suppress-drawer") {
                        // Suppress drawer auto-presentation for pane screenshots
                    } else {
                        beginSetup(reason: isNeedsUpgrade ? .updateRequired : .missing)
                    }
                    #else
                    beginSetup(reason: isNeedsUpgrade ? .updateRequired : .missing)
                    #endif
                }
            case .disconnected:
                if isCheckingSetup {
                    isCheckingSetup = false
                    setupFeedback = "Reconnect to your SSH host, then check again."
                }
            case .loading, .suspended: break
            }
        }
        .onChange(of: connectionState) { _, _ in cancelHelperInstallation() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelHelperInstallation() } }
        .onChange(of: timeline.phase) { _, newPhase in
            // A stop result only describes the no-session episode it answered;
            // a later episode (after the pane was ready again) starts fresh.
            if !Self.codexDaemonResultIsCurrent(phase: newPhase) { clearCodexDaemonResult() }
            dismissStaleCodexDaemonConfirm()
        }
        .onChange(of: timeline.codexDaemon) { _, codexDaemon in
            codexDaemonReportSeq += 1
            // A fresh daemon report that contradicts the recorded result (the
            // server came back after "off", or was stopped despite "still
            // running") hands the pane back to the live state.
            if Self.codexDaemonResultIsStale(outcome: codexDaemonStopOutcome, codexDaemon: codexDaemon) {
                clearCodexDaemonResult()
            }
            dismissStaleCodexDaemonConfirm()
        }
        .onChange(of: bridgeUpgrade.requested) { _, requested in
            if requested {
                bridgeUpgrade.requested = false
                // The menu item is offered while Timeline is working; dismissing
                // the optional upgrade must not dump a working Timeline.
                beginSetup(reason: .updateRequired, shouldUseTerminalOnDismiss: timeline.phase != .ready)
            }
        }
        .onChange(of: timeline.revision) { _, _ in
            let items = conversationItems
            if atBottom || following { unseen.markSeen(items) } else { unseen.update(items) }
        }
        .onChange(of: timeline.identity) { _, _ in unseen.markSeen(conversationItems) }
        .onChange(of: atBottom) { _, bottom in if bottom { unseen.markSeen(conversationItems) } }
        .onChange(of: StatusKey(scope: contentScope, status: timeline.agentStatus)) { previous, current in
            // A new session or snapshot is not a status change of this one.
            guard previous.scope == current.scope else { return }
            announceStatusChange(from: previous.status, to: current.status)
        }
        .onChange(of: contentScope) { _, _ in
            unseen.markSeen(conversationItems)
            historyLoader.cancel()
            entryFrames.frames = [:]
            historyScrollAnchor = nil
            contentFiles.reset()
            blockCache.reset()
        }
        .onChange(of: taskKey) { _, _ in historyLoader.cancel(); updateTimelineSheet() }
        .onDisappear {
            approvalViewVisible = false
            approvalResponse.reset()
            questionResponse.reset()
            updateTimelineSheet()
            historyLoader.cancel(); cancelHelperInstallation(); contentFiles.reset(); blockCache.reset()
        }
        .sheet(item: timelineSheetBinding, onDismiss: timelineSheetDismissed) { sheet in timelineSheet(sheet) }
    }
    private var timelineSheetBinding: Binding<TimelineSheetState.Sheet?> {
        Binding(get: { sheetState.presented }, set: { value in
            guard value == nil else { return }
            switch sheetState.presented {
            case .phoneAnswers: phoneAnswersSelection = nil
            case .helper: showsSetup = false
            case .codexDaemon: showsCodexDaemonConfirm = false
            default: break
            }
            sheetState.close()
        })
    }
    @MainActor private func timelineSheetDismissed() {
        let dismissed = sheetState.dismissing
        sheetState.didDismiss()
        if dismissed == .helper {
            cancelHelperInstallation()
            if setupShouldUseTerminal { onUseTerminal() }
        }
        updateTimelineSheet()
    }
    @ViewBuilder private func timelineSheet(_ sheet: TimelineSheetState.Sheet) -> some View {
        switch sheet {
        case .phoneAnswers:
            if let selection = phoneAnswersSelection {
                PhoneAnswersSheet(selection: selection, connection: connection, store: appModel.phoneAnswers,
                    isCurrent: { hooksContextIsCurrent(selection.key) })
            }
        case .helper:
            AgentBridgeSetupView(
                reason: setupReason, agent: agent, installedVersion: bridgeVersion,
                isChecking: isCheckingSetup, feedback: setupFeedback,
                stage: helperStage, target: setupTarget,
                canInstall: connectionState.isReady && appModel.connectionIdentity == setupTarget && canPinnedInstallerSupportAgent,
                onInstall: startHelperInstallation,
                onCheckAgain: { setupFeedback = nil; isCheckingSetup = true; retry += 1 },
                onUseTerminal: { cancelHelperInstallation(); showsSetup = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        case .codexDaemon:
            CodexDaemonConfirmSheet(
                onConfirm: { showsCodexDaemonConfirm = false; disableCodexDaemon() },
                onCancel: { showsCodexDaemonConfirm = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
    }
    @MainActor func updateTimelineSheet() {
        sheetState.sync(visible: matchesLiveTimeline && approvalViewVisible && scenePhase == .active,
            phone: phoneAnswersSelection != nil, helper: showsSetup, codex: showsCodexDaemonConfirm)
    }
    private struct StatusKey: Equatable {
        let scope: String
        let status: String?
    }

    /// Tells VoiceOver users when the turn finishes or an answer is needed.
    /// Only while VoiceOver runs, the scene is active, and this Timeline is
    /// the focused pane showing the live conversation.
    private func announceStatusChange(from previous: String?, to current: String?) {
        guard UIAccessibility.isVoiceOverRunning, scenePhase == .active, matchesLiveTimeline,
              let message = TimelineLiveState.turnEndAnnouncement(
                agentName: TimelineSpeaker.name(agent: speakerAgent), previous: previous, current: current,
                isFocusedPane: paneIsFocused) else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private var contentScope: String {
        "\(activeOwner?.uuidString ?? "none"):\(timeline.generation ?? 0):\(timeline.identity?.nativeSessionId ?? "")"
    }
    @MainActor private func loadContent(_ reference: String, scope: String) async throws -> Data {
        guard matchesLiveTimeline, scope == contentScope, timeline.phase == .ready else { throw AgentBridgeError.closed }
        let result = try await contentFiles.data(key: "\(scope):\(reference)") {
            #if DEBUG && targetEnvironment(simulator)
            if ScreenshotFixtures.enabled { return try AgentTimelineScreenshotFixture.content(reference: reference) }
            #endif
            guard let client = activeClient, let identity = timeline.identity, let generation = timeline.generation else { throw AgentBridgeError.closed }
            return try await client.content(reference: reference, generation: generation, identity: identity)
        }
        try Task.checkCancellation()
        guard matchesLiveTimeline, scope == contentScope, timeline.phase == .ready else { throw AgentBridgeError.closed }
        return result
    }

}


/// Render only Pi's standard dialog contract. Option strings are sent back
/// verbatim, including permission scopes supplied by the originating extension.
private struct PiDialogCard: View {
    let dialog: AgentPiDialog
    let isSending: Bool
    let onSubmit: (AgentPiDialogValue) -> Void
    let onUseTerminal: () -> Void
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NeedsAnswerHeader()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: dialog.title)
                    .font(.jost(.title3, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if isSending { ProgressView().accessibilityLabel("Sending answer") }
            }
            if let message = dialog.message, !message.isEmpty {
                Text(verbatim: message)
                    .font(.jost(.subheadline))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            switch dialog.kind {
            case "confirm":
                VStack(spacing: 10) {
                    option("Yes") { onSubmit(.boolean(true)) }.buttonStyle(.herdrPrimary())
                    option("No") { onSubmit(.boolean(false)) }.buttonStyle(ApprovalOptionButtonStyle())
                }
            case "select":
                VStack(spacing: 10) {
                    ForEach(Array(dialog.options.enumerated()), id: \.element) { index, label in
                        if index == 0 {
                            option(label) { onSubmit(.text(label)) }.buttonStyle(.herdrPrimary())
                        } else {
                            option(label) { onSubmit(.text(label)) }.buttonStyle(ApprovalOptionButtonStyle())
                        }
                    }
                }
            case "input":
                TextField("Answer", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("timeline-pi-dialog-answer")
                Button("Submit") { onSubmit(.text(text)) }.buttonStyle(.herdrPrimary)
            default:
                Text("This custom Pi dialog needs Terminal.").font(.jost(.body))
                Button("Use Terminal", action: onUseTerminal).buttonStyle(.herdrSecondary)
            }
        }
        .padding(16)
        .foregroundStyle(Theme.text)
        .needsAnswerCard()
        .disabled(isSending)
        .onAppear { text = dialog.value ?? "" }
        .accessibilityIdentifier("timeline-pi-dialog")
    }
    private func option(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: label).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Conversation rows

/// The agent's name above its turn. VoiceOver treats it as a heading, so the
/// rotor can jump from one turn to the next.
struct TimelineSpeakerRow: View {
    /// The pane's agent string, for example "claude" or "agy".
    let agent: String
    let firstItemID: String
    @ScaledMetric(relativeTo: .footnote) private var iconSize: CGFloat = 13

    var body: some View {
        HStack(spacing: 6) {
            AgentKindIcon(kind: TimelineSpeaker.iconKind(agent: agent), size: iconSize)
            Text(TimelineSpeaker.name(agent: agent))
                .font(.jost(.footnote, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("timeline-speaker-\(firstItemID)")
    }
}

/// Empty space between two items: wider where the speaker changes.
struct TimelineGapRow: View {
    let height: CGFloat

    var body: some View {
        Color.clear
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

/// A short line about the conversation itself, such as "Turn
/// interrupted" or "Pull down to load earlier messages". The words stay
/// muted; only the icon carries the warning or error colour.
struct TimelineNotice: View {
    enum Kind { case info, warning, error }

    let text: String
    let systemImage: String
    var kind: Kind = .info
    /// Centred by default; leading when it heads left-aligned details.
    var alignment: HorizontalAlignment = .center

    init(_ text: String, systemImage: String, kind: Kind = .info, alignment: HorizontalAlignment = .center) {
        self.text = text
        self.systemImage = systemImage
        self.kind = kind
        self.alignment = alignment
    }

    private var iconColor: Color {
        switch kind {
        case .info: Theme.textMuted
        case .warning: Theme.statusWorking
        case .error: Theme.statusBlocked
        }
    }

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(Theme.textMuted)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
        }
        .font(.jost(.caption))
        .multilineTextAlignment(alignment == .leading ? .leading : .center)
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        // One static text element, read and found by its words alone.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isStaticText)
    }
}
