import Foundation
import Security
import NIOSSH
import SwiftUI
import Testing
@testable import Herdcats

@Suite("Pane last updated")
struct PaneLastUpdatedTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private var locale: Locale { Locale(identifier: "en_US_POSIX") }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 15, _ minute: Int = 30) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    @Test func formatsTodayAsTime() {
        let now = date(2026, 9, 20, 18, 0)
        let label = PaneUpdatedFormat.label(
            for: date(2026, 9, 20, 9, 5),
            now: now,
            calendar: calendar,
            locale: locale
        )
        #expect(label.contains("9"))
        #expect(label.contains("05"))
    }

    @Test func formatsYesterday() {
        let now = date(2026, 9, 20)
        let label = PaneUpdatedFormat.label(
            for: date(2026, 9, 19, 22, 0),
            now: now,
            calendar: calendar,
            locale: locale
        )
        #expect(label == "Yesterday")
    }

    @Test func formatsWeekdayWithinWeek() {
        let now = date(2026, 9, 20) // Sunday
        let label = PaneUpdatedFormat.label(
            for: date(2026, 9, 17, 11, 0), // Thursday
            now: now,
            calendar: calendar,
            locale: locale
        )
        #expect(label == "Thursday")
    }

    @Test func formatsDateBeyondWeek() {
        let now = date(2026, 9, 20)
        let label = PaneUpdatedFormat.label(
            for: date(2026, 9, 1, 8, 0),
            now: now,
            calendar: calendar,
            locale: locale
        )
        #expect(label.contains("Sep"))
        #expect(label.contains("1"))
    }

    @Test func observeRecordsFirstSeenAndBumpsOnChange() throws {
        let suiteName = "PaneLastUpdatedTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scope = ConnectionIdentity(host: "test.local", port: 22, username: "tester")

        let firstJSON = """
        {"id":"cli:pane:list","result":{"panes":[
        {"agent_status":"idle","focused":true,"pane_id":"w1:p1","revision":1,"tab_id":"w1:t1","workspace_id":"w1"}
        ]}}
        """
        let first = try HerdrConnection.decode(firstJSON, as: PaneListResult.self).panes
        let firstObservedAt = date(2026, 9, 20, 10, 0)
        let dates1 = PaneLastUpdatedStore.observe(first, scope: scope, now: firstObservedAt, defaults: defaults)
        #expect(dates1["w1:p1"] == firstObservedAt)

        let unchanged = PaneLastUpdatedStore.observe(
            first, scope: scope, now: date(2026, 9, 20, 11, 0), defaults: defaults)
        #expect(unchanged["w1:p1"] == firstObservedAt)

        let secondJSON = """
        {"id":"cli:pane:list","result":{"panes":[
        {"agent_status":"working","focused":true,"pane_id":"w1:p1","revision":2,"tab_id":"w1:t1","workspace_id":"w1"}
        ]}}
        """
        let second = try HerdrConnection.decode(secondJSON, as: PaneListResult.self).panes
        let secondObservedAt = date(2026, 9, 20, 12, 0)
        let dates2 = PaneLastUpdatedStore.observe(second, scope: scope, now: secondObservedAt, defaults: defaults)
        #expect(dates2["w1:p1"] == secondObservedAt)
    }

    @Test func observeAgentsSharesStoreWithPanes() throws {
        let suiteName = "PaneLastUpdatedTests.agents.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scope = ConnectionIdentity(host: "test.local", port: 22, username: "tester")

        let agentsJSON = """
        {"id":"cli:agent:list","result":{"agents":[
        {"agent":"cursor","agent_status":"idle","focused":true,"pane_id":"w1:p1","revision":1,
        "tab_id":"w1:t1","workspace_id":"w1"}
        ]}}
        """
        let agents = try HerdrConnection.decode(agentsJSON, as: AgentListResult.self).agents
        let firstObservedAt = date(2026, 9, 20, 10, 0)
        let dates1 = PaneLastUpdatedStore.observe(agents, scope: scope, now: firstObservedAt, defaults: defaults)
        #expect(dates1["w1:p1"] == firstObservedAt)

        let panesJSON = """
        {"id":"cli:pane:list","result":{"panes":[
        {"agent":"cursor","agent_status":"idle","focused":true,"label":"command","pane_id":"w1:p1",
        "revision":1,"tab_id":"w1:t1","workspace_id":"w1"}
        ]}}
        """
        let panes = try HerdrConnection.decode(panesJSON, as: PaneListResult.self).panes
        let unchanged = PaneLastUpdatedStore.observe(
            panes, scope: scope, now: date(2026, 9, 20, 11, 0), defaults: defaults)
        #expect(unchanged["w1:p1"] == firstObservedAt)

        let workingAgentsJSON = """
        {"id":"cli:agent:list","result":{"agents":[
        {"agent":"cursor","agent_status":"working","focused":true,"pane_id":"w1:p1","revision":2,
        "tab_id":"w1:t1","workspace_id":"w1"}
        ]}}
        """
        let working = try HerdrConnection.decode(workingAgentsJSON, as: AgentListResult.self).agents
        let secondObservedAt = date(2026, 9, 20, 12, 0)
        let dates2 = PaneLastUpdatedStore.observe(working, scope: scope, now: secondObservedAt, defaults: defaults)
        #expect(dates2["w1:p1"] == secondObservedAt)
    }
}

