import Foundation
import Observation

/// Committed Live keyboard / accessory events, in arrival order.
enum PaneLiveInputEvent: Sendable, Equatable {
    case text(String)
    case keys([String])

    /// False for empty text, no keys, or an empty key name. The queue never
    /// accepts these, so a refusal for this reason is not a full queue.
    var isDeliverable: Bool {
        switch self {
        case let .text(text):
            !text.isEmpty
        case let .keys(keys):
            !keys.isEmpty && keys.allSatisfy { !$0.isEmpty }
        }
    }
}

/// Generation-scoped token for pane input. Invalidate after pane switch,
/// disconnect, or SSH generation change; never reuse across panes.
struct PaneLiveInputSession: Sendable, Equatable {
    /// How the input is sent. A Live token goes through the Live session,
    /// and only while it is still the active one. A one-shot token carries
    /// rail keys while Live typing is not ready, each batch as its own
    /// `pane send-keys` (TUI) or `terminal.keys` (Herdr Core) request.
    /// The kind is part of equality, so the two never merge in the queue.
    enum Kind: Sendable, Equatable {
        case live
        case oneShot
    }

    let paneId: String
    let generation: ConnectionGeneration
    var kind: Kind = .live
    /// Distinguishes successive Live owners on the same connection and pane.
    let streamID: UUID = UUID()
}

/// Why a queued send failed, which decides whether keys must pause.
enum PaneLiveInputFailure: Equatable, Sendable {
    /// Herdr Core refused a key batch with `invalid_params` ("unknown key").
    /// Core checks the whole batch before pressing anything, so nothing
    /// reached the pane and no fresh read is needed.
    case coreRefusedKeys([String])
    /// Herdr Core refused a key batch with `invalid_params` for another
    /// reason. Nothing was pressed here either.
    case coreRefusedBatch
    /// Anything else. The input may or may not have arrived, so keys stay off
    /// until the pane has been read again.
    case uncertain

    static func classify(_ error: Error, event: PaneLiveInputEvent) -> Self {
        if case let .keys(keys) = event,
           case let .remote(_, kind, message, _)? = error as? CoreRPCError,
           kind == "invalid_params" {
            return message.contains("unknown key") ? .coreRefusedKeys(keys) : .coreRefusedBatch
        }
        return .uncertain
    }

    /// Core pressed nothing, so keys don't need to pause.
    var pressedNothing: Bool {
        switch self {
        case .coreRefusedKeys, .coreRefusedBatch: true
        case .uncertain: false
        }
    }
}

/// Observable delivery phase for Live input.
enum PaneLiveInputQueueState: Sendable, Equatable {
    case ready
    case sending
    case needsResync
}

/// SSH lane used by `PaneLiveInputQueue`. Production uses `PaneInputSender`.
protocol PaneLiveInputSending: Sendable {
    func sendPaneLiveText(_ text: String, session: PaneLiveInputSession) async throws
    func sendPaneLiveKeys(_ keys: [String], session: PaneLiveInputSession) async throws
}

/// The pane's one input queue sender. Typed text needs the Live session.
/// Rail keys follow their token: Live keys through the Live session while it
/// is active, one-shot keys as a plain key command (`sendPaneKeys`).
struct PaneInputSender: PaneLiveInputSending {
    let connection: HerdrConnection

    func sendPaneLiveText(_ text: String, session: PaneLiveInputSession) async throws {
        try await connection.sendPaneLiveText(text, session: session)
    }

    func sendPaneLiveKeys(_ keys: [String], session: PaneLiveInputSession) async throws {
        try await connection.sendPaneKeys(keys, session: session)
    }
}

/// Main-actor bounded FIFO for Live events. Enqueue is synchronous so separate
/// `Task`s cannot reorder keystrokes before they enter the queue. One drain
/// loop sends through `PaneLiveInputSending` (which must use
/// `PaneInputCoordinator`). Ambiguous failures stop the queue; uncertain
/// events are never retried. A Herdr Core refusal of key names stops nothing,
/// because Core pressed none of them, but the rest of the queue is dropped.
/// All input for a pane, Live or one-shot, shares one queue, so it arrives
/// in the order it was tapped.
///
/// Nagle-style coalescing: while a send is in flight, a new event merges into
/// the last queued (not yet sent) batch when both are text, or both are keys,
/// for the same session. The first event after idle still goes out at once;
/// on a slow link a typing burst costs one round trip instead of one per key.
/// Text and keys never merge across each other, so wire order is preserved.
@MainActor
@Observable
final class PaneLiveInputQueue {
    /// Maximum queued sends (coalesced batches), not individual keystrokes.
    nonisolated static let maxPendingEvents = 32

    private(set) var state: PaneLiveInputQueueState = .ready
    /// Number of queued sends (coalesced batches), excluding the in-flight one.
    private(set) var pendingCount = 0
    /// True while a drain task owns the send loop (including in-flight SSH).
    private(set) var isDraining = false
    /// Monotonic count of successfully delivered Live events. Increments by the
    /// number of events in each acknowledged send, before the next queued send
    /// starts. Failures and abandoned events do not increment.
    private(set) var acknowledgedCount: UInt64 = 0
    /// The most recent send failure, and how many sends have failed so far.
    /// Watch the count: it changes on every failure, even a repeat of the
    /// same kind.
    private(set) var lastFailure: PaneLiveInputFailure?
    private(set) var failureCount: UInt64 = 0
    /// Counts every stop for resync. A read that started before the latest
    /// stop can't clear it, because it may not show that input's effect.
    private(set) var stopCount: UInt64 = 0

