import Foundation
import Security
import NIOSSH
import SwiftUI
import Testing
@testable import Herdcats

@Suite("Saved machine order and names")
struct SavedMachineOrderTests {
    private func machine(_ host: String) -> RecentConnection {
        RecentConnection(host: host, port: 22, username: "u", authMode: "password", remember: true)
    }

    private func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
        let suite = "SavedMachineOrderTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try test(defaults)
    }

    @Test func recordKeepsPositionAndStampsLastConnected() throws {
        try withDefaults { defaults in
            let entries = [machine("a"), machine("b"), machine("c")]
            let now = Date(timeIntervalSince1970: 1234)
            let updated = try RecentConnectionStore.record(entries[1], in: entries, defaults: defaults, now: now)
            #expect(updated.map(\.id) == entries.map(\.id))
            #expect(updated[1].lastConnectedAt == now)
            #expect(try RecentConnectionStore.load(defaults: defaults, using: FakeKeychainOperations()) == updated)
        }
    }

    @Test func recordAppendsNewMachine() throws {
        try withDefaults { defaults in
            let entries = [machine("a"), machine("b"), machine("c")]
            let added = machine("d")
            let updated = try RecentConnectionStore.record(added, in: entries, defaults: defaults)
            #expect(updated.map(\.id) == (entries + [added]).map(\.id))
        }
    }

    @Test func movePersistsOrder() throws {
        try withDefaults { defaults in
            var entries = [machine("a"), machine("b"), machine("c")]
            entries[0].lastConnectedAt = Date(timeIntervalSince1970: 100)
            defaults.set(try JSONEncoder().encode(entries), forKey: RecentConnectionStore.storageKey)
            defaults.set(LaunchPreference.autoConnect.rawValue, forKey: LaunchPreference.storageKey)
            let keychain = FakeKeychainOperations()
            for entry in entries { keychain.items[entry.secretAccount] = Data("pw".utf8) }
            let moved = try RecentConnectionStore.move(fromOffsets: IndexSet(integer: 2), toOffset: 0,
                defaults: defaults, using: keychain)
            #expect(moved == [entries[2], entries[0], entries[1]])
            #expect(try RecentConnectionStore.load(defaults: defaults, using: keychain) == moved)
            #expect(LaunchPreference.autoConnectConfig(defaults: defaults, keychain: keychain)?.host == "a")
        }
    }

    @Test func autoConnectUsesLastUsedNotFirst() throws {
        try withDefaults { (defaults: UserDefaults) throws in
            var a = machine("a")
            var b = machine("b")
            a.lastConnectedAt = Date(timeIntervalSince1970: 1)
            b.lastConnectedAt = Date(timeIntervalSince1970: 2)
            defaults.set(LaunchPreference.autoConnect.rawValue, forKey: LaunchPreference.storageKey)
            let keychain = FakeKeychainOperations()
            for entry in [a, b] { keychain.items[entry.secretAccount] = Data("pw".utf8) }
            func selected(_ entries: [RecentConnection]) throws -> String? {
                defaults.set(try JSONEncoder().encode(entries), forKey: RecentConnectionStore.storageKey)
                return LaunchPreference.autoConnectConfig(defaults: defaults, keychain: keychain)?.host
            }
            #expect(try selected([a, b]) == "b")
            a.lastConnectedAt = nil
            #expect(try selected([a, b]) == "b")
            a.lastConnectedAt = b.lastConnectedAt
            #expect(try selected([a, b]) == "a")
            a.lastConnectedAt = nil
            b.lastConnectedAt = nil
            #expect(try selected([b, a]) == "b")
            b.remember = false
            b.lastConnectedAt = Date(timeIntervalSince1970: 3)
            #expect(try selected([b, a]) == "a")
        }
    }

    @Test func decodesLegacyRecentConnectionWithoutNewFields() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","host":"h","port":22,"username":"u","authMode":"password","remember":true}
        """
        let entry = try JSONDecoder().decode(RecentConnection.self, from: Data(json.utf8))
        #expect(entry.name == nil)
        #expect(entry.lastConnectedAt == nil)
    }

    @Test func displayNamePrefersNameThenUserHostPort() {
        var entry = machine("h")
        entry.name = "  "
        #expect(entry.displayName == "u@h")
        entry.port = 2222
        #expect(entry.displayName == "u@h:2222")
        entry.name = "  Studio \n"
        #expect(entry.displayName == "Studio")
    }

    @Test func shortDisplayNameAbbreviatesDNSHostsOnly() {
        var entry = machine("kennybots-mac-mini.tail5b5906.ts.net")
        #expect(entry.shortDisplayName(among: [entry]) == "kennybots-mac-mini")
        entry.port = 2222
        #expect(entry.shortDisplayName(among: [entry]) == "kennybots-mac-mini:2222")
        #expect(machine("149.248.202.63").shortDisplayName(among: []) == "149.248.202.63")
        #expect(machine("fe80::1").shortDisplayName(among: []) == "fe80::1")
        entry.name = "Mini"
        #expect(entry.shortDisplayName(among: [entry]) == "Mini")
    }

    @Test func shortDisplayNameAddsUserWhenSameHostHasTwoLogins() {
        let kenny = machine("studio.local")
        var admin = machine("studio.local")
        admin.username = "admin"
        let all = [kenny, admin, machine("mini.local")]
        #expect(kenny.shortDisplayName(among: all) == "u@studio")
        #expect(admin.shortDisplayName(among: all) == "admin@studio")
        #expect(all[2].shortDisplayName(among: all) == "mini")
    }

    @Test func shortDisplayNameKeepsFullHostWhenAbbreviationsCollide() {
        let tailnet = machine("mini.tail5b5906.ts.net")
        let local = machine("mini.local")
        let other = machine("studio.local")
        let all = [tailnet, local, other]
        #expect(tailnet.shortDisplayName(among: all) == "mini.tail5b5906.ts.net")
        #expect(local.shortDisplayName(among: all) == "mini.local")
        #expect(other.shortDisplayName(among: all) == "studio")
    }

    @Test func entryPreservesOrUpdatesName() {
        var saved = machine("h")
        saved.name = "Studio"
        let unchanged = RecentConnectionStore.entry(host: "h", port: 22, username: "u",
            authMode: "password", remember: true, in: [saved])
        #expect(unchanged.name == "Studio")
        let cleared = RecentConnectionStore.entry(host: "h", port: 22, username: "u",
            authMode: "password", remember: true, name: "", in: [saved])
        #expect(cleared.displayName == "u@h")
        #expect(cleared.id == saved.id)
    }
}

@Suite("Saved connection configuration")
struct SavedConnectionConfigTests {
    @Test func savedConnectionConfigUsesRememberedPassword() throws {
        let entry = RecentConnection(host: "saved.example", port: 2222, username: "tester",
            authMode: "password", remember: true)
        let keychain = FakeKeychainOperations()
        keychain.items[entry.secretAccount] = Data("pw".utf8)
        let config = try #require(RecentConnectionStore.config(for: entry, using: keychain))
        #expect(config.host == entry.host)
        #expect(config.port == entry.port)
        #expect(config.username == entry.username)
        guard case let .password(password) = config.auth else {
            Issue.record("Expected password authentication")
            return
        }
        #expect(password == "pw")
    }

    @Test func savedConnectionConfigIsNilWithoutRememberedSecret() {
        var entry = RecentConnection(host: "saved.example", port: 22, username: "tester",
            authMode: "password", remember: false)
        let keychain = FakeKeychainOperations()
        keychain.items[entry.secretAccount] = Data("pw".utf8)
        #expect(RecentConnectionStore.config(for: entry, using: keychain) == nil)
        entry.remember = true
        keychain.items.removeValue(forKey: entry.secretAccount)
        #expect(RecentConnectionStore.config(for: entry, using: keychain) == nil)
        keychain.items[entry.secretAccount] = Data(" \n\t".utf8)
        #expect(RecentConnectionStore.config(for: entry, using: keychain) == nil)
    }

    @Test func savedConnectionConfigIsNilForEncryptedKeyWithoutPassphrase() throws {
        let pem = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABBQsNNQDE
        3OeNlbiirYuF51AAAAQAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIEHiHx4Brcpqh9OW
        lY7YKkM3HN1yOFbJNYbUClrT7q+MAAAAoPXvIQDoTJK/XrKBIF2kuCD9KIPYTstdeLIEcI
        heoaAWhTJoeN0uixLdLK2E0qnaOA4teelJmrqntGC3kaWAOknVv7UPGceybXd82nYykl/s
        xiPxdhHmIcm/mO6Bw1Cve9cJZF6k2sd0EBzfwnaFImLcSF3oL/T6Cf/JS6vTFOWHjh+anc
        1Jzhj402WYisxnyveuTPZGidiF24UyVUEMyEs=
        -----END OPENSSH PRIVATE KEY-----
        """
        #expect(try OpenSSHEd25519.isEncrypted(pem: pem))
        let entry = RecentConnection(host: "saved.example", port: 22, username: "tester",
            authMode: "privateKey", remember: true)
        let keychain = FakeKeychainOperations()
        keychain.items[entry.secretAccount] = Data(pem.utf8)
        #expect(RecentConnectionStore.config(for: entry, using: keychain) == nil)
    }
}

