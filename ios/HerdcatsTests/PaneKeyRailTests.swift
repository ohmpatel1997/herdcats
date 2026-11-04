import Foundation
import Testing
@testable import Herdcats

@Suite("Pane key rail")
@MainActor struct PaneKeyRailTests {
    private func route(
        isOffline: Bool = false,
        isReady: Bool = true,
        hasGeneration: Bool = true,
        isSceneActive: Bool = true,
        isFocused: Bool = true,
        isRecording: Bool = false,
        queueState: PaneLiveInputQueueState? = nil,
        liveInputEnabled: Bool = false,
        hasFreshRead: Bool = true
    ) -> PaneKeyRoute {
        PaneKeyRoute.resolve(
            isOffline: isOffline,
            isReadyForTerminalInput: isReady,
            hasGeneration: hasGeneration,
            isSceneActive: isSceneActive,
            isFocused: isFocused,
            isRecording: isRecording,
            queueState: queueState,
            liveInputEnabled: liveInputEnabled,
            hasFreshRead: hasFreshRead
        )
    }

    private func notice(
        _ route: PaneKeyRoute,
        pauseReason: String? = nil,
        transient: String? = nil,
        sessionError: String? = nil,
        resyncReadFailures: Int = 0,
        backoffAtCap: Bool = false,
        showsTimeline: Bool = false
    ) -> PaneKeyNotice? {
        PaneKeyNotice.resolve(
            route: route,
            pauseReason: pauseReason,
            transient: transient,
            sessionError: sessionError,
            resyncReadFailures: resyncReadFailures,
            backoffAtCap: backoffAtCap,
            showsTimeline: showsTimeline
        )
    }

    @Test func liveRouteWhenSessionReady() {
        #expect(route(queueState: .ready, liveInputEnabled: true) == .live)
        #expect(route(queueState: .sending, liveInputEnabled: true) == .live)
        #expect(PaneKeyRoute.live.sendsKeys)
    }

    @Test func oneShotRouteWhenConnectedWithoutLiveSession() {
        #expect(route() == .oneShot)
        #expect(route(queueState: .ready) == .oneShot)
        #expect(route(queueState: .sending) == .oneShot)
        #expect(PaneKeyRoute.oneShot.sendsKeys)
        // Not connected yet, or no generation to send for: keys wait.
        #expect(route(isReady: false) == .unavailable(.connecting))
        #expect(route(hasGeneration: false) == .unavailable(.connecting))
        #expect(!PaneKeyRoute.unavailable(.connecting).sendsKeys)
    }

    @Test func activeLiveSessionCountsAsReadyBeforeTheConnectingCheck() {
        // A Live session is installed only after a fresh read on a live
        // connection, so it is enough on its own. This keeps keys working in
        // the simulator's screenshot mode, which has no connection generation.
        #expect(route(isReady: false, hasGeneration: false, liveInputEnabled: true) == .live)
        #expect(route(liveInputEnabled: true, hasFreshRead: false) == .live)
        // Offline and recording still win.
        #expect(route(isOffline: true, liveInputEnabled: true) == .unavailable(.offline))
        #expect(route(isRecording: true, liveInputEnabled: true) == .unavailable(.recording))
    }

    @Test func inactiveOrUnfocusedWithoutLiveIsConnecting() {
        #expect(route(isSceneActive: false) == .unavailable(.connecting))
        #expect(route(isFocused: false) == .unavailable(.connecting))
        #expect(route(isFocused: false, queueState: .needsResync) == .unavailable(.connecting))
    }

    @Test func oneShotWaitsForAReadAfterOpen() {
        let generation = ConnectionGeneration(rawValue: 1)
        var reads = PaneFreshReadGate()
        #expect(route(hasFreshRead: reads.hasFreshRead(generation: generation)) == .unavailable(.reading))
        // A failed or overtaken read doesn't count.
        reads.finishRead(reads.startRead(generation: generation), outcome: .failed)
        reads.finishRead(reads.startRead(generation: generation), outcome: .superseded)
        #expect(!reads.hasFreshRead(generation: generation))
        reads.finishRead(reads.startRead(generation: generation), outcome: .fresh)
        #expect(route(hasFreshRead: reads.hasFreshRead(generation: generation)) == .oneShot)
        // No generation (not connected yet): never fresh.
        #expect(!reads.hasFreshRead(generation: nil))
    }

