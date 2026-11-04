import Foundation
import Security
import NIOSSH
import SwiftUI
import Testing
@testable import Herdcats

@Suite("Credential migration")
struct CredentialMigrationTests {
    private let pendingKey = "hc.pendingCredentialMigration"
    private let sourceAccount = KeychainStore.Account.password
    private let secret = Data("synthetic-legacy-secret".utf8)

    private struct PendingFixture: Codable {
        let sourceAccount: String
        let entry: RecentConnection
        var destinationAccount: String? = nil
    }

    func withLegacy(
        authMode: String = "password",
        _ body: (MigrationTestDefaults, FakeKeychainOperations) throws -> Void
    ) throws {
        let suite = "CredentialMigrationTests.\(UUID())"
        let defaults = try #require(MigrationTestDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("legacy.example", forKey: "hc.host")
        defaults.set("alice", forKey: "hc.username")
        defaults.set("22", forKey: "hc.port")
        defaults.set(authMode, forKey: "hc.authMode")
        defaults.set(true, forKey: "hc.remember")
        let keychain = FakeKeychainOperations()
        keychain.items[authMode == "privateKey" ? KeychainStore.Account.privateKey : sourceAccount] = secret
        try body(defaults, keychain)
    }

    private func pending(_ defaults: UserDefaults) throws -> PendingFixture {
        try JSONDecoder().decode(PendingFixture.self, from: #require(defaults.data(forKey: pendingKey)))
    }

    @MainActor @Test func replaySnapshotLeavesPendingMigrationUntouched() throws {
        try withLegacy { defaults, keychain in
            keychain.nextAddStatus = errSecInteractionNotAllowed
            #expect(throws: KeychainStore.StoreError.self) {
                try RecentConnectionStore.load(defaults: defaults, using: keychain)
            }
            let pendingBefore = try #require(defaults.data(forKey: pendingKey))
            let secretsBefore = keychain.items
            let addsBefore = keychain.addedAccounts
            let updatesBefore = keychain.updatedAccounts
            #expect(RecentConnectionStore.snapshot(defaults: defaults).isEmpty)
            let entry = RecentConnection(host: "replay.example", port: 22, username: "alice", authMode: "password", remember: false)
            let form = ConnectionSettingsView(connection: entry, isReplay: true, using: keychain)
            _ = try form.signIn(defaults: defaults, using: keychain)
            #expect(defaults.data(forKey: pendingKey) == pendingBefore)
            #expect(defaults.data(forKey: RecentConnectionStore.storageKey) == nil)
            #expect(keychain.items == secretsBefore)
            #expect(keychain.addedAccounts == addsBefore)
            #expect(keychain.updatedAccounts == updatesBefore)
            #expect(keychain.deletedAccounts.isEmpty)
        }
    }

    @Test(arguments: ["password", "privateKey"])
    func verifiesCopyAndProfileBeforeDeletingOnlySelectedLegacyCredential(authMode: String) throws {
        try withLegacy(authMode: authMode) { defaults, keychain in
            let selected = authMode == "privateKey" ? KeychainStore.Account.privateKey : sourceAccount
            let other = authMode == "privateKey" ? sourceAccount : KeychainStore.Account.privateKey
            keychain.items[other] = Data("unselected-secret".utf8)
            keychain.onDelete = { account in
                #expect(account == selected)
                guard let metadata = defaults.data(forKey: RecentConnectionStore.storageKey),
                      let entries = try? JSONDecoder().decode([RecentConnection].self, from: metadata),
                      let entry = entries.first else {
                    Issue.record("Source deletion preceded profile persistence")
                    return
                }
                #expect(keychain.items[entry.secretAccount] == secret)
            }
            let entries = try RecentConnectionStore.load(defaults: defaults, using: keychain)
            #expect(entries.count == 1)
            #expect(keychain.items[entries[0].secretAccount] == secret)
            #expect(keychain.items[selected] == nil)
            #expect(keychain.items[other] == Data("unselected-secret".utf8))
            #expect(try RecentConnectionStore.load(defaults: defaults, using: keychain) == entries)
            #expect(keychain.deletedAccounts == [selected])
        }
    }