@Suite("Agents attention ordering")
struct AgentAttentionOrderingTests {
    func item(_ id: String, _ status: String, _ sequence: UInt64?) throws -> AgentListItem {
        let workspace = try HerdrConnection.decode(workspaceListJSON, as: WorkspaceListResult.self).workspaces[0]
        let agent = AgentEntry(
            agent: "codex", agentStatus: status, stateChangeSeq: sequence,
            cwd: nil, paneId: id, tabId: "tab", workspaceId: workspace.workspaceId,
            terminalTitle: nil, terminalTitleStripped: "Same title", focused: false,
            revision: nil
        )
        return AgentListItem(space: Space(workspace: workspace, agents: [agent]), agent: agent)
    }

    @Test
    func blockedThenDoneThenWorkingThenIdleThenUnknownPerHerdrPriority() throws {
        let items = try [
            item("working", "working", 100),
            item("done", "done", 30),
            item("idle", "idle", 40),
            item("blocked", "blocked", 10),
            item("unknown", "unknown", 200)
        ]
        // Mirrors herdr's tab_attention_priority: blocked > done > working >
        // idle > unknown, regardless of state-change recency.
        #expect(items.sorted(by: AgentListItem.attentionOrder).map(\.id)
                == ["blocked", "done", "working", "idle", "unknown"])
    }

    @Test
    func missingSequenceAndTiesHaveStableFallbacks() throws {
        let items = try [item("z", "idle", nil), item("b", "done", 5),
                         item("a", "idle", 5), item("y", "done", nil)]
        #expect(items.sorted(by: AgentListItem.attentionOrder).map(\.id) == ["b", "y", "a", "z"])
    }

    @Test
    func groupedSectionsFollowSpaceOrderAndKeepJoinOrder() throws {
        let workspaces = try HerdrConnection.decode(workspaceListJSON, as: WorkspaceListResult.self).workspaces
        let agents = try HerdrConnection.decode(agentListJSON, as: AgentListResult.self).agents
        let spaces = Space.join(workspaces: workspaces, agents: agents)

        let sections = AgentListItem.grouped(in: spaces)
        // w32 has no agents: its section is hidden, not rendered empty.
        #expect(sections.map(\.space.id) == ["w4", "w4H"])
        #expect(sections.allSatisfy { !$0.items.isEmpty })

        // The two-agent space keeps its join (title) order in grouped mode —
        // grouping must not silently re-sort by attention.
        let samplenotes = try #require(sections.first { $0.space.id == "w4" })
        #expect(samplenotes.items.map(\.id) == ["w4:p2V", "w3W:p4"])
        #expect(samplenotes.items.map(\.id) == samplenotes.space.agents.map(\.paneId))
    }

    @Test
    func decodesSequenceAndAcceptsOlderResponses() throws {
        let agents = try HerdrConnection.decode(agentListJSON, as: AgentListResult.self).agents
        #expect(agents.first?.stateChangeSeq == 52)
        let olderJSON = agentListJSON.replacingOccurrences(of: "\"state_change_seq\":52,", with: "")
        let olderAgents = try HerdrConnection.decode(olderJSON, as: AgentListResult.self).agents
        #expect(olderAgents.first?.stateChangeSeq == nil)
    }
}

@Suite("Card reorder motion")
struct CardReorderMotionTests {
    @Test func raisesTheCardWhosePriorityChanged() {
        let old = [
            ReorderingCard(id: "a", priorityKey: "working"),
            ReorderingCard(id: "b", priorityKey: "working")
        ]
        let new = [
            ReorderingCard(id: "b", priorityKey: "working"),
            ReorderingCard(id: "a", priorityKey: "idle")
        ]
        #expect(ReorderingCard.movingID(from: old, to: new) == "a")
    }

    @Test func ignoresInitialLoadAndUnchangedOrder() {
        let cards = [ReorderingCard(id: "a", priorityKey: "working")]
        #expect(ReorderingCard.movingID(from: [], to: cards) == nil)
        #expect(ReorderingCard.movingID(from: cards, to: cards) == nil)
        #expect(
            ReorderingCard.movingID(from: cards, to: [ReorderingCard(id: "b", priorityKey: "blocked")] + cards) == nil)
    }
}

@Suite("Recent connections")
struct RecentConnectionTests {
    @Test func reconnectKeepsExistingProfilePositionAndPreservesCredentialAccount() throws {
        let defaults = try #require(UserDefaults(suiteName: "RecentConnectionTests.\(UUID())"))
        defer { defaults.removeObject(forKey: RecentConnectionStore.storageKey) }
        let first = RecentConnection(
            host: "mac.local", port: 22, username: "alice", authMode: "password", remember: true)
        let second = RecentConnection(
            host: "server.local", port: 2222, username: "bob", authMode: "privateKey", remember: false)
        let updated = RecentConnectionStore.entry(
            host: " MAC.local ", port: 22, username: " alice ", authMode: "privateKey",
            remember: false, in: [second, first]
        )
        #expect(updated.id == first.id)
        #expect(updated.legacySecretAccount == first.legacySecretAccount)
        #expect(updated.secretAccount != first.secretAccount)
        #expect(updated.authMode == "privateKey")
        #expect(!updated.remember)
        let entries = try RecentConnectionStore.record(updated, in: [second, first], defaults: defaults)
        #expect(entries.map(\.id) == [second.id, first.id])
        #expect(try RecentConnectionStore.load(defaults: defaults) == entries)
    }

