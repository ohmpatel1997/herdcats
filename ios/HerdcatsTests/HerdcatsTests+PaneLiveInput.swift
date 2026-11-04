import Foundation
import Security
import NIOSSH
import SwiftUI
import Testing
@testable import Herdcats

actor TestLiveGenerationState {
    private var current: ConnectionGeneration

    init(_ current: ConnectionGeneration) {
        self.current = current
    }

    func require(_ owned: ConnectionGeneration) throws {
        guard current == owned else { throw HerdrError.notConnected }
    }

    func replace(with generation: ConnectionGeneration) {
        current = generation
    }
}

@Suite("Pane live input delivery")
struct PaneLiveInputDeliveryTests {
    @Test
    @MainActor
    func recordsWireOrderWithDelayedFirstSend() async throws {
        let gate = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(firstSendGate: gate)
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 32)
        let session = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 3)
        )

        #expect(queue.enqueue(.text("a"), session: session))
        #expect(queue.enqueue(.text("b"), session: session))
        #expect(queue.enqueue(.keys(["backspace"]), session: session))
        #expect(queue.enqueue(.text("c"), session: session))
        #expect(queue.enqueue(.keys(["enter"]), session: session))
        #expect(queue.enqueue(.keys(["esc"]), session: session))
        #expect(queue.enqueue(.keys(["1"]), session: session)) // blocked choice
        #expect(queue.enqueue(.keys(["up"]), session: session)) // command-pad shortcut
        #expect(queue.state == .sending)

        try await Task.sleep(for: .milliseconds(30))
        #expect(await sender.wire.isEmpty)

        gate.release(())
        try await waitUntilLiveIdle(queue)

        // Adjacent same-kind events coalesce; text/keys boundaries keep order.
        #expect(await sender.wire == [
            "text:ab",
            "keys:backspace",
            "text:c",
            "keys:enter,esc,1,up"
        ])
        #expect(queue.acknowledgedCount == 8)
        #expect(queue.state == .ready)
        #expect(queue.pendingCount == 0)
    }

    @Test
    @MainActor
    func acknowledgedCountIncrementsPerSuccessfulSendWhileLaterEventsRemainQueued() async throws {
        let firstGate = ExternallyReleasedWait<Void>()
        let secondGate = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(sendGates: [firstGate, secondGate])
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 8)
        let session = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 9)
        )

        #expect(queue.acknowledgedCount == 0)
        #expect(queue.enqueue(.text("a"), session: session))
        try await waitUntil { queue.isDraining && queue.pendingCount == 0 }
        #expect(queue.enqueue(.text("b"), session: session))
        #expect(queue.enqueue(.text("c"), session: session))
        #expect(queue.enqueue(.keys(["enter"]), session: session))
        #expect(queue.pendingCount == 2)

        firstGate.release(())
        try await waitUntil {
            queue.acknowledgedCount == 1 && queue.pendingCount >= 1 && queue.isDraining
        }

        #expect(queue.acknowledgedCount == 1)
        #expect(queue.pendingCount >= 1)
        #expect(queue.state == .sending)
        #expect(await sender.wire == ["text:a"])

        secondGate.release(())
        // Third send has no gate — drain finishes after second releases.
        try await waitUntilLiveIdle(queue)

        // The "bc" batch acknowledges both of its events.
        #expect(queue.acknowledgedCount == 4)
        #expect(await sender.wire == ["text:a", "text:bc", "keys:enter"])
        #expect(queue.pendingCount == 0)
    }

    @Test
    @MainActor
    func acknowledgedCountDoesNotIncrementOnFailedDelivery() async throws {
        let gate = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(sendGates: [gate])
        await sender.setFailAfterGateWith(HerdrError.timeout(HerdrConnection.herdrDiagnosticLabel))
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 8)
        let session = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 2)
        )

        #expect(queue.enqueue(.text("maybe"), session: session))
        #expect(queue.enqueue(.text("later"), session: session))
        gate.release(())
        try await waitUntil { queue.state == .needsResync }

        #expect(queue.acknowledgedCount == 0)
        #expect(await sender.attemptCount == 1)
    }

    @Test
    @MainActor
    func coalescesKeystrokeBurstWhileSendIsInFlight() async throws {
        let gate = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(firstSendGate: gate)
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 2)
        let session = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 1)
        )

        // First key after idle goes out immediately, alone.
        #expect(queue.enqueue(.text("h"), session: session))
        try await waitUntil { queue.isDraining && queue.pendingCount == 0 }
        #expect(await sender.wire.isEmpty)
        #expect(await sender.attemptCount == 1)

        // A burst longer than maxPending fits because it coalesces.
        for character in "ello, world" {
            #expect(queue.enqueue(.text(String(character)), session: session))
        }
        #expect(queue.pendingCount == 1)

        gate.release(())
        try await waitUntilLiveIdle(queue)

        #expect(await sender.wire == ["text:h", "text:ello, world"])
        #expect(queue.acknowledgedCount == 12)
    }

    @Test
    @MainActor
    func doesNotCoalesceAcrossSessions() async throws {
        let gate = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(firstSendGate: gate)
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 8)
        let first = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 1)
        )
        let second = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 2)
        )

        #expect(queue.enqueue(.text("x"), session: first))
        try await waitUntil { queue.isDraining && queue.pendingCount == 0 }
        #expect(queue.enqueue(.text("a"), session: first))
        #expect(queue.enqueue(.text("b"), session: second))
        #expect(queue.pendingCount == 2)

        gate.release(())
        try await waitUntilLiveIdle(queue)

        #expect(await sender.wire == ["text:x", "text:a", "text:b"])
        #expect(queue.acknowledgedCount == 3)
    }

    @Test
    @MainActor
    func failedCoalescedBatchIsNotRetriedOrAcknowledged() async throws {
        let firstGate = ExternallyReleasedWait<Void>()
        let secondGate = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(sendGates: [firstGate, secondGate])
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 8)
        let session = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 1)
        )

        #expect(queue.enqueue(.text("a"), session: session))
        try await waitUntil { queue.isDraining && queue.pendingCount == 0 }
        #expect(queue.enqueue(.text("b"), session: session))
        #expect(queue.enqueue(.text("c"), session: session))
        #expect(queue.enqueue(.keys(["enter"]), session: session))

        firstGate.release(())
        try await waitUntil { queue.acknowledgedCount == 1 && queue.isDraining }
        await sender.setFailAfterGateWith(HerdrError.timeout(HerdrConnection.herdrDiagnosticLabel))
        secondGate.release(())
        try await waitUntil { queue.state == .needsResync }

        #expect(await sender.wire == ["text:a"])
        #expect(await sender.attemptCount == 2)
        #expect(queue.acknowledgedCount == 1)
        #expect(queue.pendingCount == 0)
    }

    @Test
    func liveCommandArgumentsEscapeShellMetacharactersUnicodeAndNewlines() {
        let pane = "w1:p1; rm -rf /"
        let text = "it's \"x\" $HOME `id`\n線"
        let textArgs = HerdrConnection.paneSendTextArguments(paneId: pane, text: text)
        let expectedTextArgs = "pane send-text \(HerdrConnection.shellSafeArgument(pane)) "
            + HerdrConnection.shellSafeArgument(text)
        #expect(textArgs == expectedTextArgs)
        #expect(!textArgs.contains("'"))
        #expect(!textArgs.contains(";"))
        #expect(!textArgs.contains("$HOME"))
        #expect(!textArgs.contains("`"))

        let keys = ["ctrl+c", "enter;evil", "線"]
        let keyArgs = HerdrConnection.paneSendKeysArguments(paneId: pane, keys: keys)
        let expectedKeyArgs = "pane send-keys \(HerdrConnection.shellSafeArgument(pane)) "
            + keys.map(HerdrConnection.shellSafeArgument).joined(separator: " ")
        #expect(keyArgs == expectedKeyArgs)
        #expect(!keyArgs.contains("'"))
        #expect(!keyArgs.contains(";"))
    }

    @Test
    @MainActor
    func fullQueueRefusesAdditionalEventsWithoutSilentDrop() async throws {
        let gate = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(firstSendGate: gate)
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 2)
        let session = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 1)
        )

        #expect(queue.enqueue(.text("a"), session: session))
        try await waitUntil { queue.isDraining && queue.pendingCount == 0 }
        #expect(queue.enqueue(.text("b"), session: session))
        #expect(queue.enqueue(.keys(["enter"]), session: session))
        #expect(!queue.enqueue(.text("c"), session: session))
        // Same-kind input still merges into the tail batch while full.
        #expect(queue.enqueue(.keys(["tab"]), session: session))
        #expect(queue.pendingCount == 2)

        gate.release(())
        try await waitUntilLiveIdle(queue)

        #expect(await sender.wire == ["text:a", "text:b", "keys:enter,tab"])
        #expect(queue.state == .ready)
    }

    @Test
    @MainActor
    func paneChangeDiscardsPendingWithoutDeliveryToNewPane() async throws {
        let gate = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(firstSendGate: gate)
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 8)
        let oldSession = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 1)
        )
        let newSession = PaneLiveInputSession(
            paneId: "w1:p2",
            generation: ConnectionGeneration(rawValue: 1)
        )

        #expect(queue.enqueue(.text("old"), session: oldSession))
        try await waitUntil { queue.isDraining && queue.pendingCount == 0 }
        #expect(queue.enqueue(.text("stale"), session: oldSession))
        queue.abandonQueuedInput()
        #expect(queue.pendingCount == 0)
        #expect(queue.enqueue(.text("new"), session: newSession))

        gate.release(())
        try await waitUntilLiveIdle(queue)

        let wire = await sender.wire
        #expect(wire == ["text:old", "text:new"])
        #expect(!wire.contains("text:stale"))
    }

    @Test
    @MainActor
    func generationMismatchStopsQueueAndDropsLaterEvents() async throws {
        let gate = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(firstSendGate: gate)
        await sender.setAcceptedGeneration(ConnectionGeneration(rawValue: 2))
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 8)
        let stale = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 1)
        )
        let newer = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 2)
        )

        #expect(queue.enqueue(.text("a"), session: stale))
        #expect(queue.enqueue(.text("b"), session: newer))

        gate.release(())
        try await waitUntil { queue.state == .needsResync }

        #expect(queue.state == .needsResync)
        #expect(queue.pendingCount == 0)
        #expect(!queue.enqueue(.text("c"), session: newer))
        let wire = await sender.wire
        #expect(wire.isEmpty)
        #expect(await sender.attemptCount == 1)
    }

    @Test
    @MainActor
    func ambiguousTimeoutNeedsResyncWithoutRetryingInFlight() async throws {
        let gate = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(firstSendGate: gate)
        await sender.setFailAfterGateWith(HerdrError.timeout(HerdrConnection.herdrDiagnosticLabel))
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 8)
        let session = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 4)
        )

        #expect(queue.enqueue(.text("maybe"), session: session))
        #expect(queue.enqueue(.text("later"), session: session))
        #expect(queue.enqueue(.keys(["enter"]), session: session))

        gate.release(())
        try await waitUntil { queue.state == .needsResync }

        #expect(queue.state == .needsResync)
        #expect(queue.pendingCount == 0)
        #expect(await sender.attemptCount == 1)
        #expect(await sender.wire.isEmpty)
        #expect(!queue.enqueue(.text("more"), session: session))

        queue.noteResynced()
        #expect(queue.state == .ready)
        let fresh = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 5)
        )
        await sender.setFailAfterGateWith(nil)
        #expect(queue.enqueue(.text("after"), session: fresh))
        try await waitUntilLiveIdle(queue)
        #expect(await sender.wire == ["text:after"])
        #expect(await sender.attemptCount == 2)
    }
}

