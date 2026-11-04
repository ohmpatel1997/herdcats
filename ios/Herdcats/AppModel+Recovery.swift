import Observation
import SwiftUI

extension AppModel {
    func prepareConnectionStatus(for config: ConnectionConfig) {
        lastError = nil
        connectionProgressMessage = "Signing in over SSH…"
        herdrMissingOnLastConnect = false
        runtimeMismatchOnLastConnect = nil
        herdrSessionUnavailableOnLastConnect = false
        connectionIdentity = ConnectionIdentity(config)
    }

    /// Whether the last connect attempt was for `entry`'s machine and runtime.
    func lastConnectWasFor(_ entry: RecentConnection) -> Bool {
        guard let activeConfig else { return false }
        let shown = ConnectionIdentity(host: entry.host, port: entry.port, username: entry.username, backend: entry.backend)
        // The stored form ignores the case of the host name.
        return ConnectionIdentity(activeConfig).storageKey == shown.storageKey
    }

    /// Shows `message` as a plain error in place of a Herdr recovery card.
    func showPlainError(_ message: String) {
        herdrMissingOnLastConnect = false
        runtimeMismatchOnLastConnect = nil
        herdrSessionUnavailableOnLastConnect = false
        lastError = message
    }

    func checkSessionReadiness() async throws {
        // --version confirms the binary only; a space query confirms the
        // default session is ready for the screens we present next.
        do {
            _ = try await connection.workspaceList(timeoutPolicy: .teardownSilently)
        } catch {
            throw Self.sessionReadinessError(error)
        }
    }

    static func sessionReadinessError(_ error: Error) -> Error {
        guard let herdrError = error as? HerdrError else { return error }
        switch herdrError {
        case let .api(code, message):
            let missingSessionPhrases = [
                "no default session", "default session not found", "default session is missing",
                "default session is unavailable", "default session does not exist"
            ]
            if code == "session_unavailable"
                || missingSessionPhrases.contains(where: { message.localizedCaseInsensitiveContains($0) }) {
                return HerdrError.sessionUnavailable
            }
            return error
        default:
            return error
        }
    }

    /// Approval only persists the exact displayed key; the next handshake verifies it again.
    func approveHostKey(_ challenge: SSHHostKeyChallenge, store: SSHHostKeyStore = .shared) async -> Bool {
        guard hostKeyChallenge == challenge, !isDialing else { return false }
        do {
            if let previousKey = challenge.previousPublicKey {
                try await store.replace(challenge.publicKey, replacing: previousKey,
                                        host: challenge.host, port: challenge.port)
            } else {
                try await store.trust(challenge.publicKey, host: challenge.host, port: challenge.port)
            }
            guard hostKeyChallenge == challenge else { return false }
            hostKeyChallenge = nil
            hostKeyVerificationBlocked = false
            lastError = nil
            return true
        } catch {
            lastError = HerdrConnection.friendlyMessage(for: error)
            return false
        }
    }

    func cancelHostKeyApproval() {
        hostKeyChallenge = nil
        cancelReconnect()
    }

    func disconnect() async {
        cancelReconnect()
        dismissBannerTask?.cancel()
        connectionBanner = nil
        hasActiveSession = false
        activeConfig = nil
        hostKeyChallenge = nil
        hostKeyVerificationBlocked = false
        let generation = ownership.disconnect()
        phase = .disconnected
        herdrVersion = nil
        connectionIdentity = nil
        if let generation {
            connection.forceClose(generation: generation)
        }
        // If somehow no generation was reserved, invalidate whatever is current
        // via a fresh reserve-and-close would be wrong; leave transport alone.
    }

    /// Returns the user to the connection screen if a remembered credential
    /// could not be persisted after authentication succeeded.
    func reportCredentialStorageError(_ message: String) async {
        await disconnect()
        lastError = message
    }

    func handleConnectWatchdog(attempt: UInt64) {
        guard case .connecting = phase else { return }
        switch ownership.watchdogTimeout(for: attempt) {
        case .stale:
            return
        case let .timedOut(generation):
            lastError = "The connection attempt timed out."
            connection.forceClose(generation: generation)
            connectionIdentity = nil
            if hasActiveSession, let config = activeConfig {
                phase = .offline(host: config.host, username: config.username)
                connectionBanner = .offline(message: "Offline · Connection timed out", canRetry: true)
                scheduleAutoReconnect(delaySeconds: 5.0)
            } else {
                phase = .disconnected
            }
        }
    }

    func handleConnectionLost(generation: ConnectionGeneration) {
        // Invalidates the app attempt so delayed serverVersion cannot promote.
        guard ownership.handleLoss(generation: generation) else { return }
        switch phase {
        case let .connected(host, username):
            phase = .offline(host: host, username: username)
            connectionBanner = .offline(message: "Offline · Connection lost", canRetry: true)
            scheduleAutoReconnect()
        case .connecting:
            if hasActiveSession, let config = activeConfig {
                phase = .offline(host: config.host, username: config.username)
                connectionBanner = .offline(message: "Offline · Connection lost", canRetry: true)
                scheduleAutoReconnect()
            } else {
                connectionIdentity = nil
                phase = .disconnected
                lastError = "The connection was lost during handshake."
            }
        case .offline:
            scheduleAutoReconnect()
        case .disconnected:
            break
        }
    }
}
