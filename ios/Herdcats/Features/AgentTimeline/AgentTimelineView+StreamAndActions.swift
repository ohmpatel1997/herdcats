import SwiftUI
import UIKit

// MARK: - Agent timeline stream runner, helper setup, and interaction actions

extension AgentTimelineView {
    func beginSetup(reason: HostHelperSetupReason? = nil, shouldUseTerminalOnDismiss: Bool = true) {
        let isNeedsUpgrade: Bool
        if case .unavailable(let code) = timeline.phase {
            isNeedsUpgrade = Self.isNeedsUpgrade(code: code, agent: agent, bridgeVersion: bridgeVersion)
        } else {
            isNeedsUpgrade = false
        }
        let resolvedReason = reason ?? (isNeedsUpgrade ? .updateRequired : .missing)
        setupReason = resolvedReason
        setupShouldUseTerminal = shouldUseTerminalOnDismiss
        setupFeedback = nil
        showsSetup = true
    }
    @MainActor func startHelperInstallation() {
        guard helperInstallTask == nil, !helperStage.isBusy, !isCheckingSetup else { return }
        if helperStage == .installed { isCheckingSetup = true; retry += 1; return }
        let checkOnly = helperStage == .uncertain
        let replacing: Bool
        if case .replacementRequired = helperStage { replacing = true } else { replacing = false }
        let token = UUID()
        helperInstallToken = token
        let ownedConnection = connectionState
        setupFeedback = nil
        helperStage = .checking
        helperMayHaveInstalled = checkOnly
        helperInstallTask = Task { @MainActor in
            do {
                let result: HostHelperSetupDecision
                #if DEBUG && targetEnvironment(simulator)
                if ScreenshotFixtures.enabled {
                    try await Task.sleep(for: .milliseconds(150))
                    let args = ProcessInfo.processInfo.arguments
                    let scenario = args.firstIndex(of: "-hc.timeline-install-result").flatMap { index in
                        index + 1 < args.count ? args[index + 1] : nil
                    } ?? "failure"
                    if scenario == "replacement" && !replacing {
                        if setupReason == .updateRequired {
                            helperStage = .installing
                            helperMayHaveInstalled = true
                            try await Task.sleep(for: .milliseconds(150))
                            fixtureHelperInstalled = true
                            result = .ready
                        } else {
                            result = .replacementRequired(.present(version: "0.1.0", managed: true, compatible: false))
                        }
                    } else if scenario == "external_replacement" && !replacing {
                        result = .replacementRequired(.present(version: "0.1.0", managed: false, compatible: false))
                    } else if scenario == "uncertain" && !checkOnly {
                        helperStage = .installing
                        helperMayHaveInstalled = true
                        throw AgentBridgeError.closed
                    } else if scenario == "probe_failure" {
                        throw AgentBridgeError.closed
                    } else if scenario == "failure" {
                        throw HostHelperSetupError.failed("download_failed")
                    } else {
                        if !checkOnly { helperStage = .installing; helperMayHaveInstalled = true }
                        try await Task.sleep(for: .milliseconds(150))
                        fixtureHelperInstalled = true
                        result = .ready
                    }
                } else {
                    guard let owned = ownedConnection.generation else { throw AgentBridgeError.closed }
                    result = try await connection.setUpHostHelper(
                        replace: replacing, checkOnly: checkOnly, target: setupTarget, owned: owned, agent: agent,
                        reason: setupReason,
                        onStage: { stage in await commitHelperStage(stage, token: token, connection: ownedConnection) })
                }
                #else
                guard let owned = ownedConnection.generation else { throw AgentBridgeError.closed }
                result = try await connection.setUpHostHelper(
                    replace: replacing, checkOnly: checkOnly, target: setupTarget, owned: owned, agent: agent,
                    reason: setupReason,
                    onStage: { stage in await commitHelperStage(stage, token: token, connection: ownedConnection) })
                #endif
                try Task.checkCancellation()
                guard helperInstallToken == token, ownedConnection == connectionState, showsSetup else { return }
                helperInstallTask = nil
                switch result {
                case .ready:
                    helperStage = .installed
                    isCheckingSetup = true
                    retry += 1
                case .missing:
                    helperStage = .idle
                    setupReason = .missing
                    setupFeedback = "No Herdcats Bridge was found. Tap Install Herdcats Bridge to try installation, or use manual setup."
                case .replacementRequired(let probe):
                    helperStage = .replacementRequired(probe)
                    setupFeedback = HostHelperSetupPlan.replacementFeedback(probe: probe)
                case .unsupportedByPinnedInstaller(let agent):
                    helperStage = .idle
                    setupFeedback = "This version of Herdcats can't install a version of Herdcats Bridge that supports \(agent.capitalized) yet."
                case .install: throw HostHelperSetupError.invalidResponse
                }
            } catch {
                guard helperInstallToken == token, ownedConnection == connectionState, showsSetup else { return }
                helperInstallTask = nil
                if let setupError = error as? HostHelperSetupError {
                    if helperMayHaveInstalled && (setupError == .invalidResponse || setupError == .failed("install_failed")) {
                        helperStage = .uncertain
                        setupFeedback = "Installation could not be verified. Check installation before trying again, or use manual setup."
                    } else {
                        helperStage = .idle
                        helperMayHaveInstalled = false
                        setupFeedback = setupError.localizedDescription
                    }
                } else if helperMayHaveInstalled {
                    helperStage = .uncertain
                    setupFeedback = "Installation could not be confirmed. It may have finished on the host. Check installation before trying again, or use manual setup."
                } else {
                    helperStage = .idle
                    setupFeedback = "The host could not be checked. Reconnect and try again, or use manual setup. No installation was started."
                }
            }
        }
    }
    @MainActor func commitHelperStage(_ stage: HostHelperSetupStage, token: UUID, connection: AgentTimelineConnectionState) {
        guard helperInstallToken == token, connection == connectionState, showsSetup else { return }
        helperStage = stage
        if stage == .installing { helperMayHaveInstalled = true }
    }
    @MainActor func cancelHelperInstallation() {
        guard let task = helperInstallTask else { return }
        helperInstallToken = nil
        helperInstallTask = nil
        task.cancel()
        helperStage = helperMayHaveInstalled ? .uncertain : .idle
        setupFeedback = helperMayHaveInstalled
            ? "Installation may have finished on the host. Check installation before trying again."
            : "The host check stopped. Reconnect and try again. No installation was started."
    }
    @MainActor func prepareWaitingRow() async {
        let expected = waitingTaskKey
        waitingKey = nil
        guard expected.eligible, let key = expected.hooks, let agent = ApprovalAgent(rawValue: key.agent) else { return }
        var grace = PhoneAnswersGrace()
        _ = grace.update(eligible: true, now: ProcessInfo.processInfo.systemUptime)
        do { try await Task.sleep(for: .seconds(PhoneAnswersGrace.delay)) } catch { return }
        guard !Task.isCancelled, waitingTaskKey == expected,
            grace.update(eligible: true, now: ProcessInfo.processInfo.systemUptime) else { return }
        waitingKey = expected
        await appModel.phoneAnswers.check(key) {
            guard !Task.isCancelled, waitingTaskKey == expected, hooksContextIsCurrent(key) else { throw HerdrError.notConnected }
            return try await connection.hooksStatus(agent: agent, target: key.target, owned: key.generation)
        }
    }