    @Test func differentPortsAndUsersHaveSeparateCredentialAccounts() {
        let first = RecentConnection(
            host: "mac.local", port: 22, username: "alice", authMode: "password", remember: true)
        let port = RecentConnectionStore.entry(
            host: first.host, port: 2222, username: first.username, authMode: "password", remember: true, in: [first])
        let user = RecentConnectionStore.entry(
            host: first.host, port: 22, username: "bob", authMode: "password", remember: true, in: [first])
        #expect(Set([first.secretAccount, port.secretAccount, user.secretAccount]).count == 3)
    }

    @Test func removeDeletesMetadataSecretAndPassphraseOfOnlyThatConnection() throws {
        let defaults = try #require(UserDefaults(suiteName: "RecentConnectionTests.\(UUID())"))
        defer { defaults.removeObject(forKey: RecentConnectionStore.storageKey) }
        let keychain = FakeKeychainOperations()
        let first = RecentConnection(
            host: "mac.local", port: 22, username: "alice", authMode: "privateKey", remember: true)
        let second = RecentConnection(
            host: "server.local", port: 22, username: "bob", authMode: "password", remember: true)
        _ = try RecentConnectionStore.record(first, in: [second], defaults: defaults)
        for entry in [first, second] {
            for account in entry.credentialAccounts {
                try KeychainStore.save("synthetic-secret", account: account, using: keychain)
            }
        }

        let remaining = try RecentConnectionStore.remove(first, defaults: defaults, using: keychain)

        #expect(remaining == [second])
        #expect(try RecentConnectionStore.load(defaults: defaults, using: keychain) == [second])
        for account in first.credentialAccounts { #expect(keychain.items[account] == nil) }
        for account in second.credentialAccounts { #expect(keychain.items[account] != nil) }
    }

    @Test func removeOfUnknownConnectionLeavesOthersAndToleratesMissingSecrets() throws {
        let defaults = try #require(UserDefaults(suiteName: "RecentConnectionTests.\(UUID())"))
        defer { defaults.removeObject(forKey: RecentConnectionStore.storageKey) }
        let keychain = FakeKeychainOperations()
        let saved = RecentConnection(
            host: "mac.local", port: 22, username: "alice", authMode: "password", remember: false)
        let stranger = RecentConnection(
            host: "other.local", port: 22, username: "eve", authMode: "password", remember: true)
        let persisted = try RecentConnectionStore.record(saved, in: [], defaults: defaults)

        #expect(try RecentConnectionStore.remove(stranger, defaults: defaults, using: keychain) == persisted)
    }

    @Test func removeKeepsEntryWhenKeychainDeletionFails() throws {
        let defaults = try #require(UserDefaults(suiteName: "RecentConnectionTests.\(UUID())"))
        defer { defaults.removeObject(forKey: RecentConnectionStore.storageKey) }
        let keychain = FakeKeychainOperations()
        let saved = RecentConnection(
            host: "mac.local", port: 22, username: "alice", authMode: "password", remember: true)
        let persisted = try RecentConnectionStore.record(saved, in: [], defaults: defaults)
        try KeychainStore.save("secret", account: saved.secretAccount, using: keychain)
        keychain.nextDeleteStatus = errSecInteractionNotAllowed

        #expect(throws: KeychainStore.StoreError.self) {
            try RecentConnectionStore.remove(saved, defaults: defaults, using: keychain)
        }
        #expect(try RecentConnectionStore.load(defaults: defaults, using: keychain) == persisted)
    }

    @Test func disableRememberingUpdatesSavedEntryInPlaceWithoutReordering() throws {
        let defaults = try #require(UserDefaults(suiteName: "RecentConnectionTests.\(UUID())"))
        defer { defaults.removeObject(forKey: RecentConnectionStore.storageKey) }
        let keychain = FakeKeychainOperations()
        let first = RecentConnection(
            host: "mac.local", port: 22, username: "alice", authMode: "password", remember: true)
        let second = RecentConnection(
            host: "server.local", port: 22, username: "bob", authMode: "password", remember: true)
        _ = try RecentConnectionStore.record(second, in: [first], defaults: defaults)

        let entries = try RecentConnectionStore.disableRemembering(first, defaults: defaults, using: keychain)

        #expect(entries.map(\.id) == [first.id, second.id])
        #expect(entries.first { $0.id == first.id }?.remember == false)
        #expect(entries.first { $0.id == second.id }?.remember == true)
        #expect(try RecentConnectionStore.load(defaults: defaults, using: keychain) == entries)
    }

    @Test func disableRememberingNeverInsertsAnUnsavedConnection() throws {
        let defaults = try #require(UserDefaults(suiteName: "RecentConnectionTests.\(UUID())"))
        defer { defaults.removeObject(forKey: RecentConnectionStore.storageKey) }
        let keychain = FakeKeychainOperations()
        let unsaved = RecentConnection(
            host: "new.local", port: 22, username: "alice", authMode: "password", remember: false)

        #expect(try RecentConnectionStore.disableRemembering(unsaved, defaults: defaults, using: keychain).isEmpty)
        #expect(defaults.data(forKey: RecentConnectionStore.storageKey) == nil)
    }

    @Test func emptyOrCorruptHistoryIsSafe() throws {
        let defaults = try #require(UserDefaults(suiteName: "RecentConnectionTests.\(UUID())"))
        defer { defaults.removeObject(forKey: RecentConnectionStore.storageKey) }
        #expect(try RecentConnectionStore.load(defaults: defaults).isEmpty)
        defaults.set(Data("invalid".utf8), forKey: RecentConnectionStore.storageKey)
        #expect(try RecentConnectionStore.load(defaults: defaults).isEmpty)
    }
}

final class FakeKeychainOperations: KeychainOperations {
    var items: [String: Data] = [:]
    var nextAddStatus: OSStatus?
    var nextUpdateStatus: OSStatus?
    var nextDeleteStatus: OSStatus?
    var failingReadAccount: String?
    var mismatchReadAccount: String?
    var onAdd: ((String) -> Void)?
    var onDelete: ((String) -> Void)?
    var addedAccounts: [String] = []
    var deletedAccounts: [String] = []
    var lastAddQuery: NSDictionary?
    var protectionByAccount: [String: String] = [:]
    var updatedAccounts: [String] = []
    var copiedAccounts: [String] = []

