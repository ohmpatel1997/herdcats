import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable, Sendable {
        case disconnected
        case connecting
        case connected(host: String, username: String)
        case offline(host: String, username: String)
    }

    var phase: Phase = .disconnected
    var hasActiveSession: Bool
    var activeConfig: ConnectionConfig?
    /// Runtimes the Auto probe found on the last connect; empty when it did not run.
    var detectedBackends: Set<ConnectionBackend> = []
    var isCoreMode: Bool { activeConfig?.backend == .core }
    var isReadyForTerminalInput: Bool {
        if case .connected = phase { return true }
        return false
    }
    var runtimeRevision: UInt64 = 0
    var runtimeRefreshTask: Task<Void, Never>?

    func noteRuntimeChange(generation: ConnectionGeneration) {
        guard ownership.transportGeneration == generation, runtimeRefreshTask == nil else { return }
        runtimeRefreshTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self else { return }
            self.runtimeRefreshTask = nil
            guard self.ownership.transportGeneration == generation else { return }
            self.runtimeRevision &+= 1
        }
    }
    var connectionBanner: ConnectionBanner?
    var lastConnectPassphraseRejected = false
    var lastConnectNeedsSignIn = false
    var lastError: String?
    var connectionProgressMessage = "Connecting…"
    var herdrMissingOnLastConnect = false
    /// The connection's saved runtime isn't on the machine, but the other one is.
    struct RuntimeMismatch: Equatable {
        let saved: ConnectionBackend
        let installed: ConnectionBackend
    }
    /// Set with `herdrMissingOnLastConnect` when the machine has the other runtime.
    var runtimeMismatchOnLastConnect: RuntimeMismatch?
    var herdrSessionUnavailableOnLastConnect = false
    var herdrVersion: String?
    var connectionIdentity: ConnectionIdentity?
    var hostKeyChallenge: SSHHostKeyChallenge?
    var hostKeyVerificationBlocked = false
    var isSceneActive = true

    /// Production ownership primitive — unit tests exercise this same type.
    var ownership = ConnectionSessionOwnership()

    let phoneAnswers = PhoneAnswersStore()
    let connection: HerdrConnection
    var dismissBannerTask: Task<Void, Never>?
    var autoReconnectTask: Task<Void, Never>?
    var isDialing = false

    var machineDisplayName: String {
        if case let .connected(host, _) = phase { return host }
        if case let .offline(host, _) = phase { return host }
        return "Remote Machine"
    }

    init(
        connection: HerdrConnection = HerdrConnection(),
        autoConnectOnLaunch: Bool = true
    ) {
        self.connection = connection
        if autoConnectOnLaunch,
           let autoConfig = AutoConnect.configIfRequested() ?? LaunchPreference.autoConnectConfig() {
            self.hasActiveSession = true
            self.activeConfig = autoConfig
            self.phase = .disconnected
            self.connectionBanner = .connecting(message: "Connecting…")
        } else {
            self.hasActiveSession = false
            self.phase = .disconnected
        }
    }

    /// Test seam: overrides the 30s connect watchdog sleep.
    var connectWatchdogNanoseconds: UInt64 = 30_000_000_000

    var isConnecting: Bool {
        if case .connecting = phase { return true }
        return false
    }

    var isOffline: Bool {
        if case .offline = phase { return true }
        return false
    }

    func showBackOnline(message: String = "Back online") {
        dismissBannerTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) {
            connectionBanner = .backOnline(message: message)
        }
        dismissBannerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                self?.connectionBanner = nil
            }
        }
    }

    func scheduleAutoReconnect(delaySeconds: Double = 2.5) {
        guard !hostKeyVerificationBlocked else { return }
        autoReconnectTask?.cancel()
        guard hasActiveSession, activeConfig != nil else { return }
        autoReconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled, let self else { return }
            guard self.isOffline, self.hasActiveSession else { return }
            // The reconnect task is handing control to reconnect(). Clear its
            // slot first so reconnect() does not cancel the task that is now
            // performing the SSH attempt.
            self.autoReconnectTask = nil
            await self.reconnect(automatically: true)
        }
    }

    func cancelReconnect() {
        autoReconnectTask?.cancel()
        autoReconnectTask = nil
    }

    func reconnect(automatically: Bool = false) async {
        guard !automatically || !hostKeyVerificationBlocked else { return }
        guard let config = activeConfig else { return }
        guard !isDialing else { return }
        cancelReconnect()
        #if DEBUG
        print("[HC] reconnecting to \(config.host):\(config.port)")
        #endif
        connectionBanner = .connecting(message: "Reconnecting…")
        await connect(config: config)
    }
}