    @MainActor func respondToApproval(_ pending: AgentPendingApproval, option: AgentApprovalOption) {
        guard showsApproval, let owner = activeOwner, let client = activeClient,
            connectionState.isReady, scenePhase == .active,
            let current = timeline.pendingApproval,
            ApprovalResponseState.Scope(current) == ApprovalResponseState.Scope(pending),
            current.options.contains(option) else { return }
        approvalResponse.sync(current)
        guard let token = approvalResponse.begin(current) else { return }
        let ownedConnection = connectionState
        Task { @MainActor in
            do {
                let result = try await client.respond(requestId: current.requestId, option: option.number, labelLines: option.labelLines)
                guard approvalViewVisible, activeOwner == owner, connectionState == ownedConnection, scenePhase == .active,
                    timeline.phase == .ready, timeline.identity == current.identity,
                    timeline.generation == current.generation else { return }
                approvalResponse.sync(timeline.pendingApproval)
                let effects = approvalResponse.succeed(token: token, confirmed: result.confirmed,
                    focusComposer: ApprovalResponseState.focusesComposer(agent: current.agent, option: option))
                if effects.haptic { HapticFeedback.impact(.light) }
                if effects.focusComposer { onFocusComposer() }
            } catch {
                guard activeOwner == owner, connectionState == ownedConnection, scenePhase == .active else { return }
                approvalResponse.sync(timeline.pendingApproval)
                approvalResponse.fail(token: token, error: (error as? AgentBridgeError) ?? .closed)
            }
        }
    }