    func account(_ query: CFDictionary) -> String {
        guard let account = (query as NSDictionary)[kSecAttrAccount as String] as? String else {
            preconditionFailure("Synthetic keychain query is missing its account")
        }
        return account
    }

    func add(_ query: CFDictionary) -> OSStatus {
        let account = account(query)
        addedAccounts.append(account)
        lastAddQuery = query as NSDictionary
        if let status = nextAddStatus { nextAddStatus = nil; return status }
        guard items[account] == nil else { return errSecDuplicateItem }
        items[account] = (query as NSDictionary)[kSecValueData as String] as? Data
        protectionByAccount[account] = (query as NSDictionary)[kSecAttrAccessible as String] as? String
        onAdd?(account)
        return errSecSuccess
    }

    func update(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus {
        let account = account(query)
        updatedAccounts.append(account)
        if let status = nextUpdateStatus {
            nextUpdateStatus = nil
            if status == errSecItemNotFound { items[account] = nil }
            return status
        }
        guard items[account] != nil else { return errSecItemNotFound }
        if let data = (attributes as NSDictionary)[kSecValueData as String] as? Data { items[account] = data }
        if let protection = (attributes as NSDictionary)[kSecAttrAccessible as String] as? String {
            protectionByAccount[account] = protection
        }
        return errSecSuccess
    }

    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>) -> OSStatus {
        let account = account(query)
        copiedAccounts.append(account)
        if failingReadAccount == account {
            failingReadAccount = nil
            return errSecInteractionNotAllowed
        }
        guard let data = items[account] else { return errSecItemNotFound }
        if mismatchReadAccount == account {
            mismatchReadAccount = nil
            result.pointee = Data("wrong-value".utf8) as CFData
        } else {
            result.pointee = data as CFData
        }
        return errSecSuccess
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        let account = account(query)
        deletedAccounts.append(account)
        onDelete?(account)
        if let status = nextDeleteStatus { nextDeleteStatus = nil; return status }
        guard items.removeValue(forKey: account) != nil else { return errSecItemNotFound }
        return errSecSuccess
    }
}

final class MigrationTestDefaults: UserDefaults, @unchecked Sendable {
    var rejectedKeys: Set<String> = []

    override func set(_ value: Any?, forKey defaultName: String) {
        if !rejectedKeys.contains(defaultName) { super.set(value, forKey: defaultName) }
    }
}

@Suite("Saved connection workflow")
struct SavedConnectionWorkflowTests {
    let entry = RecentConnection(host: "mac.local", port: 22, username: "alice", authMode: "password", remember: true)

    @Test func destinationEditWriteFailurePreservesSavedCredentials() throws {
        let suite = "DestinationWriteFailure.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        try ConnectionSignIn(entry: entry, secret: "saved-password").persist(defaults: defaults, using: keychain)
        var edited = entry
        edited.username = "bob"
        keychain.nextAddStatus = errSecInteractionNotAllowed
        #expect(throws: KeychainStore.StoreError.self) {
            try ConnectionSignIn(entry: edited, secret: "replacement").persist(defaults: defaults, using: keychain, connected: false)
        }
        #expect(try ConnectionSignIn.load(entry, using: keychain).secret == "saved-password")
        #expect(RecentConnectionStore.snapshot(defaults: defaults).first?.username == "alice")
    }

    @MainActor @Test func authenticationChangesPreserveBothSavedCredentials() throws {
        let suite = "AuthenticationEdits.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        try ConnectionSignIn(entry: entry, secret: "saved-password").persist(defaults: defaults, using: keychain)
        var keyed = entry
        keyed.authMode = "privateKey"
        try ConnectionSignIn(entry: keyed, secret: "synthetic-private-key").persist(defaults: defaults, using: keychain, connected: false)
        // Reopening must hydrate the inactive field too, without treating the key as a password.
        let keyForm = ConnectionSettingsView(connection: keyed, defaults: defaults, using: keychain)
        #expect(keyForm.password == "saved-password")
        #expect(keyForm.keyPEM == "synthetic-private-key")
        #expect(try ConnectionSignIn.load(entry, using: keychain).secret == "saved-password")
        try ConnectionSignIn(entry: entry, secret: "replacement-password").persist(defaults: defaults, using: keychain, connected: false)
        #expect(try ConnectionSignIn.load(keyed, using: keychain).secret == "synthetic-private-key")
    }