    @Test func sourceReadFailurePreservesOriginalAndMetadata() throws {
        try withLegacy { defaults, keychain in
            keychain.failingReadAccount = sourceAccount
            #expect(throws: KeychainStore.StoreError.self) {
                try RecentConnectionStore.load(defaults: defaults, using: keychain)
            }
            #expect(keychain.items[sourceAccount] == secret)
            #expect(defaults.data(forKey: RecentConnectionStore.storageKey) == nil)
            #expect(keychain.addedAccounts.isEmpty)
            #expect(keychain.deletedAccounts.isEmpty)
            let loaded = try RecentConnectionStore.load(defaults: defaults, using: keychain)
            #expect(loaded.count == 1)
        }
    }

    @Test func destinationWriteFailureRetriesSameAccountWithoutOrphans() throws {
        try withLegacy { defaults, keychain in
            keychain.nextAddStatus = errSecInteractionNotAllowed
            #expect(throws: KeychainStore.StoreError.self) {
                try RecentConnectionStore.load(defaults: defaults, using: keychain)
            }
            let intent = try pending(defaults)
            #expect(keychain.items[sourceAccount] == secret)
            #expect(defaults.data(forKey: RecentConnectionStore.storageKey) == nil)
            let entries = try RecentConnectionStore.load(defaults: defaults, using: keychain)
            #expect(entries.map(\.id) == [intent.entry.id])
            #expect(Set(keychain.addedAccounts) == [intent.entry.secretAccount])
            #expect(keychain.items.count == 1)
        }
    }

    @Test(arguments: [false, true])
    func destinationVerificationFailurePreservesSourceAndRetries(mismatch: Bool) throws {
        try withLegacy { defaults, keychain in
            keychain.onAdd = { account in
                if mismatch { keychain.mismatchReadAccount = account } else { keychain.failingReadAccount = account }
            }
            #expect(throws: KeychainStore.StoreError.self) {
                try RecentConnectionStore.load(defaults: defaults, using: keychain)
            }
            let intent = try pending(defaults)
            #expect(keychain.items[sourceAccount] == secret)
            #expect(defaults.data(forKey: RecentConnectionStore.storageKey) == nil)
            #expect(keychain.deletedAccounts.isEmpty)
            keychain.onAdd = nil
            let entries = try RecentConnectionStore.load(defaults: defaults, using: keychain)
            #expect(entries.map(\.id) == [intent.entry.id])
            #expect(keychain.items.count == 1)
        }
    }

    @Test(arguments: ["hc.pendingCredentialMigration", "hc.recentConnections"])
    func metadataWriteFailureNeverDeletesSourceAndCanRetry(key: String) throws {
        try withLegacy { defaults, keychain in
            defaults.rejectedKeys = [key]
            #expect(throws: RecentConnectionStore.StoreError.self) {
                try RecentConnectionStore.load(defaults: defaults, using: keychain)
            }
            #expect(keychain.items[sourceAccount] == secret)
            #expect(keychain.deletedAccounts.isEmpty)
            if key == pendingKey { #expect(keychain.addedAccounts.isEmpty) }
            let destinationAccounts = keychain.addedAccounts
            defaults.rejectedKeys = []
            let entries = try RecentConnectionStore.load(defaults: defaults, using: keychain)
            #expect(entries.count == 1)
            #expect(keychain.items.count == 1)
            if let previous = destinationAccounts.first { #expect(entries[0].secretAccount == previous) }
        }
    }

    @Test func crashAfterCopyBeforeProfileCommitResumesStableDestination() throws {
        try withLegacy { defaults, keychain in
            let entry = RecentConnection(
                host: "legacy.example", port: 22, username: "alice", authMode: "password", remember: true)
            defaults.set(
                try JSONEncoder().encode(PendingFixture(sourceAccount: sourceAccount, entry: entry, destinationAccount: entry.secretAccount)), forKey: pendingKey
            )
            keychain.items[entry.secretAccount] = secret
            keychain.onDelete = { _ in #expect(defaults.data(forKey: RecentConnectionStore.storageKey) != nil) }
            let entries = try RecentConnectionStore.load(defaults: defaults, using: keychain)
            #expect(entries == [entry])
            #expect(keychain.items[entry.secretAccount] == secret)
            #expect(keychain.addedAccounts.isEmpty)
            #expect(keychain.items[sourceAccount] == nil)
        }
    }

    @Test func cleanupFailureRetriesWithoutRewritingCopyOrProfile() throws {
        try withLegacy { defaults, keychain in
            keychain.nextDeleteStatus = errSecInteractionNotAllowed
            #expect(throws: KeychainStore.StoreError.self) {
                try RecentConnectionStore.load(defaults: defaults, using: keychain)
            }
            let intent = try pending(defaults)
            let committed = defaults.data(forKey: RecentConnectionStore.storageKey)
            #expect(keychain.items[sourceAccount] == secret)
            keychain.addedAccounts = []
            let entries = try RecentConnectionStore.load(defaults: defaults, using: keychain)
            #expect(entries == [intent.entry])
            #expect(defaults.data(forKey: RecentConnectionStore.storageKey) == committed)
            #expect(keychain.addedAccounts.isEmpty)
            #expect(keychain.items.count == 1)
            #expect(defaults.data(forKey: pendingKey) == nil)
        }
    }

    @Test(arguments: [false, true])
    func oldPendingMarkerResumesItsOriginalDestinationAfterUpgrade(committed: Bool) throws {
        try withLegacy { defaults, keychain in
            let entry = RecentConnection(host: "legacy.example", port: 22, username: "alice", authMode: "password", remember: true)
            // Previous versions recorded only these two fields and copied into the shared profile slot.
            defaults.set(try JSONEncoder().encode(PendingFixture(sourceAccount: sourceAccount, entry: entry)), forKey: pendingKey)
            keychain.items[entry.legacySecretAccount] = secret
            if committed { defaults.set(try JSONEncoder().encode([entry]), forKey: RecentConnectionStore.storageKey) }
            #expect(try RecentConnectionStore.load(defaults: defaults, using: keychain) == [entry])
            #expect(keychain.items[sourceAccount] == nil)
            #expect(keychain.addedAccounts.isEmpty)
            #expect(defaults.data(forKey: pendingKey) == nil)
            #expect(try ConnectionSignIn.load(entry, using: keychain).secret == "synthetic-legacy-secret")
            try RecentConnectionStore.remove(entry, defaults: defaults, using: keychain)
            #expect(keychain.items.isEmpty)
        }
    }

    @Test(arguments: ["secretChanged", "secretDeleted", "rememberDisabled", "authChanged", "profileDeleted"])
    func cleanupRetryDoesNotUndoNewerUserChanges(change: String) throws {
        try withLegacy { defaults, keychain in
            keychain.nextDeleteStatus = errSecInteractionNotAllowed
            #expect(throws: KeychainStore.StoreError.self) {
                try RecentConnectionStore.load(defaults: defaults, using: keychain)
            }
            var entry = try pending(defaults).entry
            switch change {
            case "secretChanged": keychain.items[entry.secretAccount] = Data("newer-secret".utf8)
            case "secretDeleted": keychain.items[entry.secretAccount] = nil
            case "rememberDisabled": entry.remember = false
            case "authChanged": entry.authMode = "privateKey"
            default: break
            }
            let expected = change == "profileDeleted" ? [] : [entry]
            defaults.set(try JSONEncoder().encode(expected), forKey: RecentConnectionStore.storageKey)
            let itemsBefore = keychain.items
            #expect(try RecentConnectionStore.load(defaults: defaults, using: keychain) == expected)
            #expect(keychain.items == itemsBefore)
            #expect(keychain.items[sourceAccount] == secret)
        }
    }

    @Test func missingSourceAndRememberDisabledDoNotDeleteOtherCredentials() throws {
        try withLegacy { defaults, keychain in
            keychain.items[sourceAccount] = nil
            keychain.items[KeychainStore.Account.privateKey] = secret
            let loaded = try RecentConnectionStore.load(defaults: defaults, using: keychain)
            #expect(loaded.count == 1)
            #expect(keychain.deletedAccounts.isEmpty)
            #expect(keychain.items[KeychainStore.Account.privateKey] == secret)
        }
        try withLegacy { defaults, keychain in
            defaults.set(false, forKey: "hc.remember")
            let entries = try RecentConnectionStore.load(defaults: defaults, using: keychain)
            #expect(entries.first?.remember == false)
            #expect(keychain.deletedAccounts.isEmpty)
        }
    }

    @Test func keychainStatusMappingAndDuplicateUpdateRace() throws {
        let keychain = FakeKeychainOperations()
        keychain.nextAddStatus = errSecInteractionNotAllowed
        #expect(throws: KeychainStore.StoreError.self) {
            try KeychainStore.save("new", account: "test", using: keychain)
        }
        keychain.items["test"] = secret
        keychain.nextUpdateStatus = errSecAuthFailed
        #expect(throws: KeychainStore.StoreError.self) {
            try KeychainStore.save("new", account: "test", using: keychain)
        }
        #expect(keychain.items["test"] == secret)
        keychain.nextUpdateStatus = errSecItemNotFound
        try KeychainStore.save("new", account: "test", using: keychain)
        #expect(try KeychainStore.load(account: "test", using: keychain) == "new")
        #expect(
            keychain.lastAddQuery?[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        keychain.failingReadAccount = "test"
        #expect(throws: KeychainStore.StoreError.self) { try KeychainStore.load(account: "test", using: keychain) }
        keychain.items["test"] = Data([0xff])
        #expect(throws: KeychainStore.StoreError.self) { try KeychainStore.load(account: "test", using: keychain) }
        keychain.nextDeleteStatus = errSecInteractionNotAllowed
        #expect(throws: KeychainStore.StoreError.self) { try KeychainStore.delete(account: "test", using: keychain) }
        #expect(keychain.items["test"] != nil)
        try KeychainStore.delete(account: "missing", using: keychain)
        #expect(try KeychainStore.load(account: "missing", using: keychain) == nil)
    }

    @MainActor @Test func storageFailureReturnsToConnectScreenWithError() async {
        let model = AppModel(autoConnectOnLaunch: false)
        await model.reportCredentialStorageError("Could not save credentials.")
        #expect(!model.hasActiveSession)
        #expect(model.lastError == "Could not save credentials.")
        #expect(model.connectionBanner == nil)
    }
}