    @MainActor func respondToQuestion(_ pending: AgentPendingQuestion, skip: Bool = false) {
        guard showsQuestion, let owner = activeOwner, let client = activeClient,
            connectionState.isReady, scenePhase == .active,
            let current = timeline.pendingQuestion, current == pending else { return }
        questionResponse.sync(current)
        let answers = questionResponse.answers
        guard let token = questionResponse.begin(skip: skip) else { return }
        let ownedConnection = connectionState
        Task { @MainActor in
            do {
                let confirmed: Bool
                if skip { confirmed = try await client.skipQuestion(requestId: current.requestId) }
                else { confirmed = try await client.respondQuestion(requestId: current.requestId, answers: answers ?? []) }
                guard approvalViewVisible, activeOwner == owner, connectionState == ownedConnection, scenePhase == .active,
                    timeline.phase == .ready, timeline.identity == current.identity,
                    timeline.generation == current.generation else { return }
                questionResponse.sync(timeline.pendingQuestion)
                questionResponse.succeed(token: token, confirmed: confirmed)
                if confirmed { HapticFeedback.impact(.light) }
            } catch {
                guard approvalViewVisible, activeOwner == owner, connectionState == ownedConnection, scenePhase == .active,
                    timeline.phase == .ready, timeline.identity == current.identity,
                    timeline.generation == current.generation else { return }
                questionResponse.sync(timeline.pendingQuestion)
                questionResponse.fail(token: token, error: (error as? AgentBridgeError) ?? .closed)
            }
        }
    }

    @MainActor func run() async {
        guard !Task.isCancelled else { return }
        let runKey = taskKey
        historyLoader.cancel()
        approvalResponse.reset()
        questionResponse.reset()
        let owner = UUID()
        activeOwner = owner
        pageError = nil
        isPaging = false
        await AgentTimelineStreamRunner(
            timeline: timeline, key: runKey, owner: owner,
            currentKey: { taskKey },
            isOwner: { activeOwner == owner },
            metadata: {
                let capabilities = await connection.bridgeCapabilities(for: runKey.connection.generation)
                let version = await connection.bridgeVersion(for: runKey.connection.generation)
                return .init(capabilities: capabilities, version: version)
            },
            publish: { metadata in
                bridgeCapabilities = metadata.capabilities
                bridgeVersion = metadata.version
                Self.publishBridgeVersion(metadata.version, to: bridgeUpgrade, owner: owner, activeOwner: activeOwner)
            },
            prepare: {
                clearCodexDaemonResult()
                return await prepareScreenshotTimeline(owner: owner)
            },
            open: { onEvent in
                try await connection.openAgentTimeline(paneId: runKey.paneId, agent: runKey.agent, onEvent: onEvent)
            },
            attach: { activeClient = $0 },
            acceptedEvent: {
                approvalResponse.sync(timeline.pendingApproval)
                questionResponse.sync(timeline.pendingQuestion)
            },
            close: { await connection.endAgentTimeline($0) },
            finish: {
                if activeOwner == owner {
                    activeClient = nil
                    activeOwner = nil
                    isPaging = false
                }
            }
        ).run()
    }

    @MainActor private func prepareScreenshotTimeline(owner: UUID) async -> Bool {
        #if DEBUG && targetEnvironment(simulator)
            if ScreenshotFixtures.enabled {
                if ScreenshotFixtures.screen == "timeline-loading" { return true }
                if ScreenshotFixtures.screen == "timeline-history-position" { following = false }
                if ScreenshotFixtures.screen.contains("helper-old") || ScreenshotFixtures.screen.contains("needs-upgrade") {
                    bridgeVersion = "0.1.4"
                } else if ScreenshotFixtures.screen == "optional-upgrade-menu" {
                    bridgeVersion = "0.2.0"
                }
                if ScreenshotFixtures.screen == "timeline-codex-no-session" || ProcessInfo.processInfo.arguments.contains("-hc.split-capture") {
                    bridgeCapabilities = AgentBridgeCapabilities(claudeTimeline: true, codexTimeline: true, codexDaemonConfig: true, codexDaemonStop: true, recordContent: true)
                }
                if AgentTimelineScreenshotFixture.showsApproval {
                    bridgeCapabilities = AgentBridgeCapabilities(claudeTimeline: true, codexTimeline: true, recordContent: true, approvals: true)
                }
                if AgentTimelineScreenshotFixture.showsQuestion {
                    bridgeCapabilities = AgentBridgeCapabilities(claudeTimeline: true, codexTimeline: true, recordContent: true, approvals: true, questions: true)
                }
                Self.publishBridgeVersion(bridgeVersion, to: bridgeUpgrade, owner: owner, activeOwner: activeOwner)
                do {
                    try timeline.consume(AgentTimelineScreenshotFixture.frame(
                        paneId: paneId,
                        helperInstalled: fixtureHelperInstalled || (retry > 0 && ProcessInfo.processInfo.arguments.contains("-hc.timeline-helper-installed"))
                    ), owner: owner)
                    if AgentTimelineScreenshotFixture.showsApproval {
                        try timeline.consume(AgentTimelineScreenshotFixture.approvalFrame(paneId: paneId, agent: ScreenshotFixtures.paneAgent), owner: owner)
                        AgentTimelineScreenshotFixture.prepareApprovalResponse(approvalResponse, pending: timeline.pendingApproval)
                        updateTimelineSheet()
                    }
                    if AgentTimelineScreenshotFixture.showsQuestion {
                        try timeline.consume(AgentTimelineScreenshotFixture.questionFrame(paneId: paneId), owner: owner)
                        questionResponse.sync(timeline.pendingQuestion)
                    }
                    if ScreenshotFixtures.screen.hasPrefix("timeline-model") {
                        await timeline.modelControl.loadScreenshotFixture(agent: ScreenshotFixtures.paneAgent)
                    }
                } catch { timeline.end(owner: owner, error: (error as? AgentBridgeError) ?? .invalidFrame) }
                return true
            }
        #endif
        return false
    }

