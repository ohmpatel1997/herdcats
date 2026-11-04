import Foundation

/// Where a tap on the pane's key row goes right now.
///
/// Keys work once the connection is ready and the pane has been read since
/// input last stopped, not only once Live typing has started: until then each
/// batch is sent as its own key command. After any send that may not have
/// arrived, every key stays off until the pane has been read again, so a later
/// key can never act on a screen the user hasn't seen.
enum PaneKeyRoute: Equatable {
    /// Through the active Live session.
    case live
    /// As a plain key command, while Live typing is not ready.
    case oneShot
    /// Keys are off.
    case unavailable(Reason)

    enum Reason: Equatable {
        case offline
        case connecting
        case recording
        /// A send may not have arrived. Keys come back after a fresh read.
        case resyncing
        /// The pane hasn't been read since it opened or since input last
        /// stopped (offline, background, focus moving away), so the screen may
        /// be old. Keys come back after the next successful read.
        case reading
    }

    var sendsKeys: Bool {
        switch self {
        case .live, .oneShot: true
        case .unavailable: false
        }
    }

    static func resolve(
        isOffline: Bool,
        isReadyForTerminalInput: Bool,
        hasGeneration: Bool,
        isSceneActive: Bool,
        isFocused: Bool,
        isRecording: Bool,
        queueState: PaneLiveInputQueueState?,
        liveInputEnabled: Bool,
        hasFreshRead: Bool
    ) -> PaneKeyRoute {
        if isOffline { return .unavailable(.offline) }
        if isRecording { return .unavailable(.recording) }
        // A Live session already proved the connection and its generation,
        // and is installed only after a fresh read.
        if liveInputEnabled && queueState != .needsResync { return .live }
        if !isReadyForTerminalInput || !hasGeneration { return .unavailable(.connecting) }
        // The dock is hidden in both cases, so this text never shows.
        if !isSceneActive || !isFocused { return .unavailable(.connecting) }
        if queueState == .needsResync { return .unavailable(.resyncing) }
        if !hasFreshRead { return .unavailable(.reading) }
        return .oneShot
    }

    /// Rail keys may come from the Live toolbar or from above Compose. Typed
    /// text comes only from the Live keyboard. Nothing comes from recording.
    static func accepts(_ event: PaneLiveInputEvent, surface: PaneInputSurfaceModel.Surface) -> Bool {
        switch (event, surface) {
        case (_, .liveToolbar): true
        case (.keys, .composeDraft): true
        case (.text, .composeDraft): false
        case (_, .voiceRecording): false
        }
    }
}

/// The one line of text above the key row: why keys are off, or the last
/// key or send problem.
struct PaneKeyNotice: Equatable {
    let text: String
    let offersRetry: Bool

    static let connecting = "Connecting. Keys work once the connection is ready."
    static let checkingScreen = "Checking the screen. Keys come back once it’s read."
    static let readFailed = "Couldn’t read the pane, so keys stay paused. Trying again."
    static let mayNotHaveArrived = "That key may not have reached the pane."
    static let tooManyKeys = "Too many keys at once. Some may not have reached the pane."

    static let coreRefusedBatch = "Herdr Core refused those keys, so they and any after them weren’t sent."

    static func coreRefusal(_ keys: [String]) -> String {
        if keys.count == 1, let key = keys.first {
            return "Herdr Core doesn’t accept “\(key)”. That key and any after it weren’t sent."
        }
        return "Herdr Core doesn’t accept one of “\(keys.joined(separator: " "))”. "
            + "Those keys and any after them weren’t sent."
    }

    /// The real reason wins: a pause reason or a transient key notice first,
    /// then the route's own text, then the existing `sessionError`. Nil in the
    /// Timeline, which draws `sessionError` itself, and while offline or
    /// recording, where other UI already explains. Waiting for the first read
    /// is silent unless a read fails, so opening a pane doesn't flash text.
    static func resolve(
        route: PaneKeyRoute,
        pauseReason: String?,
        transient: String?,
        sessionError: String?,
        resyncReadFailures: Int,
        backoffAtCap: Bool,
        showsTimeline: Bool
    ) -> PaneKeyNotice? {
        guard !showsTimeline else { return nil }
        switch route {
        case .unavailable(.offline), .unavailable(.recording):
            return nil
        case .unavailable(.connecting):
            return PaneKeyNotice(text: connecting, offersRetry: false)
        case .unavailable(.resyncing):
            if resyncReadFailures > 0 {
                return PaneKeyNotice(text: readFailed, offersRetry: backoffAtCap)
            }
            let text = [pauseReason, checkingScreen].compactMap { $0 }.joined(separator: " ")
            return PaneKeyNotice(text: text, offersRetry: false)
        case .unavailable(.reading):
            guard resyncReadFailures > 0 else { return nil }
            return PaneKeyNotice(text: readFailed, offersRetry: backoffAtCap)
        case .live, .oneShot:
            guard let text = transient ?? sessionError else { return nil }
            return PaneKeyNotice(text: text, offersRetry: false)
        }
    }
}

/// Tracks whether the pane has been read since input last stopped. One-shot
/// keys wait for such a read, so a key never acts on a screen that may be
/// minutes or hours old: after opening the pane, a reconnect, or a return
/// from the background. A Live session needs no check, because it is
/// installed only after its own fresh read.
struct PaneFreshReadGate: Equatable {
    /// Where a read started: the input epoch and connection generation then.
    struct ReadStart: Equatable {
        let epoch: Int
        let generation: ConnectionGeneration?
    }

    private(set) var inputEpoch = 0
    private var freshEpoch: Int?
    private var freshGeneration: ConnectionGeneration?

    /// Input stopped (offline, background, focus moving away, pane change).
    /// Reads that started before this no longer count.
    mutating func inputStopped() {
        inputEpoch += 1
    }

    func startRead(generation: ConnectionGeneration?) -> ReadStart {
        ReadStart(epoch: inputEpoch, generation: generation)
    }

    /// Records a read that landed. Ignores one that was overtaken or failed,
    /// started before input last stopped, or had no connection generation.
    mutating func finishRead(_ start: ReadStart, outcome: PaneReadOutcome) {
        guard outcome == .fresh, start.epoch == inputEpoch, let generation = start.generation else { return }
        freshEpoch = start.epoch
        freshGeneration = generation
    }

    /// True after a read on this connection generation since input last stopped.
    func hasFreshRead(generation: ConnectionGeneration?) -> Bool {
        guard let generation else { return false }
        return freshEpoch == inputEpoch && freshGeneration == generation
    }
}

/// Compose Send doesn't go through the key queue; it takes the pane's input
/// lane directly. So it waits while keys are queued or being sent, which
/// keeps it from overtaking keys tapped earlier, and while keys are paused
/// for a fresh read, so a message never goes to a screen nobody has re-read.
enum PaneComposeGate {
    static func allowsSend(queueState: PaneLiveInputQueueState?, isDraining: Bool) -> Bool {
        guard let queueState else { return true }
        return queueState == .ready && !isDraining
    }
}