@Suite("Onboarding entry")
struct OnboardingEntryTests {
    @Test func firstUseAndReturnRoutes() {
        #expect(OnboardingRoute.initial(hasSeenIntro: false, hasSavedMachines: false) == .intro)
        #expect(OnboardingRoute.initial(hasSeenIntro: true, hasSavedMachines: false) == .connectionSelection)
        #expect(OnboardingRoute.initial(hasSeenIntro: false, hasSavedMachines: true) == .connectionSelection)
        #expect(OnboardingRoute.initial(hasSeenIntro: true, hasSavedMachines: true) == .connectionSelection)
        #expect(OnboardingRoute.initial(hasSeenIntro: true, hasSavedMachines: true, replay: true) == .intro)
    }
}

@Suite("Auto-connect launch and offline status bar")
struct AutoConnectAndOfflineStatusBarTests {
    @MainActor
    @Test func transientReadinessTimeoutOnOfflineReconnectKeepsRetrying() async {
        for timeout in [HerdrError.timeout("herdr --version"), HerdrError.timeout("workspace list")] {
            let config = ConnectionConfig(
                host: "offline.example", port: 22, username: "tester", auth: .password("fixture")
            )
            let model = AppModel(autoConnectOnLaunch: false)
            model.hasActiveSession = true
            model.phase = .offline(host: config.host, username: config.username)
            guard let state = await model.prepareConnectAttempt(config: config) else {
                Issue.record("Could not prepare offline reconnect")
                return
            }
            state.watchdog.cancel()
            #expect(state.wasOffline)
            model.handleConnectFailure(
                timeout, config: config, attempt: state.attempt,
                wasOffline: state.wasOffline, isCheckingHerdr: true
            )
            #expect(model.hasActiveSession)
            #expect(model.phase == .offline(host: config.host, username: config.username))
            #expect(model.connectionBanner?.canRetry == true)
            #expect(model.autoReconnectTask != nil)
            model.cancelReconnect()
        }
    }