    @MainActor func mergeHistoryPreservingPosition(
        _ page: AgentBridgePayload, owner: UUID, generation: UInt64
    ) throws {
        // Capture at response time so scrolling while a page is in flight is respected.
        let visible = entryFrames.frames
            .filter { $0.value.maxY > topOverlayInset && $0.value.minY < viewportHeight - bottomOverlayInset - approvalInset }
            .min { $0.value.minY < $1.value.minY }
        try timeline.mergeHistory(page, owner: owner, generation: generation)
        guard activeOwner == owner, timeline.generation == generation, let visible,
              let item = conversationItems.first(where: { $0.entries.contains { $0.id == visible.key } })
        else { return }
        historyScrollAnchor = TimelineHistoryScrollAnchor(
            id: item.id, top: visible.value.minY, height: visible.value.height, viewportHeight: viewportHeight)
    }

    @MainActor func refreshHistory() async {
        await historyLoader.load { await loadOlder() }
    }

    @MainActor func loadOlder() async {
        guard timeline.phase == .ready, timeline.hasMore, !isPaging,
            let owner = activeOwner, let generation = timeline.generation, let before = timeline.before
        else {
            TimelineHistoryDiagnostics.record("history.skipped ready=\(timeline.phase == .ready) has_more=\(timeline.hasMore) paging=\(isPaging) owner_present=\(activeOwner != nil) generation_present=\(timeline.generation != nil) cursor_present=\(timeline.before != nil)")
            return
        }
        let attempt = UUID().uuidString
        let started = ContinuousClock.now
        var stage = "request"
        TimelineHistoryDiagnostics.record("history.start attempt=\(attempt) client=\(activeClient?.id.uuidString ?? "none") generation=\(generation) loaded_entries=\(timeline.entries.count) cursor_in_loaded_entries=\(timeline.entries.contains { $0.id == before }) task_cancelled=\(Task.isCancelled)")
        following = false
        isPaging = true
        pageError = nil
        defer { if activeOwner == owner { isPaging = false } }
        let ownedConnection = connectionState
        do {
            #if DEBUG && targetEnvironment(simulator)
                if ScreenshotFixtures.enabled {
                    if ScreenshotFixtures.screen == "timeline-history-position" {
                        try await Task.sleep(for: .seconds(5))
                    } else if ProcessInfo.processInfo.arguments.contains("-hc.timeline-history-delay") {
                        try await Task.sleep(for: .seconds(2))
                    }
                    let page = try AgentTimelineScreenshotFixture.historyPage(paneId: paneId, generation: generation)
                    try mergeHistoryPreservingPosition(page, owner: owner, generation: generation)
                    TimelineHistoryDiagnostics.record("history.fixture_merged attempt=\(attempt) loaded_entries=\(timeline.entries.count)")
                    return
                }
            #endif
            guard let client = activeClient else { throw AgentBridgeError.closed }
            let page = try await client.request(
                .history, params: AgentBridgeParams(generation: generation, before: before), timeout: 15)
            try Task.checkCancellation()
            stage = "connection_validation"
            TimelineHistoryDiagnostics.record("history.response attempt=\(attempt) elapsed=\(started.duration(to: .now)) response_generation=\(page.generation.map(String.init) ?? "missing") entries=\(page.entries?.count ?? -1) has_more=\(page.hasMore.map(String.init) ?? "missing") identity_present=\(page.identity != nil) pane_match=\(page.identity?.paneId == timeline.identity?.paneId) terminal_match=\(page.identity?.terminalId == timeline.identity?.terminalId) agent_match=\(page.identity?.agent == timeline.identity?.agent) session_match=\(page.identity?.nativeSessionId == timeline.identity?.nativeSessionId)")
            try ownedConnection.requireCurrent(connectionState)
            stage = "merge"
            try mergeHistoryPreservingPosition(page, owner: owner, generation: generation)
            TimelineHistoryDiagnostics.record("history.merged attempt=\(attempt) elapsed=\(started.duration(to: .now)) loaded_entries=\(timeline.entries.count) has_more=\(timeline.hasMore) owner_current=\(activeOwner == owner) generation_current=\(timeline.generation == generation)")
        } catch {
            TimelineHistoryDiagnostics.record("history.failed attempt=\(attempt) stage=\(stage) reason=\(TimelineHistoryDiagnostics.reason(error)) elapsed=\(started.duration(to: .now)) task_cancelled=\(Task.isCancelled) owner_current=\(activeOwner == owner) generation_current=\(timeline.generation == generation) connection_current=\(ownedConnection == connectionState)", failure: true)
            if !Task.isCancelled, activeOwner == owner, timeline.generation == generation {
                pageError = "Earlier messages could not load. Pull down to try again."
            }
        }
    }
}