actor RecordingLiveSender: PaneLiveInputSending {
    private(set) var wire: [String] = []
    private(set) var attemptCount = 0
    private var sendGates: [ExternallyReleasedWait<Void>]
    private var acceptedGeneration: ConnectionGeneration?
    private var failAfterGateWith: Error?

    init(
        firstSendGate: ExternallyReleasedWait<Void>? = nil,
        sendGates: [ExternallyReleasedWait<Void>] = []
    ) {
        if let firstSendGate, sendGates.isEmpty {
            self.sendGates = [firstSendGate]
        } else {
            self.sendGates = sendGates
        }
    }

    func setAcceptedGeneration(_ generation: ConnectionGeneration?) {
        acceptedGeneration = generation
    }

    func setFailAfterGateWith(_ error: Error?) {
        failAfterGateWith = error
    }

    func sendPaneLiveText(_ text: String, session: PaneLiveInputSession) async throws {
        try await beforeSend(session: session)
        wire.append("text:\(text)")
    }

    func sendPaneLiveKeys(_ keys: [String], session: PaneLiveInputSession) async throws {
        try await beforeSend(session: session)
        wire.append("keys:\(keys.joined(separator: ","))")
    }

    func beforeSend(session: PaneLiveInputSession) async throws {
        attemptCount += 1
        if !sendGates.isEmpty {
            let gate = sendGates.removeFirst()
            try await gate.wait()
        }
        if let acceptedGeneration, acceptedGeneration != session.generation {
            throw HerdrError.notConnected
        }
        if let failAfterGateWith {
            throw failAfterGateWith
        }
    }
}