@Suite("Credential accessibility")
struct CredentialAccessibilityTests {
    @Test func newAndUpdatedSecretsUseUnlockedDeviceOnlyProtection() throws {
        let keychain = FakeKeychainOperations()
        let policy = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        try KeychainStore.save("first-secret", account: "profile", using: keychain)
        #expect(keychain.protectionByAccount["profile"] == policy)
        keychain.protectionByAccount["profile"] = kSecAttrAccessibleAfterFirstUnlock as String
        try KeychainStore.save("second-secret", account: "profile", using: keychain)
        #expect(keychain.protectionByAccount["profile"] == policy)
        #expect(keychain.items["profile"] == Data("second-secret".utf8))
        keychain.nextUpdateStatus = errSecItemNotFound
        try KeychainStore.save("third-secret", account: "profile", using: keychain)
        #expect(keychain.protectionByAccount["profile"] == policy)
        #expect(keychain.items["profile"] == Data("third-secret".utf8))
    }

    @Test(arguments: ["connection.password", "connection.privateKey", "connection.fixture.secret"])
    func existingSecretsAreTightenedOnReadWithoutChangingTheirData(account: String) throws {
        let keychain = FakeKeychainOperations()
        let secret = Data("synthetic-credential".utf8)
        keychain.items[account] = secret
        keychain.protectionByAccount[account] = kSecAttrAccessibleAfterFirstUnlock as String
        keychain.items["unrelated"] = Data("other-value".utf8)
        keychain.protectionByAccount["unrelated"] = kSecAttrAccessibleAfterFirstUnlock as String
        #expect(try KeychainStore.load(account: account, using: keychain) == "synthetic-credential")
        #expect(keychain.protectionByAccount[account] == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(keychain.items[account] == secret)
        #expect(keychain.protectionByAccount["unrelated"] == kSecAttrAccessibleAfterFirstUnlock as String)
        #expect(keychain.updatedAccounts == [account])
        #expect(keychain.deletedAccounts.isEmpty)
        #expect(keychain.addedAccounts.isEmpty)
    }