    @Test func explicitClearingRemovesOnlyTheSelectedCredential() throws {
        let suite = "CredentialClearing.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        var keyed = entry
        keyed.authMode = "privateKey"
        try ConnectionSignIn(entry: entry, secret: "password").persist(defaults: defaults, using: keychain)
        try ConnectionSignIn(entry: keyed, secret: "synthetic-key").persist(defaults: defaults, using: keychain)
        try ConnectionSignIn(entry: entry, secret: "").persist(defaults: defaults, using: keychain, connected: false)
        #expect(try ConnectionSignIn.load(entry, using: keychain).secret.isEmpty)
        #expect(try ConnectionSignIn.load(keyed, using: keychain).secret == "synthetic-key")
        var forgotten = keyed
        forgotten.remember = false
        try ConnectionSignIn(entry: forgotten, secret: "in-memory-key").persist(defaults: defaults, using: keychain, connected: false)
        #expect(keychain.items.isEmpty)
    }

    @Test(arguments: ["password", "privateKey"])
    func legacyProfileCredentialIsCopiedAndVerifiedBeforeRemoval(authMode: String) throws {
        var profile = entry
        profile.authMode = authMode
        let keychain = FakeKeychainOperations()
        let legacy = "connection.\(profile.id.uuidString).secret"
        keychain.items[legacy] = Data("legacy-profile-secret".utf8)
        #expect(try ConnectionSignIn.load(profile, using: keychain, readOnly: true).secret == "legacy-profile-secret")
        #expect(keychain.addedAccounts.isEmpty)
        #expect(keychain.deletedAccounts.isEmpty)
        keychain.onDelete = { account in
            if account == legacy { #expect(keychain.items[profile.secretAccount] == Data("legacy-profile-secret".utf8)) }
        }
        #expect(try ConnectionSignIn.load(profile, using: keychain).secret == "legacy-profile-secret")
        #expect(keychain.items[legacy] == nil)
        #expect(try ConnectionSignIn.load(profile, using: keychain).secret == "legacy-profile-secret")
    }

    @Test(arguments: ["read", "write", "verification", "cleanup"])
    func legacyProfileMigrationFailureKeepsSourceRetryable(stage: String) throws {
        let keychain = FakeKeychainOperations()
        let legacy = "connection.\(entry.id.uuidString).secret"
        keychain.items[legacy] = Data("legacy-password".utf8)
        switch stage {
        case "read": keychain.failingReadAccount = legacy
        case "write": keychain.nextAddStatus = errSecInteractionNotAllowed
        case "verification": keychain.onAdd = { keychain.mismatchReadAccount = $0 }
        default: keychain.nextDeleteStatus = errSecInteractionNotAllowed
        }
        #expect(throws: KeychainStore.StoreError.self) { try ConnectionSignIn.load(entry, using: keychain) }
        #expect(keychain.items[legacy] == Data("legacy-password".utf8))
        if stage != "cleanup" { #expect(keychain.deletedAccounts.isEmpty) }
        keychain.onAdd = nil
        #expect(try ConnectionSignIn.load(entry, using: keychain).secret == "legacy-password")
        #expect(keychain.items[legacy] == nil)
    }

    @Test func authenticationEditMigratesLegacyCredentialUsingSavedMethod() throws {
        let suite = "LegacyAuthEdit.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        var keyed = entry
        keyed.authMode = "privateKey"
        try RecentConnectionStore.record(keyed, in: [], defaults: defaults, stampConnected: false)
        keychain.items["connection.\(entry.id.uuidString).secret"] = Data("legacy-private-key".utf8)
        try ConnectionSignIn(entry: entry, secret: "new-password").persist(defaults: defaults, using: keychain, connected: false)
        #expect(try ConnectionSignIn.load(entry, using: keychain).secret == "new-password")
        #expect(try ConnectionSignIn.load(keyed, using: keychain).secret == "legacy-private-key")
    }

    @MainActor @Test func formSubmitsBothCredentialsAndHonorsExplicitInactiveClearing() throws {
        let suite = "FormCredentials.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        try ConnectionSignIn(entry: entry, secret: "password", otherSecret: "inactive-key")
            .persist(defaults: defaults, using: keychain, connected: false)
        let form = ConnectionSettingsView(connection: entry, editing: true, defaults: defaults, using: keychain)
        var submitted = try form.signIn(defaults: defaults, using: keychain)
        #expect(submitted.secret == "password")
        #expect(submitted.otherSecret == "inactive-key")
        try submitted.persist(defaults: defaults, using: keychain, connected: false)
        #expect(ConnectionSettingsView(connection: entry, defaults: defaults, using: keychain).keyPEM == "inactive-key")
        submitted.otherSecret = ""
        try submitted.persist(defaults: defaults, using: keychain, connected: false)
        let reopened = ConnectionSettingsView(connection: entry, defaults: defaults, using: keychain)
        #expect(reopened.password == "password")
        #expect(reopened.keyPEM.isEmpty)
    }

    @Test func resolvesSavedPasswordAndPromptsOnlyWhenMissing() throws {
        let keychain = FakeKeychainOperations()
        #expect(try ConnectionSignIn.load(entry, using: keychain).needsSecret)
        try KeychainStore.save("password", account: entry.secretAccount, using: keychain)
        let signIn = try ConnectionSignIn.load(entry, using: keychain)
        #expect(signIn.isReady)
        guard case let .password(value) = signIn.config.auth else { Issue.record("Expected password"); return }
        #expect(value == "password")
    }

    @Test func rememberOffDoesNotReadOldSecret() throws {
        let keychain = FakeKeychainOperations()
        try KeychainStore.save("old", account: entry.secretAccount, using: keychain)
        var profile = entry
        profile.remember = false
        #expect(try ConnectionSignIn.load(profile, using: keychain).needsSecret)
    }

    @Test(arguments: ["host", "port", "username", "auth"])
    func explicitEmptyCredentialClearsSelectedMethodAfterDestinationEdit(field: String) throws {
        let keychain = FakeKeychainOperations()
        let defaults = try #require(UserDefaults(suiteName: "ConnectionEdit.\(UUID())"))
        defer { defaults.removeObject(forKey: RecentConnectionStore.storageKey) }
        try KeychainStore.save("old", account: entry.secretAccount, using: keychain)
        try RecentConnectionStore.record(entry, in: [], defaults: defaults, stampConnected: false)
        try KeychainStore.save("old phrase", account: entry.passphraseAccount, using: keychain)
        var updated = entry
        switch field {
        case "port": updated.port = 2222
        case "username": updated.username = "bob"
        case "auth": updated.authMode = "privateKey"
        default: updated.host = "other.local"
        }
        try ConnectionSignIn(entry: updated).persist(defaults: defaults, using: keychain, connected: false)
        #expect(try RecentConnectionStore.load(defaults: defaults, using: keychain) == [updated])
        #expect(updated.id == entry.id)
        #expect(try KeychainStore.load(account: entry.passphraseAccount, using: keychain) == (field == "auth" ? nil : "old phrase"))
        #expect(try KeychainStore.load(account: updated.secretAccount, using: keychain) == nil)
        if field == "auth" { #expect(try ConnectionSignIn.load(entry, using: keychain).secret == "old") }
    }
}

extension SavedConnectionWorkflowTests {
    @MainActor @Test func classifiesSignInFailuresWithoutHijackingHostTrustOrReadiness() {
        struct AuthenticationFailure: Error {}
        #expect(AppModel.needsSignIn(after: AuthenticationFailure()))
        #expect(AppModel.needsSignIn(after: OpenSSHKeyError.invalidPassphraseOrKey))
        #expect(!AppModel.needsSignIn(after: HerdrError.herdrNotFound))
        #expect(!AppModel.needsSignIn(after: SSHHostKeyStore.StoreError(status: errSecAuthFailed)))
        #expect(!AppModel.needsSignIn(after: CancellationError()))
    }

    @Test func failedAttemptPreservesSavedSecretAndDoesNotRecordReplacement() throws {
        let keychain = FakeKeychainOperations()
        let defaults = try #require(UserDefaults(suiteName: "ConnectionFailure.\(UUID())"))
        defer { defaults.removeObject(forKey: RecentConnectionStore.storageKey) }
        try KeychainStore.save("old", account: entry.secretAccount, using: keychain)
        let pending = ConnectionSignIn(entry: entry, secret: "replacement")
        try pending.prepareAttempt(defaults: defaults, using: keychain)
        #expect(try KeychainStore.load(account: entry.secretAccount, using: keychain) == "old")
        #expect(RecentConnectionStore.snapshot(defaults: defaults).isEmpty)
    }

    @Test func failedPersistenceLeavesProfileVisibleAndRetryable() throws {
        let keychain = FakeKeychainOperations()
        let defaults = try #require(UserDefaults(suiteName: "ConnectionWriteFailure.\(UUID())"))
        defer { defaults.removeObject(forKey: RecentConnectionStore.storageKey) }
        try RecentConnectionStore.record(entry, in: [], defaults: defaults, stampConnected: false)
        keychain.nextAddStatus = errSecInteractionNotAllowed
        #expect(throws: KeychainStore.StoreError.self) {
            try ConnectionSignIn(entry: entry, secret: "replacement").persist(defaults: defaults, using: keychain)
        }
        #expect(RecentConnectionStore.snapshot(defaults: defaults) == [entry])
    }

    @Test func savingPassphraseRequiresSeparateExplicitPreference() throws {
        let keychain = FakeKeychainOperations()
        let defaults = try #require(UserDefaults(suiteName: "ConnectionPassphrase.\(UUID())"))
        defer { defaults.removeObject(forKey: RecentConnectionStore.storageKey) }
        try KeychainStore.save("old phrase", account: entry.passphraseAccount, using: keychain)
        try ConnectionSignIn(entry: entry, secret: "password", passphrase: "phrase").persist(defaults: defaults, using: keychain)
        #expect(try KeychainStore.load(account: entry.passphraseAccount, using: keychain) == nil)
    }
}


extension SavedConnectionWorkflowTests {
    @Test func replayCredentialReadsDoNotWriteKeychain() throws {
        let keychain = FakeKeychainOperations()
        try KeychainStore.save("password", account: entry.secretAccount, using: keychain)
        let adds = keychain.addedAccounts
        #expect(try ConnectionSignIn.load(entry, using: keychain, readOnly: true).isReady)
        #expect(keychain.updatedAccounts.isEmpty)
        #expect(keychain.deletedAccounts.isEmpty)
        #expect(keychain.addedAccounts == adds)
    }
}


extension SavedConnectionWorkflowTests {
    @MainActor @Test(arguments: ["selected", "inactive", "passphrase", "legacy"])
    func failedCredentialReadPreventsDestructiveSettingsSave(field: String) throws {
        let keychain = FakeKeychainOperations()
        try KeychainStore.save("saved", account: entry.secretAccount, using: keychain)
        switch field {
        case "inactive": keychain.failingReadAccount = entry.credentialAccount(for: "privateKey")
        case "passphrase": keychain.failingReadAccount = entry.passphraseAccount
        case "legacy": keychain.failingReadAccount = entry.legacySecretAccount
        default: keychain.failingReadAccount = entry.secretAccount
        }
        let form = ConnectionSettingsView(connection: entry, editing: true, using: keychain)
        #expect(form.credentialLoadError != nil)
        #expect(!form.canSaveChanges)
        #expect(keychain.items[entry.secretAccount] == Data("saved".utf8))
        #expect(keychain.deletedAccounts.isEmpty)
    }
}


extension SavedConnectionWorkflowTests {
    @Test func gearSaveDoesNotStampLastConnected() throws {
        let suite = "GearSave.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        var first = entry
        first.name = "Office"
        let other = RecentConnection(host: "other.local", port: 22, username: "bob", authMode: "password", remember: false)
        let time = Date(timeIntervalSince1970: 12345)
        let seeded = try RecentConnectionStore.record(first, in: [other], defaults: defaults, now: time)
        var edit = seeded[1]
        edit.name = "Work Mac"
        try ConnectionSignIn(entry: edit, secret: "password").persist(defaults: defaults, using: keychain,
            connected: false, updateName: true)
        let saved = try RecentConnectionStore.load(defaults: defaults, using: keychain)
        #expect(saved.map(\.id) == seeded.map(\.id))
        #expect(saved[1].lastConnectedAt == time)
        #expect(saved[1].name == "Work Mac")
    }

    @Test func persistKeepsNameAndPosition() throws {
        let suite = "PersistPosition.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        var saved = entry
        saved.name = "Renamed after opening sign-in"
        let other = RecentConnection(host: "other.local", port: 22, username: "bob", authMode: "password", remember: false)
        let time = Date(timeIntervalSince1970: 100)
        try RecentConnectionStore.record(saved, in: [other], defaults: defaults, now: time)
        try ConnectionSignIn(entry: entry, secret: "password").persist(defaults: defaults, using: keychain, connected: false)
        let result = try RecentConnectionStore.load(defaults: defaults, using: keychain)
        #expect(result.map(\.id) == [other.id, entry.id])
        #expect(result[1].name == saved.name)
        #expect(result[1].lastConnectedAt == time)
    }

    @Test func manageSheetMoveReordersGrid() throws {
        let suite = "ManageMove.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        var first = entry
        first.name = "Work Mac"
        let second = RecentConnection(host: "other.local", port: 22, username: "bob", authMode: "password", remember: false)
        let seeded = try RecentConnectionStore.record(first, in: [second], defaults: defaults)
        let moved = try RecentConnectionStore.move(fromOffsets: IndexSet(integer: 1), toOffset: 0, defaults: defaults, using: keychain)
        #expect(moved == [seeded[1], seeded[0]])
        #expect(RecentConnectionStore.snapshot(defaults: defaults) == moved)
    }
}


extension SavedConnectionWorkflowTests {
    @MainActor @Test func newSetupNameSubmissionUpdatesExistingDestination() throws {
        let suite = "SetupName.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        var previous = entry
        previous.name = "Old name"
        let seeded = try RecentConnectionStore.record(previous, in: [], defaults: defaults)
        var submitted = entry
        submitted.name = "New name"
        submitted.remember = false
        let form = ConnectionSettingsView(connection: submitted, using: keychain)
        let value = try form.signIn(defaults: defaults, using: keychain)
        try value.persist(defaults: defaults, using: keychain, updateName: true)
        let saved = try RecentConnectionStore.load(defaults: defaults, using: keychain)
        #expect(saved.count == 1)
        #expect(saved[0].id == seeded[0].id)
        #expect(saved[0].name == "New name")
    }
}


extension SavedConnectionWorkflowTests {
    @Test func menuCredentialDecisionPromptsForDamagedPrivateKey() throws {
        let keychain = FakeKeychainOperations()
        var saved = entry
        saved.authMode = "privateKey"
        try KeychainStore.save("damaged key", account: saved.secretAccount, using: keychain)
        #expect(RecentConnectionStore.config(for: saved, using: keychain) == nil)
    }
}


extension SavedConnectionWorkflowTests {
    @MainActor @Test func gearSaveWithoutRenameKeepsLatestStoredName() throws {
        let suite = "GearConcurrentName.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        var original = entry
        original.remember = false
        original.name = "Original"
        let form = ConnectionSettingsView(connection: original, editing: true, using: keychain)
        var renamed = original
        renamed.name = "Latest saved name"
        try RecentConnectionStore.record(renamed, in: [], defaults: defaults)
        #expect(!form.nameWasEdited)
        try form.signIn(defaults: defaults, using: keychain).persist(defaults: defaults, using: keychain,
            connected: false, updateName: form.nameWasEdited)
        #expect(RecentConnectionStore.snapshot(defaults: defaults).first?.name == renamed.name)
    }

    @Test func disablingRememberingKeepsLatestNameAndConnectionTimestamp() throws {
        let suite = "RememberMetadata.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        var latest = entry
        latest.name = "Latest"
        let time = Date(timeIntervalSince1970: 54321)
        try RecentConnectionStore.record(latest, in: [], defaults: defaults, now: time)
        var stale = entry
        stale.remember = false
        try ConnectionSignIn(entry: stale).prepareAttempt(defaults: defaults, using: keychain)
        let saved = try #require(RecentConnectionStore.snapshot(defaults: defaults).first)
        #expect(!saved.remember)
        #expect(saved.name == latest.name)
        #expect(saved.lastConnectedAt == time)
    }
}

extension SavedConnectionWorkflowTests {
    @Test func canceledManagementDraftDoesNotWriteOrDeleteCredentials() throws {
        let suite = "ManagementCancel.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let other = RecentConnection(host: "other.local", port: 22, username: "bob", authMode: "password", remember: true)
        let saved = try RecentConnectionStore.record(entry, in: [other], defaults: defaults)
        try KeychainStore.save("secret", account: entry.secretAccount, using: keychain)
        let before = defaults.data(forKey: RecentConnectionStore.storageKey)
        let secrets = keychain.items
        var draft = RecentConnectionStore.ManagementDraft(connections: saved)
        draft.rename(id: entry.id, to: "Unsaved name")
        draft.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        draft.delete(at: IndexSet(integer: 0))
        #expect(defaults.data(forKey: RecentConnectionStore.storageKey) == before)
        #expect(keychain.items == secrets)
        #expect(keychain.deletedAccounts.isEmpty)
    }

    @Test func managementSaveMergesDraftNamesAndOrderIntoCurrentMetadata() throws {
        let suite = "ManagementMerge.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let second = RecentConnection(host: "second.local", port: 22, username: "bob", authMode: "password", remember: true)
        let deleted = RecentConnection(host: "deleted.local", port: 22, username: "cat", authMode: "password", remember: true)
        let saved = try RecentConnectionStore.record(deleted, in: [entry, second], defaults: defaults)
        for item in saved { try KeychainStore.save("secret", account: item.secretAccount, using: keychain) }
        for account in deleted.credentialAccounts { try KeychainStore.save("secret", account: account, using: keychain) }
        var draft = RecentConnectionStore.ManagementDraft(connections: saved)
        draft.rename(id: entry.id, to: "Draft name")
        draft.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        draft.delete(at: IndexSet(integer: 2))
        var fresh = entry
        fresh.host = "edited.local"
        fresh.port = 2222
        fresh.username = "new-user"
        fresh.authMode = "privateKey"
        fresh.remember = false
        let stamp = Date(timeIntervalSince1970: 54321)
        var current = try RecentConnectionStore.record(fresh, in: saved, defaults: defaults, now: stamp)
        var renamedSecond = second
        renamedSecond.name = "External rename"
        current = try RecentConnectionStore.record(renamedSecond, in: current, defaults: defaults, stampConnected: false)
        let added = RecentConnection(host: "new.local", port: 22, username: "new", authMode: "password", remember: false)
        _ = try RecentConnectionStore.record(added, in: current, defaults: defaults, stampConnected: false)
        let survivorSecret = keychain.items[entry.secretAccount]
        keychain.addedAccounts = []
        let result = try draft.save(defaults: defaults, using: keychain)
        #expect(result.map(\.id) == [second.id, entry.id, added.id])
        fresh.name = "Draft name"
        fresh.lastConnectedAt = stamp
        #expect(result[1] == fresh)
        #expect(result[0].name == "External rename")
        #expect(keychain.items[entry.secretAccount] == survivorSecret)
        for account in deleted.credentialAccounts { #expect(keychain.items[account] == nil) }
        #expect(keychain.addedAccounts.isEmpty)
        #expect(Set(keychain.deletedAccounts) == Set(deleted.credentialAccounts))
    }

    @Test func managementSaveFailureLeavesMetadataForRetry() throws {
        let suite = "ManagementFailure.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let saved = try RecentConnectionStore.record(entry, in: [], defaults: defaults)
        try KeychainStore.save("secret", account: entry.secretAccount, using: keychain)
        let before = defaults.data(forKey: RecentConnectionStore.storageKey)
        var draft = RecentConnectionStore.ManagementDraft(connections: saved)
        draft.delete(at: IndexSet(integer: 0))
        keychain.nextDeleteStatus = errSecInteractionNotAllowed
        #expect(throws: KeychainStore.StoreError.self) { try draft.save(defaults: defaults, using: keychain) }
        #expect(defaults.data(forKey: RecentConnectionStore.storageKey) == before)
        #expect(keychain.items[entry.secretAccount] != nil)
        #expect(try draft.save(defaults: defaults, using: keychain).isEmpty)
    }
}