    @MainActor
    @Test func unrecoverableReadinessErrorsRouteToRecovery() async {
        for error in [HerdrError.herdrNotFound, .sessionUnavailable,
                      .runtimeNotInstalled(saved: .tui, available: .core),
                      .runtimeNotInstalled(saved: .core, available: nil)] {
            let config = ConnectionConfig(
                host: "offline.example", port: 22, username: "tester", auth: .password("fixture")
            )
            let model = AppModel(autoConnectOnLaunch: false)
            model.hasActiveSession = true
            model.phase = .offline(host: config.host, username: config.username)
            guard let state = await model.prepareConnectAttempt(config: config) else {
                Issue.record("Could not prepare offline reconnect")
                return
            }
            state.watchdog.cancel()
            model.handleConnectFailure(
                error, config: config, attempt: state.attempt,
                wasOffline: state.wasOffline, isCheckingHerdr: true
            )
            #expect(!model.hasActiveSession)
            #expect(model.phase == .disconnected)
            #expect(model.connectionBanner == nil)
            #expect(model.autoReconnectTask == nil)
        }
        #expect(AppModel.connectFailureDisposition(
            error: HerdrError.timeout("workspace list"),
            hadActiveSession: false,
            wasOffline: false,
            isCheckingHerdr: true
        ) == .readinessRecovery)
    }

    @MainActor
    @Test func missingRuntimeRecoveryNamesTheRuntimeTheMachineHas() async {
        let config = ConnectionConfig(host: "mac.example", port: 22, username: "tester", auth: .password("fixture"))
        let cases: [(HerdrError, AppModel.RuntimeMismatch?)] = [
            (.runtimeNotInstalled(saved: .tui, available: .core), AppModel.RuntimeMismatch(saved: .tui, installed: .core)),
            (.runtimeNotInstalled(saved: .core, available: .tui), AppModel.RuntimeMismatch(saved: .core, installed: .tui)),
            (.runtimeNotInstalled(saved: .tui, available: nil), nil)
        ]
        for (error, mismatch) in cases {
            let model = AppModel(autoConnectOnLaunch: false)
            guard let state = await model.prepareConnectAttempt(config: config) else {
                Issue.record("Could not prepare the connect attempt")
                return
            }
            state.watchdog.cancel()
            model.handleConnectFailure(
                error, config: config, attempt: state.attempt,
                wasOffline: state.wasOffline, isCheckingHerdr: true
            )
            #expect(model.herdrMissingOnLastConnect)
            #expect(model.runtimeMismatchOnLastConnect == mismatch)
            #expect(!model.lastConnectNeedsSignIn)
            #expect(model.phase == .disconnected)
            // The next attempt starts without the old recovery state.
            model.prepareConnectionStatus(for: config)
            #expect(!model.herdrMissingOnLastConnect)
            #expect(model.runtimeMismatchOnLastConnect == nil)
        }
    }

    @MainActor
    @Test func lastConnectMatchesTheSavedEntryItWasFor() async {
        let config = ConnectionConfig(host: "Mac.example", port: 22, username: "tester", auth: .password("fixture"))
        let entry = RecentConnection(host: "mac.example", port: 22, username: "tester", authMode: "password", remember: true)
        let model = AppModel(autoConnectOnLaunch: false)
        #expect(!model.lastConnectWasFor(entry))
        guard let state = await model.prepareConnectAttempt(config: config) else {
            Issue.record("Could not prepare the connect attempt")
            return
        }
        state.watchdog.cancel()
        #expect(model.lastConnectWasFor(entry))
        var core = entry
        core.backend = .core
        #expect(!model.lastConnectWasFor(core))
        var otherUser = entry
        otherUser.username = "other"
        #expect(!model.lastConnectWasFor(otherUser))
        await model.disconnect()
    }

    @MainActor
    @Test func sessionReadinessOnlyClassifiesMissingDefaultSession() {
        let serverError = HerdrError.api(code: "session_unavailable", message: "No default session")
        #expect(AppModel.sessionReadinessError(serverError) as? HerdrError == .sessionUnavailable)
        let missingSession = HerdrError.api(code: "other", message: "Default session not found")
        #expect(AppModel.sessionReadinessError(missingSession) as? HerdrError == .sessionUnavailable)

        let unsupported = HerdrError.api(code: "unsupported_command", message: "workspace list is unsupported")
        #expect(AppModel.sessionReadinessError(unsupported) as? HerdrError == unsupported)
        #expect(AppModel.sessionReadinessError(HerdrError.herdrExit(1)) as? HerdrError == .herdrExit(1))

        let decoding = HerdrError.unexpectedResponse("invalid JSON")
        #expect(AppModel.sessionReadinessError(decoding) as? HerdrError == decoding)
        let emptyOutput = HerdrError.unexpectedResponse("empty output")
        let friendlyMessage = HerdrConnection.friendlyMessage(for: AppModel.sessionReadinessError(emptyOutput))
        #expect(friendlyMessage == "Unexpected response from herdr — empty output")

        let quotaEmptyOutput = HerdrError.unexpectedResponse("quota-axi returned empty output")
        #expect(
            HerdrConnection.friendlyMessage(for: quotaEmptyOutput)
                == "quota-axi returned no data. Pull to refresh."
        )

        let timeout = HerdrError.timeout("herdr command")
        #expect(AppModel.sessionReadinessError(timeout) as? HerdrError == timeout)
        #expect(AppModel.sessionReadinessError(HerdrError.herdrNotFound) as? HerdrError == .herdrNotFound)
    }

    @MainActor
    @Test func appModelInitWithoutAutoConnectStartsDisconnected() {
        let model = AppModel(autoConnectOnLaunch: false)
        #expect(!model.hasActiveSession)
        #expect(model.phase == .disconnected)
        #expect(model.connectionBanner == nil)
        #expect(!model.isOffline)
        #expect(!model.isConnecting)
    }

    @Test func connectionBannerProperties() {
        let offline = ConnectionBanner.offline(message: "Offline · Connection lost", canRetry: true)
        #expect(offline.message == "Offline · Connection lost")
        #expect(offline.canRetry == true)
        #expect(!offline.showsProgress)
        #expect(offline.systemImage == "wifi.slash")

        let connecting = ConnectionBanner.connecting(message: "Connecting…")
        #expect(connecting.message == "Connecting…")
        #expect(!connecting.canRetry)
        #expect(connecting.showsProgress == true)
        #expect(connecting.systemImage == "arrow.clockwise")

        let backOnline = ConnectionBanner.backOnline(message: "Back online")
        #expect(backOnline.message == "Back online")
        #expect(!backOnline.canRetry)
        #expect(!backOnline.showsProgress)
        #expect(backOnline.systemImage == "checkmark.circle.fill")
    }

    @MainActor
    @Test func showBackOnlineDismissesBanner() async throws {
        let model = AppModel(autoConnectOnLaunch: false)
        model.showBackOnline(message: "Back online")
        #expect(model.connectionBanner == .backOnline(message: "Back online"))

        try await Task.sleep(for: .seconds(2.7))
        #expect(model.connectionBanner == nil)
    }

    @MainActor
    @Test func explicitDisconnectClearsSessionAndBanner() async {
        let model = AppModel(autoConnectOnLaunch: false)
        model.showBackOnline(message: "Connected")
        #expect(model.connectionBanner != nil)

        await model.disconnect()
        #expect(!model.hasActiveSession)
        #expect(model.phase == .disconnected)
        #expect(model.connectionBanner == nil)
    }
}