@MainActor
func waitUntilLiveIdle(_ queue: PaneLiveInputQueue) async throws {
    try await waitUntil {
        queue.state == .ready && queue.pendingCount == 0 && !queue.isDraining
    }
}

@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ predicate: @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !predicate() {
        if ContinuousClock.now >= deadline {
            Issue.record("Timed out waiting for live-input condition")
            return
        }
        await Task.yield()
        try await Task.sleep(for: .milliseconds(5))
    }
}

@Suite("Pane key queue")
struct PaneKeyQueueTests {
    private let generation = ConnectionGeneration(rawValue: 4)
    private var oneShot: PaneLiveInputSession {
        PaneLiveInputSession(paneId: "w1:p1", generation: generation, kind: .oneShot)
    }

    @Test
    @MainActor
    func oneShotFailureKeepsKeysOffUntilResynced() async throws {
        let sender = RecordingLiveSender()
        await sender.setFailAfterGateWith(HerdrError.notConnected)
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 8)
        let token = oneShot

        #expect(queue.enqueue(.keys(["down"]), session: token))
        try await waitUntil { queue.state == .needsResync && !queue.isDraining }
        #expect(queue.lastFailure == .uncertain)
        #expect(queue.stopCount == 1)
        #expect(!queue.enqueue(.keys(["enter"]), session: token))
        let route = PaneKeyRoute.resolve(
            isOffline: false, isReadyForTerminalInput: true, hasGeneration: true,
            isSceneActive: true, isFocused: true, isRecording: false,
            queueState: queue.state, liveInputEnabled: false, hasFreshRead: true
        )
        #expect(route == .unavailable(.resyncing))