    private let sender: any PaneLiveInputSending
    private let maxPending: Int
    private var pending: [Queued] = []
    private var drainTask: Task<Void, Never>?
    private var epoch: UInt64 = 0

    private struct Queued {
        var event: PaneLiveInputEvent
        let session: PaneLiveInputSession
        /// Accepted events merged into this send.
        var eventCount = 1

        /// Folds `next` into this batch when both are the same kind for the
        /// same session. Returns false, leaving the batch unchanged, otherwise.
        mutating func coalesce(_ next: PaneLiveInputEvent, session nextSession: PaneLiveInputSession) -> Bool {
            guard session == nextSession else { return false }
            switch (event, next) {
            case let (.text(queued), .text(added)):
                event = .text(queued + added)
            case let (.keys(queued), .keys(added)):
                event = .keys(queued + added)
            default:
                return false
            }
            eventCount += 1
            return true
        }
    }

    init(sender: any PaneLiveInputSending, maxPending: Int = maxPendingEvents) {
        self.sender = sender
        self.maxPending = max(1, maxPending)
    }

    /// Appends an event synchronously, merging it into the last queued batch
    /// when possible. Returns `false` when the queue is full, stopped for
    /// resync, or the event is empty — never silently drops an accepted event.
    @discardableResult
    func enqueue(_ event: PaneLiveInputEvent, session: PaneLiveInputSession) -> Bool {
        guard state != .needsResync else { return false }
        guard event.isDeliverable else { return false }

        if let last = pending.indices.last, pending[last].coalesce(event, session: session) {
            // Merged into a queued batch; the drain loop is already scheduled.
            return true
        }
        guard pending.count < maxPending else { return false }
        pending.append(Queued(event: event, session: session))
        pendingCount = pending.count
        if state == .ready {
            state = .sending
        }
        startDrainIfNeeded()
        return true
    }

    /// Drops queued (not yet acknowledged) events on pane switch or disconnect.
    /// An in-flight send is not retried; remaining events never reach a new pane.
    func abandonQueuedInput() {
        epoch &+= 1
        pending.removeAll(keepingCapacity: false)
        pendingCount = 0
        if state != .needsResync {
            state = isDraining ? .sending : .ready
        }
    }

    /// Stops all input until the pane has been read again: drops anything
    /// queued and refuses new input until `noteResynced()`. Works in any
    /// state, including a queue that has never sent anything. An in-flight
    /// send is not retried and is not acknowledged.
    func stopForResync() {
        epoch &+= 1
        pending.removeAll(keepingCapacity: false)
        pendingCount = 0
        state = .needsResync
        stopCount &+= 1
    }

    /// Drops all input when the pane stops taking it: offline, background,
    /// focus moving to the other pane, or leaving the pane. If a send is still
    /// on its way, nobody will hear how it ended, so the queue stops for a
    /// fresh read instead of becoming ready again.
    func abandonAllInput() {
        if isDraining {
            stopForResync()
        } else {
            abandonQueuedInput()
        }
    }

    /// Clears a stop after a successful fresh read, unless the queue stopped
    /// again after that read started (`stopsBeforeRead` is `stopCount` taken
    /// just before it): such a read may not show that input's effect, so the
    /// queue stays stopped and this returns false.
    @discardableResult
    func noteResynced(stopsBeforeRead: UInt64) -> Bool {
        guard stopCount == stopsBeforeRead else { return false }
        noteResynced()
        return true
    }

    /// Call after a fresh pane read and `beginPaneLiveInput` token.
    func noteResynced() {
        guard state == .needsResync else { return }
        epoch &+= 1
        pending.removeAll(keepingCapacity: false)
        pendingCount = 0
        state = isDraining ? .sending : .ready
    }

    private func startDrainIfNeeded() {
        guard drainTask == nil else { return }
        isDraining = true
        let myEpoch = epoch
        drainTask = Task { @MainActor in
            await self.runDrain(epoch: myEpoch)
        }
    }

    private func runDrain(epoch myEpoch: UInt64) async {
        defer {
            if self.epoch == myEpoch {
                self.drainTask = nil
                self.isDraining = false
                if self.state == .sending && self.pending.isEmpty {
                    self.state = .ready
                }
            } else {
                self.drainTask = nil
                self.isDraining = false
                if self.state != .needsResync {
                    if self.pending.isEmpty {
                        self.state = .ready
                    } else {
                        self.state = .sending
                        self.startDrainIfNeeded()
                    }
                }
            }
        }

        while epoch == myEpoch {
            guard let next = pending.first else { break }
            pending.removeFirst()
            pendingCount = pending.count

            do {
                switch next.event {
                case let .text(text):
                    try await sender.sendPaneLiveText(text, session: next.session)
                case let .keys(keys):
                    try await sender.sendPaneLiveKeys(keys, session: next.session)
                }
            } catch {
                guard epoch == myEpoch else { return }
                // Never retry, and discard the rest: later input was typed
                // for a screen the failed batch may not have produced.
                let failure = PaneLiveInputFailure.classify(error, event: next.event)
                pending.removeAll(keepingCapacity: false)
                pendingCount = 0
                lastFailure = failure
                failureCount &+= 1
                // A Core refusal pressed nothing, so the screen is as it was:
                // keep accepting input, and the defer settles the state to ready.
                if !failure.pressedNothing {
                    state = .needsResync
                    stopCount &+= 1
                }
                return
            }

            guard epoch == myEpoch else { return }
            // Ack every event in the batch before starting the next queued send.
            acknowledgedCount &+= UInt64(next.eventCount)
        }
    }
}