@Suite("SSH host key verification")
struct SSHHostKeyVerificationTests {
    private let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f"

    @Test func fingerprintMatchesOpenSSHFormat() throws {
        let parsed = try NIOSSHPublicKey(openSSHPublicKey: key)
        let canonical = String(openSSHPublicKey: parsed)
        #expect(SSHHostKeyValidatorDelegate.fingerprint(canonical)
                == "SHA256:ZkAslGjFiUHdGf/WUL8rQvkib4PTvQatUV0OUQSncCA")
    }

    @Test func unknownHostFailsWithExactApprovalCandidate() {
        let validator = SSHHostKeyValidatorDelegate(host: "server", port: 2222, trustedKey: nil)
        #expect(throws: SSHHostKeyError.unknown(SSHHostKeyChallenge(host: "server", port: 2222, publicKey: key))) {
            try validator.validate(key)
        }
    }

    @Test func matchingKeySucceedsAndChangedKeyFails() throws {
        let validator = SSHHostKeyValidatorDelegate(host: "server", port: 22, trustedKey: key)
        try validator.validate(key)
        let other = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        #expect(throws: SSHHostKeyError.changed(SSHHostKeyChallenge(
            host: "server", port: 22, publicKey: other, previousPublicKey: key))) {
            try validator.validate(other)
        }
        // Corrupt stored trust data must fail closed, never offer first-use approval.
        #expect(throws: SSHHostKeyError.self) {
            try SSHHostKeyValidatorDelegate(host: "server", port: 22, trustedKey: "corrupt").validate(key)
        }
    }

    @Test func endpointIdentityNormalizesHostAndSeparatesPorts() {
        #expect(
            SSHHostKeyStore.account(host: " SERVER ", port: 22) == SSHHostKeyStore.account(host: "server", port: 22))
        #expect(
            SSHHostKeyStore.account(host: "server", port: 22) != SSHHostKeyStore.account(host: "server", port: 2222))
        #expect(SSHHostKeyStore.account(host: "::1", port: 22) == "[::1]:22")
    }

    @Test func pinPersistsAndApprovalCannotOverwriteIt() async throws {
        let service = "com.enchantinglabs.herdrcat.tests.hostkeys.\(UUID().uuidString)"
        defer {
            let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary)
            #expect(status == errSecSuccess || status == errSecItemNotFound)
        }
        let store = SSHHostKeyStore(service: service)
        #expect(try await store.load(host: "server", port: 22) == nil)
        try await store.trust(key, host: "server", port: 22)
        try await store.trust(key, host: "SERVER", port: 22)
        let reopened = SSHHostKeyStore(service: service)
        #expect(try await reopened.load(host: "server", port: 22) == key)
        #expect(try await reopened.load(host: "server", port: 2222) == nil)
        #expect(try await reopened.load(host: "other", port: 22) == nil)
        await #expect(throws: SSHHostKeyStore.StoreError.self) {
            try await store.trust("different key", host: "server", port: 22)
        }
        #expect(try await store.load(host: "server", port: 22) == key)
    }

    @Test @MainActor func changedKeyFailureOffersReviewAndStopsAutomaticReconnect() async throws {
        let config = ConnectionConfig(host: "server", port: 22, username: "tester", auth: .password("fixture"))
        let model = AppModel(autoConnectOnLaunch: false)
        model.hasActiveSession = true
        model.phase = .offline(host: config.host, username: config.username)
        let state = try #require(await model.prepareConnectAttempt(config: config))
        state.watchdog.cancel()
        let challenge = SSHHostKeyChallenge(host: "server", port: 22,
            publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            previousPublicKey: key)
        model.handleConnectFailure(SSHHostKeyError.changed(challenge), config: config,
            attempt: state.attempt, wasOffline: state.wasOffline, isCheckingHerdr: false)
        #expect(model.hostKeyChallenge == challenge)
        #expect(model.hostKeyVerificationBlocked)
        #expect(model.autoReconnectTask == nil)
        model.scheduleAutoReconnect()
        #expect(model.autoReconnectTask == nil)
        await model.reconnect(automatically: true)
        #expect(model.hostKeyChallenge == challenge)
        #expect(model.hostKeyVerificationBlocked)
    }

    @Test func replacementAndLoadEnforceThisDeviceOnlyAccessibility() async throws {
        let service = "com.enchantinglabs.herdrcat.tests.hostkeys.\(UUID().uuidString)"
        defer { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary) }
        let other = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        let account = SSHHostKeyStore.account(host: "server", port: 22)
        func accessibility() throws -> String? {
            var result: AnyObject?
            let status = SecItemCopyMatching([
                kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
                kSecReturnAttributes: true, kSecMatchLimit: kSecMatchLimitOne,
            ] as CFDictionary, &result)
            try #require(status == errSecSuccess)
            return (result as? [String: Any])?[kSecAttrAccessible as String] as? String
        }
        let weaker = kSecAttrAccessibleAfterFirstUnlock as String
        let strict = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String

        // A pin saved by an older build under a weaker class is upgraded on load.
        let legacyStatus = SecItemAdd([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecValueData: Data(key.utf8), kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ] as CFDictionary, nil)
        try #require(legacyStatus == errSecSuccess)
        #expect(try accessibility() == weaker)
        let store = SSHHostKeyStore(service: service)
        #expect(try await store.load(host: "server", port: 22) == key)
        #expect(try accessibility() == strict)

        // Replacement keeps (and re-applies) the strict class.
        let reset = SecItemUpdate(
            [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary,
            [kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock] as CFDictionary)
        try #require(reset == errSecSuccess)
        try await store.replace(other, replacing: key, host: "server", port: 22)
        #expect(try accessibility() == strict)
    }

    @Test func replacementPersistsAndRejectsStaleOrMissingPins() async throws {
        let service = "com.enchantinglabs.herdrcat.tests.hostkeys.\(UUID().uuidString)"
        defer { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary) }
        let store = SSHHostKeyStore(service: service)
        let other = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        try await store.trust(key, host: "server", port: 22)
        try await store.trust(key, host: "server", port: 2222)
        try await store.trust(key, host: "other", port: 22)
        try await store.replace(other, replacing: key, host: "SERVER", port: 22)
        #expect(try await SSHHostKeyStore(service: service).load(host: "server", port: 22) == other)
        #expect(try await store.load(host: "server", port: 2222) == key)
        #expect(try await store.load(host: "other", port: 22) == key)
        await #expect(throws: SSHHostKeyStore.StoreError.self) {
            try await store.replace(key, replacing: key, host: "server", port: 22)
        }
        await #expect(throws: SSHHostKeyStore.StoreError.self) {
            try await store.replace(other, replacing: key, host: "missing", port: 22)
        }
        #expect(try await store.load(host: "missing", port: 22) == nil)
        #expect(try await store.load(host: "server", port: 22) == other)
        try SSHHostKeyValidatorDelegate(host: "server", port: 22, trustedKey: other).validate(other)
        #expect(throws: SSHHostKeyError.self) {
            try SSHHostKeyValidatorDelegate(host: "server", port: 22, trustedKey: other).validate(key)
        }
    }

    @Test @MainActor func cancellationAndStaleChallengesCannotReplacePin() async throws {
        let service = "com.enchantinglabs.herdrcat.tests.hostkeys.\(UUID().uuidString)"
        defer { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary) }
        let store = SSHHostKeyStore(service: service)
        try await store.trust(key, host: "server", port: 22)
        let challenge = SSHHostKeyChallenge(host: "server", port: 22,
            publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            previousPublicKey: key)
        let model = AppModel(autoConnectOnLaunch: false)
        model.hostKeyChallenge = challenge
        model.hostKeyVerificationBlocked = true
        model.cancelHostKeyApproval()
        #expect(model.hostKeyVerificationBlocked)
        #expect(await model.approveHostKey(challenge, store: store) == false)
        #expect(try await store.load(host: "server", port: 22) == key)
        model.hostKeyChallenge = challenge
        var stale = challenge
        stale.previousPublicKey = "stale pin"
        #expect(await model.approveHostKey(stale, store: store) == false)
        #expect(try await store.load(host: "server", port: 22) == key)
        #expect(await model.approveHostKey(challenge, store: store))
        #expect(model.hostKeyChallenge == nil)
        #expect(!model.hostKeyVerificationBlocked)
        #expect(try await store.load(host: "server", port: 22) == challenge.publicKey)
    }

    @Test func malformedKeychainItemIsNotAnUnknownHost() async throws {
        let service = "com.enchantinglabs.herdrcat.tests.hostkeys.\(UUID().uuidString)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: SSHHostKeyStore.account(host: "server", port: 22)
        ]
        defer {
            let status = SecItemDelete(query as CFDictionary)
            #expect(status == errSecSuccess || status == errSecItemNotFound)
        }
        var add = query
        add[kSecValueData as String] = Data([0xff])
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #expect(SecItemAdd(add as CFDictionary, nil) == errSecSuccess)
        let store = SSHHostKeyStore(service: service)
        await #expect(throws: SSHHostKeyStore.StoreError.self) {
            _ = try await store.load(host: "server", port: 22)
        }
    }
}