        // Only a fresh read brings keys back.
        queue.noteResynced()
        await sender.setFailAfterGateWith(nil)
        #expect(queue.enqueue(.keys(["enter"]), session: token))
        try await waitUntilLiveIdle(queue)
        #expect(await sender.wire == ["keys:enter"])
    }

    @Test
    @MainActor
    func burstAcrossLiveHandoverArrivesInTapOrder() async throws {
        let gate = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(firstSendGate: gate)
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 8)
        let token = oneShot
        let live = PaneLiveInputSession(paneId: "w1:p1", generation: generation)

        #expect(queue.enqueue(.keys(["down"]), session: token))
        try await waitUntil { queue.isDraining && queue.pendingCount == 0 }
        #expect(queue.enqueue(.keys(["down"]), session: token))
        #expect(queue.enqueue(.keys(["right"]), session: token))
        // Live starts here: its input queues behind the one-shot keys.
        #expect(queue.enqueue(.keys(["enter"]), session: live))
        #expect(queue.enqueue(.text("a"), session: live))
        gate.release(())
        try await waitUntilLiveIdle(queue)

        // Same-token taps merge; one-shot and Live batches never do.
        #expect(await sender.wire == ["keys:down", "keys:down,right", "keys:enter", "text:a"])
        #expect(queue.acknowledgedCount == 5)
    }

    @Test
    @MainActor
    func fullQueueStopsForResyncInsteadOfDiscarding() async throws {
        let gate = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(firstSendGate: gate)
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 1)
        let token = oneShot

        #expect(queue.enqueue(.keys(["down"]), session: token))
        try await waitUntil { queue.isDraining && queue.pendingCount == 0 }
        #expect(queue.enqueue(.keys(["enter"]), session: token))
        // A different kind can't merge, and the one queued slot is taken.
        #expect(!queue.enqueue(.text("x"), session: token))
        queue.stopForResync()
        #expect(queue.state == .needsResync)
        #expect(queue.pendingCount == 0)

        gate.release(())
        try await waitUntil { !queue.isDraining }
        #expect(await sender.wire == ["keys:down"])
        #expect(queue.state == .needsResync)
        #expect(!queue.enqueue(.keys(["enter"]), session: token))
    }

    @Test
    @MainActor
    func abandonWithAKeyInFlightKeepsKeysOffAfterReconnect() async throws {
        // The user taps a key, and the link drops while it is being sent. The
        // send then fails with nobody listening. After the reconnect, and even
        // after an ordinary poll read, keys stay off until the Live start-up's
        // fresh read clears the stop.
        let gate = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(firstSendGate: gate)
        await sender.setFailAfterGateWith(HerdrError.notConnected)
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 8)
        var reads = PaneFreshReadGate()
        let generation1 = ConnectionGeneration(rawValue: 1)
        let generation2 = ConnectionGeneration(rawValue: 2)
        reads.finishRead(reads.startRead(generation: generation1), outcome: .fresh)
        let token = PaneLiveInputSession(paneId: "w1:p1", generation: generation1, kind: .oneShot)

        #expect(queue.enqueue(.keys(["down"]), session: token))
        try await waitUntil { queue.isDraining && queue.pendingCount == 0 }
        queue.abandonAllInput()   // offline
        reads.inputStopped()
        gate.release(())
        try await waitUntil { !queue.isDraining }

        #expect(queue.state == .needsResync)
        #expect(!queue.enqueue(.keys(["enter"]), session: token))
        reads.finishRead(reads.startRead(generation: generation2), outcome: .fresh)   // a poll read after reconnect
        let afterReconnect = PaneKeyRoute.resolve(
            isOffline: false, isReadyForTerminalInput: true, hasGeneration: true,
            isSceneActive: true, isFocused: true, isRecording: false,
            queueState: queue.state, liveInputEnabled: false,
            hasFreshRead: reads.hasFreshRead(generation: generation2)
        )
        #expect(afterReconnect == .unavailable(.resyncing))

        #expect(queue.noteResynced(stopsBeforeRead: queue.stopCount))
        #expect(queue.state == .ready)
    }

    @Test
    @MainActor
    func abandonWhileIdleKeepsTheQueueReady() {
        let queue = PaneLiveInputQueue(sender: RecordingLiveSender())
        queue.abandonAllInput()
        #expect(queue.state == .ready)
        #expect(queue.stopCount == 0)
    }

    @Test
    @MainActor
    func aStopDuringTheReadKeepsTheQueueStopped() {
        let queue = PaneLiveInputQueue(sender: RecordingLiveSender())
        // Ready when the read starts, stopped before it ends.
        let readyAtStart = queue.stopCount
        queue.stopForResync()
        #expect(!queue.noteResynced(stopsBeforeRead: readyAtStart))
        #expect(queue.state == .needsResync)

        // Stopped when the read starts, stopped again before it ends.
        let stoppedAtStart = queue.stopCount
        queue.stopForResync()
        #expect(!queue.noteResynced(stopsBeforeRead: stoppedAtStart))
        #expect(queue.state == .needsResync)

        // No stop during the read: it clears the stop.
        #expect(queue.noteResynced(stopsBeforeRead: queue.stopCount))
        #expect(queue.state == .ready)
    }

    @Test
    @MainActor
    func stopForResyncWorksOnAnIdleQueue() {
        let queue = PaneLiveInputQueue(sender: RecordingLiveSender())
        queue.stopForResync()
        #expect(queue.state == .needsResync)
        #expect(queue.stopCount == 1)
        #expect(!queue.isDraining)
        #expect(!queue.enqueue(.keys(["esc"]), session: oneShot))
        queue.noteResynced()
        #expect(queue.state == .ready)
    }

    @Test
    @MainActor
    func coreRefusedBatchDropsTheRestWithoutResync() async throws {
        let gate = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(firstSendGate: gate)
        await sender.setFailAfterGateWith(CoreRPCError.remote(
            code: -32602, kind: "invalid_params", message: "unknown key \"plus\"", hint: nil
        ))
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 8)
        let token = oneShot
        let live = PaneLiveInputSession(paneId: "w1:p1", generation: generation)

        #expect(queue.enqueue(.keys(["ctrl+plus"]), session: token))
        try await waitUntil { queue.isDraining && queue.pendingCount == 0 }
        #expect(queue.enqueue(.keys(["enter"]), session: live))
        gate.release(())
        try await waitUntilLiveIdle(queue)

        // Core pressed nothing, so keys stay on, but nothing after it is sent.
        #expect(queue.state == .ready)
        #expect(queue.lastFailure == .coreRefusedKeys(["ctrl+plus"]))
        #expect(queue.failureCount == 1)
        #expect(queue.stopCount == 0)
        #expect(await sender.attemptCount == 1)
        #expect(await sender.wire.isEmpty)
        #expect(queue.acknowledgedCount == 0)

        await sender.setFailAfterGateWith(nil)
        #expect(queue.enqueue(.keys(["esc"]), session: live))
        try await waitUntilLiveIdle(queue)
        #expect(await sender.wire == ["keys:esc"])
    }

    @Test
    func staleGenerationRailKeysAreRefusedBeforeTheLane() async {
        let connection = HerdrConnection()
        for kind in [PaneLiveInputSession.Kind.oneShot, .live] {
            let session = PaneLiveInputSession(
                paneId: "w1:p1", generation: ConnectionGeneration(rawValue: 999), kind: kind
            )
            do {
                try await connection.sendPaneKeys(["esc"], session: session)
                Issue.record("A stale generation must not send keys")
            } catch {
                #expect(error as? HerdrError == .notConnected)
            }
            #expect(await connection.paneInput.isBusy("w1:p1") == false)
        }
    }
}