    @Test(arguments: [errSecInteractionNotAllowed, errSecAuthFailed, errSecItemNotFound])
    func failedProtectionUpdateDoesNotReturnTheSecret(status: OSStatus) {
        let keychain = FakeKeychainOperations()
        keychain.items["profile"] = Data("synthetic-secret".utf8)
        keychain.protectionByAccount["profile"] = kSecAttrAccessibleAfterFirstUnlock as String
        keychain.nextUpdateStatus = status
        do {
            _ = try KeychainStore.load(account: "profile", using: keychain)
            Issue.record("A credential was returned after its protection update failed")
        } catch let error as KeychainStore.StoreError {
            #expect(error.status == status)
            #expect(!error.localizedDescription.contains("synthetic-secret"))
        } catch {
            Issue.record("Unexpected error type")
        }
        #expect(keychain.deletedAccounts.isEmpty)
    }

    @Test func absentSecretsDoNotCreateOrUpdateItems() throws {
        let keychain = FakeKeychainOperations()
        #expect(try KeychainStore.load(account: "missing", using: keychain) == nil)
        #expect(keychain.updatedAccounts.isEmpty)
        #expect(keychain.addedAccounts.isEmpty)
    }

    @Test func realKeychainReadUpgradesAnExistingItemInPlace() throws {
        let account = "herdrcat.tests.accessibility.\(UUID())"
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.enchantinglabs.herdrcat",
            kSecAttrAccount as String: account
        ]
        var item = identity
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecValueData as String] = Data("synthetic-keychain-fixture".utf8)
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        try #require(addStatus == errSecSuccess)
        defer {
            let status = SecItemDelete(identity as CFDictionary)
            #expect(status == errSecSuccess || status == errSecItemNotFound)
        }
        #expect(try KeychainStore.load(account: account) == "synthetic-keychain-fixture")
        var query = identity
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let readStatus = SecItemCopyMatching(query as CFDictionary, &result)
        try #require(readStatus == errSecSuccess)
        let attributes = try #require(result as? [String: Any])
        #expect(
            attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                as String)
    }
}