/// The production async lifetime, shared by SwiftUI and controlled transport tests.
/// Dependencies stop at the transport/metadata boundary; owner and event policy live here.
@MainActor struct AgentTimelineStreamRunner {
    struct Metadata {
        var capabilities: AgentBridgeCapabilities?
        var version: String?
    }
    let timeline: AgentTimelineState
    let key: AgentTimelineView.TaskKey
    let owner: UUID
    let currentKey: () -> AgentTimelineView.TaskKey
    let isOwner: () -> Bool
    let metadata: () async -> Metadata
    let publish: (Metadata) -> Void
    var prepare: () async -> Bool = { false }
    let open: (@escaping @Sendable (AgentBridgeFrame) async throws -> Void) async throws -> AgentBridgeClient
    let attach: (AgentBridgeClient) -> Void
    var acceptedEvent: () -> Void = {}
    let close: (AgentBridgeClient) async -> Void
    var finish: () -> Void = {}

    private var isCurrent: Bool {
        key == currentKey() && isOwner() && key.isActive && key.connection.isReady
    }
    private func retire() {
        timeline.retire(owner: owner, preservingContent: key.connection == currentKey().connection)
    }
    func run() async {
        // A queued retired task must not steal the store before its first await.
        // Current inactive/unready owners still begin below, publishing neutral suspension.
        guard !Task.isCancelled, key == currentKey(), isOwner() else { return }
        timeline.begin(owner: owner, paneId: key.paneId, connection: key.connection, isActive: key.isActive, agent: key.agent)
        let initial = await metadata()
        guard !Task.isCancelled, isCurrent else { retire(); finish(); return }
        publish(initial)
        if await prepare() { return }
        guard !Task.isCancelled, isCurrent else { retire(); finish(); return }
        var opened: AgentBridgeClient?
        do {
            let client = try await open { frame in try await commit(frame) }
            opened = client
            let capabilities = await client.capabilities
            let recorded = await metadata()
            try Task.checkCancellation()
            guard isCurrent else { throw CancellationError() }
            timeline.modelControl.connect(client, supported: capabilities?.modelControl == true)
            timeline.connectPi(capabilities?.pi == true ? client : nil)
            timeline.connectPrompts(capabilities?.cursorPrompts == true ? client : nil)
            attach(client)
            publish(recorded)
            try await client.waitUntilClosed()
        } catch {
            if Task.isCancelled || error is CancellationError || !isCurrent {
                retire()
            } else {
                // Handshake metadata can be recorded before open throws (without an event/client).
                // Revalidate after every lookup has completed, then publish metadata + failure
                // in the same MainActor turn. A retired attempt cannot replace current guidance.
                let recorded = await metadata()
                if !Task.isCancelled, isCurrent {
                    publish(recorded)
                    timeline.end(owner: owner, error: (error as? AgentBridgeError) ?? .unavailable("bridge_unavailable"))
                } else {
                    retire()
                }
            }
        }
        if let opened { await close(opened) }
        finish()
    }
    private func commit(_ frame: AgentBridgeFrame) async throws {
        let recorded = await metadata()
        try key.connection.requireCurrent(currentKey().connection)
        guard !Task.isCancelled, isCurrent else { throw AgentBridgeError.closed }
        publish(recorded)
        try timeline.consume(frame, owner: owner)
        acceptedEvent()
    }
}