    @Test func oneShotWaitsForAReadAfterReconnect() {
        let before = ConnectionGeneration(rawValue: 1)
        let after = ConnectionGeneration(rawValue: 2)
        var reads = PaneFreshReadGate()
        reads.finishRead(reads.startRead(generation: before), outcome: .fresh)
        // Offline stops input. A read that started before that, and lands
        // later, still shows the old screen.
        let startedBeforeDrop = reads.startRead(generation: before)
        reads.inputStopped()
        reads.finishRead(startedBeforeDrop, outcome: .fresh)
        #expect(route(hasFreshRead: reads.hasFreshRead(generation: after)) == .unavailable(.reading))
        // A read on the old generation doesn't count for the new one.
        reads.finishRead(reads.startRead(generation: before), outcome: .fresh)
        #expect(!reads.hasFreshRead(generation: after))
        reads.finishRead(reads.startRead(generation: after), outcome: .fresh)
        #expect(route(hasFreshRead: reads.hasFreshRead(generation: after)) == .oneShot)
    }

    @Test func oneShotWaitsForAReadAfterForegroundReturn() {
        let generation = ConnectionGeneration(rawValue: 3)
        var reads = PaneFreshReadGate()
        reads.finishRead(reads.startRead(generation: generation), outcome: .fresh)
        #expect(route(hasFreshRead: reads.hasFreshRead(generation: generation)) == .oneShot)
        // Going to the background stops input; the same connection comes back.
        reads.inputStopped()
        #expect(route(isSceneActive: false, hasFreshRead: reads.hasFreshRead(generation: generation))
            == .unavailable(.connecting))
        #expect(route(hasFreshRead: reads.hasFreshRead(generation: generation)) == .unavailable(.reading))
        reads.finishRead(reads.startRead(generation: generation), outcome: .fresh)
        #expect(route(hasFreshRead: reads.hasFreshRead(generation: generation)) == .oneShot)
    }

    @Test func waitingForTheFirstReadIsSilentUntilAReadFails() throws {
        let reading = PaneKeyRoute.unavailable(.reading)
        #expect(!reading.sendsKeys)
        #expect(notice(reading, sessionError: "An older error.") == nil)
        let failed = try #require(notice(reading, resyncReadFailures: 1))
        #expect(failed.text == PaneKeyNotice.readFailed)
        #expect(!failed.offersRetry)
        #expect(notice(reading, resyncReadFailures: 3, backoffAtCap: true)?.offersRetry == true)
    }

    @Test func composeSendWaitsForQueuedOrPausedKeys() {
        #expect(PaneComposeGate.allowsSend(queueState: nil, isDraining: false))
        #expect(PaneComposeGate.allowsSend(queueState: .ready, isDraining: false))
        // A key is waiting or on its way: Send would overtake it in the lane.
        #expect(!PaneComposeGate.allowsSend(queueState: .sending, isDraining: true))
        #expect(!PaneComposeGate.allowsSend(queueState: .ready, isDraining: true))
        // Keys are paused for a fresh read.
        #expect(!PaneComposeGate.allowsSend(queueState: .needsResync, isDraining: false))
    }

    @Test func needsResyncIsResyncingNotOneShot() {
        // After a send that may not have arrived, a key must not go out by
        // another route before the screen has been read again.
        #expect(route(queueState: .needsResync) == .unavailable(.resyncing))
        #expect(route(queueState: .needsResync, liveInputEnabled: true) == .unavailable(.resyncing))
        #expect(!PaneKeyRoute.unavailable(.resyncing).sendsKeys)
    }

    @Test func offlineIsDimmedWithoutText() {
        let offline = route(isOffline: true, queueState: .ready, liveInputEnabled: true)
        #expect(offline == .unavailable(.offline))
        #expect(!offline.sendsKeys)
        #expect(notice(offline, pauseReason: "reason", transient: "transient", sessionError: "error") == nil)
        #expect(route(isRecording: true) == .unavailable(.recording))
        #expect(notice(.unavailable(.recording), sessionError: "error") == nil)
    }

    @Test func connectingAndResyncingShowPlainText() {
        let connecting = notice(.unavailable(.connecting))
        #expect(connecting == PaneKeyNotice(text: "Connecting. Keys work once the connection is ready.", offersRetry: false))
        let resyncing = notice(.unavailable(.resyncing))
        #expect(resyncing == PaneKeyNotice(text: "Checking the screen. Keys come back once it’s read.", offersRetry: false))
        for text in [connecting?.text, resyncing?.text, PaneKeyNotice.readFailed] {
            #expect(text?.contains("in a moment") == false)
        }
    }

    @Test func pauseReasonWinsOverCheckingTheScreen() throws {
        let paused = try #require(notice(
            .unavailable(.resyncing),
            pauseReason: "That key may not have reached the pane.",
            transient: "An older notice.",
            sessionError: "An older error."
        ))
        #expect(paused.text.hasPrefix("That key may not have reached the pane."))
        #expect(paused.text == "That key may not have reached the pane. Checking the screen. Keys come back once it’s read.")
        #expect(!paused.offersRetry)
    }

    @Test func coreRefusalNoticeNamesTheKey() throws {
        let one = PaneKeyNotice.coreRefusal(["ctrl+plus"])
        #expect(one == "Herdr Core doesn’t accept “ctrl+plus”. That key and any after it weren’t sent.")
        let several = PaneKeyNotice.coreRefusal(["esc", "alt+plus"])
        #expect(several.contains("“esc alt+plus”"))
        // A refusal pressed nothing, so keys stay on and the notice wins
        // over an older send error.
        let shown = try #require(notice(.oneShot, transient: one, sessionError: "An older error."))
        #expect(shown.text == one)
        #expect(notice(.live, transient: one)?.text == one)
    }

    @Test func failedResyncReadSaysSoAndOffersRetryOnlyAtTheCap() throws {
        let early = try #require(notice(.unavailable(.resyncing), pauseReason: "That key may not have reached the pane.",
                                        resyncReadFailures: 1, backoffAtCap: false))
        #expect(early.text == "Couldn’t read the pane, so keys stay paused. Trying again.")
        #expect(!early.offersRetry)
        let capped = try #require(notice(.unavailable(.resyncing), resyncReadFailures: 3, backoffAtCap: true))
        #expect(capped.text == early.text)
        #expect(capped.offersRetry)
        // Retry belongs to a failing read only; the cap alone doesn't add it.
        #expect(notice(.unavailable(.resyncing), backoffAtCap: true)?.offersRetry == false)
    }

    @Test func noticeFallsBackToTransientThenSessionError() {
        #expect(notice(.live) == nil)
        #expect(notice(.oneShot, sessionError: "Could not load that image.")?.text == "Could not load that image.")
        #expect(notice(.oneShot, transient: "Nothing was sent.", sessionError: "Could not load that image.")?.text
            == "Nothing was sent.")
        // The connecting text explains why keys are off, ahead of an old error.
        #expect(notice(.unavailable(.connecting), sessionError: "Could not load that image.")?.text
            == PaneKeyNotice.connecting)
    }

    @Test func noticeIsNilInTheTimeline() {
        for route in [PaneKeyRoute.live, .oneShot, .unavailable(.connecting), .unavailable(.resyncing)] {
            #expect(notice(route, pauseReason: "reason", transient: "transient", sessionError: "error",
                           resyncReadFailures: 1, backoffAtCap: true, showsTimeline: true) == nil)
        }
    }

    @Test func railKeysAreAcceptedFromComposeButTypedTextIsNot() {
        #expect(PaneKeyRoute.accepts(.keys(["esc"]), surface: .liveToolbar))
        #expect(PaneKeyRoute.accepts(.text("a"), surface: .liveToolbar))
        #expect(PaneKeyRoute.accepts(.keys(["esc"]), surface: .composeDraft))
        #expect(!PaneKeyRoute.accepts(.text("a"), surface: .composeDraft))
        #expect(!PaneKeyRoute.accepts(.keys(["esc"]), surface: .voiceRecording))
        #expect(!PaneKeyRoute.accepts(.text("a"), surface: .voiceRecording))
    }

    @Test func railKeyPathSendsOneShotAsCommandAndActiveLiveThroughShell() {
        let generation = ConnectionGeneration(rawValue: 7)
        let live = PaneLiveInputSession(paneId: "w1:p1", generation: generation)
        let oneShot = PaneLiveInputSession(paneId: "w1:p1", generation: generation, kind: .oneShot)
        #expect(HerdrConnection.railKeyPath(session: live, active: live) == .liveShell)
        #expect(HerdrConnection.railKeyPath(session: oneShot, active: nil) == .command)
        // A one-shot batch still waiting when Live starts goes out as a command.
        #expect(HerdrConnection.railKeyPath(session: oneShot, active: live) == .command)
        // One-shot and Live tokens never compare equal, so they never merge.
        #expect(oneShot != live)
    }

    @Test func staleLiveTokenIsExpiredNotSentAsCommand() {
        let generation = ConnectionGeneration(rawValue: 7)
        let stale = PaneLiveInputSession(paneId: "w1:p1", generation: generation)
        let current = PaneLiveInputSession(paneId: "w1:p1", generation: generation)
        #expect(HerdrConnection.railKeyPath(session: stale, active: nil) == .expired)
        #expect(HerdrConnection.railKeyPath(session: stale, active: current) == .expired)
    }

    @Test func coreInvalidParamsOnKeysIsClassifiedAsRefused() {
        let refused = CoreRPCError.remote(code: -32602, kind: "invalid_params",
                                          message: "unknown key \"plus\"", hint: nil)
        #expect(PaneLiveInputFailure.classify(refused, event: .keys(["ctrl+plus"])) == .coreRefusedKeys(["ctrl+plus"]))
        // Anything that may have pressed a key is uncertain.
        #expect(PaneLiveInputFailure.classify(CoreRPCError.timeout, event: .keys(["esc"])) == .uncertain)
        #expect(PaneLiveInputFailure.classify(HerdrError.timeout("pane send-keys"), event: .keys(["esc"])) == .uncertain)
        #expect(PaneLiveInputFailure.classify(HerdrError.notConnected, event: .keys(["esc"])) == .uncertain)
        let otherRemote = CoreRPCError.remote(code: -32000, kind: "internal", message: "failed", hint: nil)
        #expect(PaneLiveInputFailure.classify(otherRemote, event: .keys(["esc"])) == .uncertain)
        // Typed text keeps the stop, even when Core names it invalid.
        #expect(PaneLiveInputFailure.classify(refused, event: .text("a")) == .uncertain)
        // Another bad parameter: still nothing pressed, but no key is named.
        let badTerminal = CoreRPCError.remote(code: -32602, kind: "invalid_params",
                                              message: "unknown terminal \"t9\"", hint: nil)
        let batch = PaneLiveInputFailure.classify(badTerminal, event: .keys(["esc"]))
        #expect(batch == .coreRefusedBatch)
        #expect(batch.pressedNothing)
        #expect(!PaneLiveInputFailure.uncertain.pressedNothing)
        #expect(!PaneKeyNotice.coreRefusedBatch.contains("esc"))
    }

    @Test func taskKeyChangesWhenQueueStopsOrRetryIsTapped() {
        let base = LiveSessionTaskKey(paneId: "w1:p1", isOffline: false, isSceneActive: true,
                                      liveInputEnabled: false, isFocused: true)
        var stopped = base
        stopped.needsResync = true
        var retried = stopped
        retried.retryRequests += 1
        #expect(base != stopped)
        #expect(stopped != retried)
        #expect(base == LiveSessionTaskKey(paneId: "w1:p1", isOffline: false, isSceneActive: true,
                                           liveInputEnabled: false, isFocused: true))
    }
}