@Suite("Launch preference")
struct LaunchPreferenceTests {
    @Test func autoConnectIsOffByDefaultAndNeedsRememberedCredentials() throws {
        let defaults = try #require(UserDefaults(suiteName: "LaunchPreferenceTests.\(UUID())"))
        defer {
            defaults.removeObject(forKey: LaunchPreference.storageKey)
            defaults.removeObject(forKey: RecentConnectionStore.storageKey)
        }

        #expect(LaunchPreference.autoConnectConfig(defaults: defaults) == nil)

        let entry = RecentConnection(
            host: "mac.local", port: 22, username: "alice",
            authMode: "password", remember: true
        )
        _ = try RecentConnectionStore.record(entry, in: [], defaults: defaults)
        try KeychainStore.save("secret", account: entry.secretAccount)
        defer { try? KeychainStore.delete(account: entry.secretAccount) }

        defaults.set(LaunchPreference.connectionSelection.rawValue, forKey: LaunchPreference.storageKey)
        #expect(LaunchPreference.autoConnectConfig(defaults: defaults) == nil)

        defaults.set(LaunchPreference.autoConnect.rawValue, forKey: LaunchPreference.storageKey)
        let config = LaunchPreference.autoConnectConfig(defaults: defaults)
        #expect(config?.host == "mac.local")
        #expect(config?.username == "alice")
        #expect(config?.auth == .password("secret"))
    }
}
