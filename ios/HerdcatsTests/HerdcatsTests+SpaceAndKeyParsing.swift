import Crypto
import Foundation
import Security
import NIOSSH
import SwiftUI
import Testing
import UIKit
@testable import Herdcats

@Suite("Space join and status ranking")
struct SpaceJoinTests {
    @Test
    func joinsAgentsIntoSpacesAndSortsByNumber() throws {
        let workspaces = try HerdrConnection.decode(workspaceListJSON, as: WorkspaceListResult.self).workspaces
        let agents = try HerdrConnection.decode(agentListJSON, as: AgentListResult.self).agents

        let spaces = Space.join(workspaces: workspaces, agents: agents)
        #expect(spaces.map(\.workspace.number) == [1, 2, 3])

        let herdrcat = try #require(spaces.first { $0.id == "w4H" })
        #expect(herdrcat.agents.count == 1)
        #expect(herdrcat.agents.first?.agent == "pi")
        // lone working agent -> working
        #expect(herdrcat.status == .working)

        let samplenotes = try #require(spaces.first { $0.id == "w4" })
        // idle + blocked -> blocked is more attention-worthy
        #expect(samplenotes.status == .blocked)

        let samplemedia = try #require(spaces.first { $0.id == "w32" })
        // No agents: falls back to the workspace-level status
        #expect(samplemedia.status == .idle)
    }

    @Test
    func statusRankingMatchesHerdrAttentionPriority() {
        // Same order herdr uses for its priority agent panel and workspace
        // rollup: blocked > done > working > idle > unknown.
        #expect(AgentStatus.blocked.attentionPriority > AgentStatus.done.attentionPriority)
        #expect(AgentStatus.done.attentionPriority > AgentStatus.working.attentionPriority)
        #expect(AgentStatus.working.attentionPriority > AgentStatus.idle.attentionPriority)
        #expect(AgentStatus.idle.attentionPriority > AgentStatus.unknown.attentionPriority)
    }

    @Test
    func priorityOrderingRanksSpaceGroupsLikeAgents() throws {
        let workspaces = try HerdrConnection.decode(workspaceListJSON, as: WorkspaceListResult.self).workspaces
        let agents = try HerdrConnection.decode(agentListJSON, as: AgentListResult.self).agents
        let groups = SpaceGroup.group(Space.join(workspaces: workspaces, agents: agents))

        #expect(groups.sorted(by: SpaceGroup.attentionOrder).map(\.root.id) == ["w4", "w4H", "w32"])
    }
}

// MARK: - Space grouping

@Suite("Space creation presentation")
struct SpaceCreationPresentationTests {
    @Test func showsCreatedWorkspaceUntilRefreshAndNeverDuplicatesIt() {
        let created = Workspace(
            workspaceId: "created",
            label: "New space",
            number: 2,
            tabCount: 1,
            paneCount: 1,
            activeTabId: "tab-created",
            agentStatus: "idle",
            focused: false,
            worktree: nil
        )
        let existing = Workspace(
            workspaceId: "existing",
            label: "Existing space",
            number: 1,
            tabCount: 1,
            paneCount: 1,
            activeTabId: "tab-existing",
            agentStatus: "idle",
            focused: false,
            worktree: nil
        )
        let listed = Space.join(workspaces: [existing], agents: [])
        let unconfirmed = Space(workspace: created, agents: [])
        #expect(SpacePresentationOverlay.visibleSpaces([], unconfirmed: [unconfirmed]).map(\.id) == ["created"])
        #expect(SpaceGroup.group(SpacePresentationOverlay.visibleSpaces(listed, unconfirmed: [unconfirmed]))
            .map(\.root.id) == ["existing", "created"])

        let refreshed = Space.join(workspaces: [existing, created], agents: [])
        #expect(SpacePresentationOverlay.visibleSpaces(refreshed, unconfirmed: [unconfirmed]).map(\.id)
            == ["existing", "created"])
        #expect(SpacePresentationOverlay.unconfirmed([unconfirmed], after: refreshed).isEmpty)
    }
}

@Suite("Worktree presentation")
struct WorktreePresentationTests {
    @Test func returnedWorkspaceWithoutWorktreeMetadataStaysUnderItsSourceCard() {
        let sourceWorkspace = Workspace(
            workspaceId: "root",
            label: "Repository",
            number: 1,
            tabCount: 1,
            paneCount: 1,
            activeTabId: "root-tab",
            agentStatus: "idle",
            focused: false,
            worktree: Worktree(
                checkoutPath: "/repo",
                repoName: "repo",
                repoRoot: "/repo",
                isLinkedWorktree: false
            )
        )
        let source = Space(workspace: sourceWorkspace, agents: [])
        let returnedWorkspace = Workspace(
            workspaceId: "linked",
            label: "Feature",
            number: 2,
            tabCount: 1,
            paneCount: 1,
            activeTabId: "linked-tab",
            agentStatus: "idle",
            focused: false,
            worktree: nil
        )
        let entry = WorktreeEntry(
            path: "/repo-feature",
            branch: "feature",
            label: nil,
            isBare: false,
            isDetached: false,
            isLinkedWorktree: true,
            isPrunable: false,
            openWorkspaceId: "linked"
        )
        let presented = WorktreePresentation.space(returnedWorkspace, entry: entry, source: source)
        #expect(presented.workspace.worktree?.repoRoot == "/repo")
        let groups = SpaceGroup.group(SpacePresentationOverlay.visibleSpaces([source], unconfirmed: [presented]))
        #expect(groups.count == 1)
        #expect(groups[0].worktrees.map(\.id) == [presented.id])
        #expect(SpacePresentationOverlay.visibleSpaces([source, presented], unconfirmed: [presented]).count == 2)
        #expect(SpacePresentationOverlay.unconfirmed([presented], after: [source, presented]).isEmpty)
    }

    @Test func pendingTitlesReflectTheChosenAction() {
        #expect(PendingWorktreeAction.openTitle(path: "/repo/feature", branch: nil)
            == "Opening worktree “feature”…")
        #expect(PendingWorktreeAction.createTitle(name: nil, label: nil) == "Creating worktree…")
        #expect(PendingWorktreeAction.createTitle(name: "feature", label: "My Feature")
            == "Creating worktree “My Feature”…")
    }
}

@Suite("Space grouping by repo root")
struct SpaceGroupTests {
    func groupsFromFixture() throws -> [SpaceGroup] {
        let workspaces = try HerdrConnection
            .decode(workspaceListWithWorktreesJSON, as: WorkspaceListResult.self)
            .workspaces
        return SpaceGroup.group(Space.join(workspaces: workspaces, agents: []))
    }

    @Test
    func foldsLinkedWorktreesUnderTheirRoot() throws {
        let groups = try groupsFromFixture()

        // Roots and standalone spaces only — linked worktrees never get a card.
        #expect(groups.map(\.root.id) == ["w4", "w32", "w35", "w4C"])

        let samplenotes = try #require(groups.first { $0.root.id == "w4" })
        #expect(samplenotes.worktrees.map(\.id) == ["w36", "w48"])

        let sampleshop = try #require(groups.first { $0.root.id == "w35" })
        #expect(sampleshop.worktrees.map(\.id) == ["w3W"])

        // No worktree — stays standalone.
        let samplemedia = try #require(groups.first { $0.root.id == "w32" })
        #expect(samplemedia.worktrees.isEmpty)
    }

    @Test
    func promotesFirstLinkedWorktreeWhenNoRootExists() throws {
        let groups = try groupsFromFixture()

        // Only linked worktrees exist for the orphan repo — the first becomes
        // the card so the group is still visible.
        let orphan = try #require(groups.first { $0.root.id == "w4C" })
        #expect(orphan.worktrees.map(\.id) == ["w4E"])
    }

    @Test
    func groupStatusAggregatesAcrossWorktrees() throws {
        let groups = try groupsFromFixture()

        // samplenotes: idle root + blocked linked worktree -> blocked.
        let samplenotes = try #require(groups.first { $0.root.id == "w4" })
        #expect(samplenotes.status == .blocked)

        // sampleshop: idle root + working linked worktree -> working, and
        // focus inside a worktree highlights the whole group.
        let sampleshop = try #require(groups.first { $0.root.id == "w35" })
        #expect(sampleshop.status == .working)
        #expect(sampleshop.isFocused == true)
        #expect(samplenotes.isFocused == false)
    }
}

// MARK: - OpenSSH key parsing

@Suite("OpenSSH ed25519 key parsing")
struct OpenSSHKeyParserTests {
    /// Throwaway key generated for this test suite only.
    private static let unencryptedPEM = OpenSSHParserFixture.pem

    private static let encrypted16 = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABCbXkJg7L
    Fx6WjNp/Gz9nRnAAAAEAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIJL3ixoEfPqABvBN
    wlMfi4z+ckv1WNZQo00MhyOR1nIEAAAAoOncXPrbrVC9rQnwN68X6PY3tzllHQb96vnoLf
    nKt7e66Trh4TFW5j0hkPJyt0euwiyYbQo9sS9jw9bPtNhcRzIevywyKo1MYrbxZ34KQW/J
    CTRpH1sDxVQii5mP8bCmyoJ3xcrzaWgID97uA9YovHU7rEBmqjMH8pmDZCXOtw/KPYLGlp
    5lBqqP/9o4oCfWXFaP1V8ZT+jolVYSNdUC0TQ=
    -----END OPENSSH PRIVATE KEY-----
    """
    private static let encrypted32 = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABBY0sytrK
    GA6SISkuAEnnY6AAAAIAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIIHrV7DrXLWaVn6j
    JCmh4T6LOtDY4KVB7FL4OXJl34hhAAAAoCRsT/xm/r8VwGQqwE+I5AfBc7uwR5QlC2L+ld
    d5H54B7lFod3Qbw7OfySl30hTx0TvKznw30MI+Cz9SSkNmji/piPRFs4F1tPACwqTQiI25
    jopJD5XKlYHQ+FkVWctVQkLuS1qC+qAoa39ln/lcrMY2H6V7Qyj/EMe3uIrmbAGYM4CkbG
    lbLQp51lgCG/Pc4See3yz8SBbXIXbpkppdWls=
    -----END OPENSSH PRIVATE KEY-----
    """
    private static let encrypted64 = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABBQsNNQDE
    3OeNlbiirYuF51AAAAQAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIEHiHx4Brcpqh9OW
    lY7YKkM3HN1yOFbJNYbUClrT7q+MAAAAoPXvIQDoTJK/XrKBIF2kuCD9KIPYTstdeLIEcI
    heoaAWhTJoeN0uixLdLK2E0qnaOA4teelJmrqntGC3kaWAOknVv7UPGceybXd82nYykl/s
    xiPxdhHmIcm/mO6Bw1Cve9cJZF6k2sd0EBzfwnaFImLcSF3oL/T6Cf/JS6vTFOWHjh+anc
    1Jzhj402WYisxnyveuTPZGidiF24UyVUEMyEs=
    -----END OPENSSH PRIVATE KEY-----
    """
    private static let encryptedFullPadding = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABA67fmC6c588ccWKTA+gjakAAAAIAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIGQrPTgKc2Tjmng/nP1vdbdEG1R97z6O8gsc+bO1lHoWAAAAoHplRLWrpysjRVDkBaZSvn+5etGE2KV7W0HRbLtyHkB+ikdsAD0xhIbdIzeV31ckY055SDLBqiUb9oOQbzAxrHlcdc2ydF/nWc/vv/VckXWwDxCqIbr+8dxqt0aZ0FNNwtbpiEcorhvhz1KET+O0lqVWSrMhAU0l26S0PoqtFWOFnJKyZ8Vxu/EFNhOJJHpX4Ks7Giyw1bVlMi3xrN8lrhI=
    -----END OPENSSH PRIVATE KEY-----
    """
    /// encrypted64 re-encrypted with a different passphrase; its public key is unchanged.
    private static let reencrypted64 = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABAsedH76b
    l2rp2g2PjB0emZAAAAEAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIEHiHx4Brcpqh9OW
    lY7YKkM3HN1yOFbJNYbUClrT7q+MAAAAoMoEdE2pfeGlVMQiqomAI3eMqgp+6/mT8DNZDA
    XipTHK48vdkReqHSaPFC9D1PWuEpHgwkVFGRHdI2gEDnUj36U5XETaGZmRmw+ML4I8vIhv
    k+Twu5T6RBXBVLiFQgSuyAh/JAUESuYIi0QdMVTAi115InelAeetviVnsfjyAHFxH8SMUS
    zVVodm/6GIRyPBubRLr8zsy8rRuANhShpnX5k=
    -----END OPENSSH PRIVATE KEY-----
    """
    private static let encrypted256 = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczEyOC1jdHIAAAAGYmNyeXB0AAAAGAAAABCAZBE4rD
    GCia9qfNiUzHkCAAABAAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIMTvWynpLNkXUBjf
    Nf4cZ/jd18DuIsMlR5uS8EQWsvaOAAAAoJVICIyrMT/au68JOgwscoUFx6QeumnNNjtcRA
    MIOVoTAAYhUf5MN0bWqGex1L4SHUko9OuekkCPnXK83G/cc/yeThLoxtZQehdJZO/v25fV
    8135ra4Q4lu7diODsZEQNnTK/WXA/M5C4zk77QNwjp16RElsKf5vaq2F740JYGqAC3BroD
    uRbhBLh+7+GeZBW+mZQSBsmKIG72CzaFiCR4o=
    -----END OPENSSH PRIVATE KEY-----
    """
    @Test
    func parsesUnencryptedEd25519Key() throws {
        let raw = try OpenSSHEd25519.parseRawPrivateKey(pem: Self.unencryptedPEM)
        // CryptoKit exposes the 32-byte ed25519 seed.
        #expect(raw.count == 32)

        // The embedded public key must match the known fixture public key
        // (authorized_keys blob: "ssh-ed25519" string + 32 raw bytes).
        let blob = Data(base64Encoded: OpenSSHParserFixture.publicKeyLine.split(separator: " ").last.map(String.init) ?? "")
        #expect(blob?.count == 51)
        #expect(try OpenSSHEd25519.parsePublicKey(pem: Self.unencryptedPEM) == blob?.suffix(32))
    }

    @Test
    func unlocksEncryptedKeysAboveOldRoundLimit() throws {
        for pem in [Self.encrypted16, Self.encrypted32, Self.encrypted64, Self.encrypted256, Self.encryptedFullPadding] {
            #expect(try OpenSSHEd25519.isEncrypted(pem: pem))
            let raw = try OpenSSHEd25519.parseRawPrivateKey(pem: pem, passphrase: "herdcats-test-passphrase")
            #expect(raw.count == 32)
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
            #expect(key.publicKey.rawRepresentation == (try OpenSSHEd25519.parsePublicKey(pem: pem)))
            #expect(throws: OpenSSHKeyError.passphraseRequired) {
                _ = try OpenSSHEd25519.parseRawPrivateKey(pem: pem)
            }
            #expect(throws: OpenSSHKeyError.invalidPassphraseOrKey) {
                _ = try OpenSSHEd25519.parseRawPrivateKey(pem: pem, passphrase: "wrong")
            }
        }
    }

    @Test
    func rejectsCorruptedFinalPaddingByte() throws {
        let body = Self.encryptedFullPadding.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        var bytes = try #require(Data(base64Encoded: body))
        bytes[bytes.count - 1] ^= 1
        let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n" + bytes.base64EncodedString() + "\n-----END OPENSSH PRIVATE KEY-----"
        #expect(throws: OpenSSHKeyError.invalidPassphraseOrKey) {
            _ = try OpenSSHEd25519.parseRawPrivateKey(pem: pem, passphrase: "herdcats-test-passphrase")
        }
    }

    @MainActor
    @Test
    func connectionFormRejectsDamagedUnencryptedPrivateMaterial() throws {
        let body = Self.unencryptedPEM.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        let bytes = try #require(Data(base64Encoded: body))
        var offset = 15
        func skipString() {
            let length = bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
            offset += 4 + length
        }
        for _ in 0..<3 { skipString() }
        offset += 4 // number of keys
        skipString() // outer public key
        let privateStart = offset + 4
        var badChecks = bytes
        badChecks[privateStart + 4] ^= 1
        var mismatchedPublicKey = bytes
        mismatchedPublicKey[offset - 1] ^= 1
        offset = privateStart + 8 // check integers
        skipString() // key type
        let innerPublicStart = offset + 4
        skipString() // public key inside private section
        let seedStart = offset + 4
        var corruptedSeed = bytes
        corruptedSeed[seedStart] ^= 1
        var mismatchedInnerPublicKey = bytes
        mismatchedInnerPublicKey[innerPublicStart] ^= 1
        let truncated = Data(bytes.prefix(privateStart + 12))
        let entry = RecentConnection(host: "fixture.example", port: 22,
            username: "tester", authMode: "privateKey", remember: true)
        defer { try? KeychainStore.delete(account: entry.secretAccount) }
        for damaged in [truncated, badChecks, mismatchedPublicKey, corruptedSeed, mismatchedInnerPublicKey] {
            let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n" + damaged.base64EncodedString() + "\n-----END OPENSSH PRIVATE KEY-----"
            // Each retains a readable outer public key.
            _ = try OpenSSHEd25519.parsePublicKey(pem: pem)
            #expect(throws: OpenSSHKeyError.self) {
                _ = try OpenSSHEd25519.parseRawPrivateKey(pem: pem)
            }
            try KeychainStore.save(pem, account: entry.secretAccount)
            let form = ConnectionSettingsView(connection: entry)
            #expect(form.keyValidationError != nil)
            #expect(form.derivedPublicKey == nil)
            #expect(!form.canConnect)
        }
        try KeychainStore.save(Self.unencryptedPEM, account: entry.secretAccount)
        let validForm = ConnectionSettingsView(connection: entry)
        #expect(validForm.keyValidationError == nil)
        #expect(validForm.derivedPublicKey == OpenSSHParserFixture.publicKeyLine)
        #expect(validForm.canConnect)
    }

    @Test func directPathPromptsOnlyForMissingEncryptedPassphrase() throws {
        let entry = RecentConnection(host: "fixture.example", port: 22,
            username: "tester", authMode: "privateKey", remember: true)
        let keychain = FakeKeychainOperations()
        try KeychainStore.save(Self.encrypted64, account: entry.secretAccount, using: keychain)
        let locked = try ConnectionSignIn.load(entry, using: keychain)
        #expect(!locked.needsSecret)
        #expect(locked.needsPassphrase)
        #expect(!locked.isReady)
        try KeychainStore.save("phrase", account: entry.passphraseAccount, using: keychain)
        #expect(try ConnectionSignIn.load(entry, using: keychain).isReady)
    }

    @Test func encryptedPassphraseIsSavedOnlyWithExplicitPreference() throws {
        let suite = "EncryptedSignIn.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let entry = RecentConnection(host: "fixture.example", port: 22,
            username: "tester", authMode: "privateKey", remember: true)
        let keychain = FakeKeychainOperations()
        var value = ConnectionSignIn(entry: entry, secret: Self.encrypted64, passphrase: "phrase")
        try value.persist(defaults: defaults, using: keychain)
        #expect(try KeychainStore.load(account: entry.passphraseAccount, using: keychain) == nil)
        value.savePassphrase = true
        try value.persist(defaults: defaults, using: keychain)
        #expect(try KeychainStore.load(account: entry.passphraseAccount, using: keychain) == "phrase")
        #expect(try RecentConnectionStore.load(defaults: defaults, using: keychain).map(\.id) == [entry.id])
        #expect(try RecentConnectionStore.load(defaults: defaults, using: keychain).first?.lastConnectedAt != nil)
    }

    @MainActor @Test func savedKeyAndPassphraseSurvivePasswordAuthentication() throws {
        let suite = "InactiveKeyPassphrase.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let keyed = RecentConnection(host: "fixture.example", port: 22, username: "tester", authMode: "privateKey", remember: true)
        try ConnectionSignIn(entry: keyed, secret: Self.encrypted64, passphrase: "saved-phrase", savePassphrase: true)
            .persist(defaults: defaults, using: keychain)
        var passwordEntry = keyed
        passwordEntry.authMode = "password"
        try ConnectionSignIn(entry: passwordEntry, secret: "password", passphrase: "saved-phrase", savePassphrase: true)
            .persist(defaults: defaults, using: keychain, connected: false)
        let form = ConnectionSettingsView(connection: passwordEntry, defaults: defaults, using: keychain)
        #expect(form.password == "password")
        #expect(form.keyPEM == Self.encrypted64)
        #expect(form.keyPassphrase == "saved-phrase")
        #expect(form.rememberPassphrase)
        let reopened = try ConnectionSignIn.load(keyed, using: keychain)
        #expect(reopened.secret == Self.encrypted64)
        #expect(reopened.passphrase == "saved-phrase")
    }

    @MainActor @Test(arguments: ["saved-card", "settings"])
    func passwordRecoveryPreservesInactivePassphraseUnlessSettingsExplicitlyClearIt(submission: String) throws {
        let suite = "PasswordRecoveryPassphrase.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let keyed = RecentConnection(host: "fixture.example", port: 22, username: "tester", authMode: "privateKey", remember: true)
        try ConnectionSignIn(entry: keyed, secret: Self.encrypted64, passphrase: "saved-phrase", savePassphrase: true)
            .persist(defaults: defaults, using: keychain)
        var passwordEntry = keyed
        passwordEntry.authMode = "password"
        try ConnectionSignIn(entry: passwordEntry, secret: "rejected-password")
            .persist(defaults: defaults, using: keychain, connected: false)
        var recovery: ConnectionSignIn
        if submission == "settings" {
            recovery = try ConnectionSettingsView(connection: passwordEntry, editing: true, defaults: defaults, using: keychain)
                .signIn(defaults: defaults, using: keychain)
        } else {
            recovery = try ConnectionSignIn.load(passwordEntry, using: keychain)
        }
        // SavedConnectionSignInView resets these fields when a rejected password is edited.
        // In settings, the same values represent an explicit passphrase removal and opt-out.
        recovery.secret = "corrected-password"
        recovery.passphrase = ""
        recovery.savePassphrase = false
        try recovery.persist(defaults: defaults, using: keychain)
        #expect(try ConnectionSignIn.load(passwordEntry, using: keychain).secret == "corrected-password")
        let reopenedKey = try ConnectionSignIn.load(keyed, using: keychain)
        #expect(reopenedKey.secret == Self.encrypted64)
        #expect(reopenedKey.passphrase == (submission == "settings" ? "" : "saved-phrase"))
        #expect(reopenedKey.needsPassphrase == (submission == "settings"))
    }

    @MainActor @Test(arguments: ["password", "privateKey"])
    func newFormReusingSavedDestinationPreservesUnloadedCredentials(authMode: String) throws {
        let suite = "NewFormExistingCredentials.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let savedMode = authMode == "password" ? "privateKey" : "password"
        let saved = RecentConnection(host: "fixture.example", port: 22, username: "tester", authMode: savedMode, remember: true)
        try ConnectionSignIn(entry: saved, secret: savedMode == "password" ? "saved-password" : Self.encrypted64,
            passphrase: savedMode == "privateKey" ? "saved-phrase" : "", savePassphrase: savedMode == "privateKey")
            .persist(defaults: defaults, using: keychain)
        // A new form has its own ID and has never loaded the matching saved profile's fields.
        let enteredDestination = RecentConnection(host: saved.host, port: saved.port, username: saved.username,
            authMode: authMode, remember: true)
        let form = ConnectionSettingsView(connection: enteredDestination, defaults: defaults, using: keychain)
        #expect(form.password.isEmpty && form.keyPEM.isEmpty && form.keyPassphrase.isEmpty)
        var submitted = try form.signIn(defaults: defaults, using: keychain)
        #expect(submitted.entry.id == saved.id)
        // Supply the selected credential, leaving the inactive form field unhydrated.
        submitted.secret = authMode == "password" ? "new-password" : Self.unencryptedPEM
        try submitted.persist(defaults: defaults, using: keychain)
        let reopened = ConnectionSettingsView(connection: submitted.entry, editing: true, defaults: defaults, using: keychain)
        #expect(reopened.password == (authMode == "password" ? "new-password" : "saved-password"))
        #expect(reopened.keyPEM == (authMode == "privateKey" ? Self.unencryptedPEM : Self.encrypted64))
        #expect(reopened.keyPassphrase == (authMode == "password" ? "saved-phrase" : ""))
        #expect(reopened.rememberPassphrase == (authMode == "password"))
    }

    @MainActor @Test(arguments: ["selected", "server", "resolved", "sibling", "detected"], [false, true])
    func runtimeSavesPreserveUneditedSiblingKeyAndPassphrase(path: String, sourceHasKey: Bool) throws {
        let suite = "RuntimeCredentialOwnership.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let tui = RecentConnection(host: "fixture.example", port: 22, username: "tester", authMode: "password", remember: true)
        let core = RecentConnection(host: tui.host, port: tui.port, username: tui.username, authMode: "password", remember: true, backend: .core)
        try ConnectionSignIn(entry: tui, secret: "password", otherSecret: sourceHasKey ? Self.encrypted64 : nil)
            .persist(defaults: defaults, using: keychain)
        try ConnectionSignIn(entry: core, secret: "password", passphrase: "core-phrase", savePassphrase: true, otherSecret: Self.encrypted64)
            .persist(defaults: defaults, using: keychain)
        let form = ConnectionSettingsView(connection: tui, editing: true, defaults: defaults, using: keychain)
        #expect(form.backend == nil)
        #expect(form.keyPassphrase.isEmpty)
        var submitted = try form.signIn(defaults: defaults, using: keychain)
        switch path {
        case "selected":
            // The runtime picker targets the sibling ID without loading its fields.
            submitted.entry.id = core.id
            submitted.entry.backend = .core
            try submitted.persist(defaults: defaults, using: keychain, connected: false)
        case "server":
            submitted.entry.name = "Renamed server"
            try submitted.persistServer(from: tui, defaults: defaults, using: keychain, updateName: true)
        case "resolved":
            try submitted.resolving(.core, in: [tui, core]).persist(defaults: defaults, using: keychain)
        case "sibling":
            try submitted.persistSibling(.core, defaults: defaults, using: keychain)
        default:
            try submitted.persistDetected(backend: .core, found: [.tui, .core], defaults: defaults, using: keychain)
        }
        let reopened = ConnectionSettingsView(connection: core, editing: true, defaults: defaults, using: keychain)
        #expect(reopened.keyPEM == Self.encrypted64)
        #expect(reopened.keyPassphrase == "core-phrase")
        #expect(reopened.rememberPassphrase)
        let source = ConnectionSettingsView(connection: tui, editing: true, defaults: defaults, using: keychain)
        #expect(source.keyPEM == (sourceHasKey ? Self.encrypted64 : ""))
        #expect(source.keyPassphrase.isEmpty)
    }

    @MainActor @Test(arguments: ["selected", "server", "resolved", "sibling", "detected"])
    func runtimeSavesPreserveUnloadedSiblingPassword(path: String) throws {
        let suite = "RuntimePasswordOwnership.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let tui = RecentConnection(host: "fixture.example", port: 22, username: "tester", authMode: "password", remember: true)
        let core = RecentConnection(host: tui.host, port: tui.port, username: tui.username, authMode: "password", remember: true, backend: .core)
        try ConnectionSignIn(entry: tui).persist(defaults: defaults, using: keychain)
        try ConnectionSignIn(entry: core, secret: "core-password").persist(defaults: defaults, using: keychain)
        let form = ConnectionSettingsView(connection: tui, editing: true, defaults: defaults, using: keychain)
        #expect(form.password.isEmpty)
        #expect(form.canSaveChanges)
        var submitted = try form.signIn(defaults: defaults, using: keychain)
        switch path {
        case "selected":
            submitted.entry.id = core.id
            submitted.entry.backend = .core
            try submitted.persist(defaults: defaults, using: keychain, connected: false)
        case "server":
            try submitted.persistServer(from: tui, defaults: defaults, using: keychain, updateName: true)
        case "resolved":
            try submitted.resolving(.core, in: [tui, core]).persist(defaults: defaults, using: keychain)
        case "sibling":
            try submitted.persistSibling(.core, defaults: defaults, using: keychain)
        default:
            try submitted.persistDetected(backend: .core, found: [.tui, .core], defaults: defaults, using: keychain)
        }
        #expect(try ConnectionSignIn.load(core, using: keychain).secret == "core-password")
        #expect(try ConnectionSignIn.load(tui, using: keychain).secret.isEmpty)
    }

    @MainActor @Test(arguments: ["selected", "server", "resolved", "sibling", "detected"])
    func runtimeSavesPreserveSiblingRememberPreference(path: String) throws {
        let suite = "RuntimeRememberOwnership.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let tui = RecentConnection(host: "fixture.example", port: 22, username: "tester", authMode: "password", remember: false)
        let core = RecentConnection(host: tui.host, port: tui.port, username: tui.username, authMode: "password", remember: true, backend: .core)
        try ConnectionSignIn(entry: tui).persist(defaults: defaults, using: keychain)
        try ConnectionSignIn(entry: core, secret: "core-password", passphrase: "core-phrase", savePassphrase: true, otherSecret: Self.encrypted64)
            .persist(defaults: defaults, using: keychain)
        let form = ConnectionSettingsView(connection: tui, editing: true, defaults: defaults, using: keychain)
        #expect(!form.remember)
        var submitted = try form.signIn(defaults: defaults, using: keychain)
        switch path {
        case "selected":
            submitted.entry.id = core.id
            submitted.entry.backend = .core
            try submitted.prepareAttempt(defaults: defaults, using: keychain)
            try submitted.persist(defaults: defaults, using: keychain, connected: false)
        case "server":
            try submitted.persistServer(from: tui, defaults: defaults, using: keychain, updateName: true)
        case "resolved":
            let resolved = submitted.resolving(.core, in: [tui, core])
            try resolved.prepareAttempt(defaults: defaults, using: keychain)
            try resolved.persist(defaults: defaults, using: keychain)
        case "sibling":
            try submitted.persistSibling(.core, defaults: defaults, using: keychain)
        default:
            try submitted.persistDetected(backend: .core, found: [.tui, .core], defaults: defaults, using: keychain)
        }
        let savedCore = try #require(RecentConnectionStore.snapshot(defaults: defaults).first { $0.id == core.id })
        #expect(savedCore.remember)
        let reopened = ConnectionSettingsView(connection: savedCore, editing: true, defaults: defaults, using: keychain)
        #expect(reopened.password == "core-password")
        #expect(reopened.keyPEM == Self.encrypted64)
        #expect(reopened.keyPassphrase == "core-phrase")
        #expect(reopened.rememberPassphrase)
    }

    @MainActor @Test(arguments: ["selected", "server", "sibling"], ["password", "key", "phrase", "remember"])
    func explicitEditsCanClearSiblingCredentials(path: String, field: String) throws {
        let suite = "ExplicitRuntimeCredentialEdits.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let tui = RecentConnection(host: "fixture.example", port: 22, username: "tester", authMode: "password", remember: true)
        let core = RecentConnection(host: tui.host, port: tui.port, username: tui.username, authMode: "password", remember: true, backend: .core)
        try ConnectionSignIn(entry: tui).persist(defaults: defaults, using: keychain)
        try ConnectionSignIn(entry: core, secret: "core-password", passphrase: "core-phrase", savePassphrase: true, otherSecret: Self.encrypted64)
            .persist(defaults: defaults, using: keychain)
        var submitted = try ConnectionSettingsView(connection: tui, editing: true, defaults: defaults, using: keychain)
            .signIn(defaults: defaults, using: keychain)
        // These flags come from the form's field bindings, including an edit
        // back to empty when the source runtime never had a saved value.
        switch field {
        case "password": submitted.credentialEdits?.password = true
        case "key": submitted.credentialEdits?.privateKey = true
        case "phrase": submitted.credentialEdits?.passphrase = true
        default:
            submitted.entry.remember = false
            submitted.credentialEdits?.remember = true
        }
        switch path {
        case "selected":
            submitted.entry.id = core.id
            submitted.entry.backend = .core
            try submitted.prepareAttempt(defaults: defaults, using: keychain)
            try submitted.persist(defaults: defaults, using: keychain, connected: false)
        case "server":
            try submitted.persistServer(from: tui, defaults: defaults, using: keychain, updateName: false)
        default:
            try submitted.persistSibling(.core, defaults: defaults, using: keychain)
        }
        #expect(try KeychainStore.load(account: core.secretAccount, using: keychain)
            == (["password", "remember"].contains(field) ? nil : "core-password"))
        #expect(try KeychainStore.load(account: core.credentialAccount(for: "privateKey"), using: keychain)
            == (["key", "remember"].contains(field) ? nil : Self.encrypted64))
        #expect(try KeychainStore.load(account: core.passphraseAccount, using: keychain)
            == (["key", "phrase", "remember"].contains(field) ? nil : "core-phrase"))
        #expect(RecentConnectionStore.snapshot(defaults: defaults).first { $0.id == core.id }?.remember == (field != "remember"))
    }

    @MainActor @Test(arguments: ["password", "privateKey"], ["owner", "sibling", "server"])
    func explicitlyRemovingKeyDeletesPersistedPassphraseButKeepsDraft(authMode: String, path: String) throws {
        let suite = "RemovedKeyPassphrase.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let tui = RecentConnection(host: "fixture.example", port: 22, username: "tester", authMode: authMode, remember: true)
        let core = RecentConnection(host: tui.host, port: tui.port, username: tui.username, authMode: authMode, remember: true, backend: .core)
        for phrase in ["saved-phrase", "unsaved-phrase-draft"] {
            for (runtime, password) in [(tui, "tui-password"), (core, "core-password")] {
                try ConnectionSignIn(entry: runtime, secret: authMode == "privateKey" ? Self.encrypted64 : password,
                    passphrase: "saved-phrase", savePassphrase: true,
                    otherSecret: authMode == "privateKey" ? password : Self.encrypted64)
                    .persist(defaults: defaults, using: keychain)
            }
            var submitted = try ConnectionSettingsView(connection: tui, editing: true, defaults: defaults, using: keychain)
                .signIn(defaults: defaults, using: keychain)
            if authMode == "privateKey" { submitted.secret = "" }
            else { submitted.otherSecret = "" }
            submitted.credentialEdits?.privateKey = true
            submitted.passphrase = phrase
            submitted.savePassphrase = true
            switch path {
            case "owner":
                try submitted.persist(defaults: defaults, using: keychain, connected: false)
            case "sibling":
                try submitted.persistSibling(.core, defaults: defaults, using: keychain)
            default:
                try submitted.persistServer(from: tui, defaults: defaults, using: keychain, updateName: false)
            }
            let affected = path == "owner" ? [tui] : path == "sibling" ? [core] : [tui, core]
            for runtime in affected {
                #expect(try KeychainStore.load(account: runtime.credentialAccount(for: "privateKey"), using: keychain) == nil)
                #expect(try KeychainStore.load(account: runtime.passphraseAccount, using: keychain) == nil)
                let password = runtime.id == tui.id || authMode == "password" ? "tui-password" : "core-password"
                #expect(try KeychainStore.load(account: runtime.credentialAccount(for: "password"), using: keychain) == password)
            }
            #expect(submitted.passphrase == phrase)
            #expect(submitted.savePassphrase)
        }
    }

    @MainActor @Test(arguments: ["selected", "server", "resolved", "sibling", "detected"], ["different", "same", "formatting", "reencrypted", "provided"])
    func runtimeKeyReplacementPreservesOnlyAssociatedPassphrase(path: String, scenario: String) throws {
        let suite = "RuntimeKeyAssociation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let tui = RecentConnection(host: "fixture.example", port: 22, username: "tester", authMode: "privateKey", remember: true)
        let core = RecentConnection(host: tui.host, port: tui.port, username: tui.username, authMode: "privateKey", remember: true, backend: .core)
        let targetKey: String
        switch scenario {
        case "same": targetKey = Self.encrypted64
        case "formatting": targetKey = "\n  " + Self.encrypted64.replacingOccurrences(of: "\n", with: "\r\n  ") + "\r\n"
        case "reencrypted":
            targetKey = Self.reencrypted64
            #expect(try OpenSSHEd25519.parsePublicKey(pem: targetKey) == OpenSSHEd25519.parsePublicKey(pem: Self.encrypted64))
        default: targetKey = Self.encrypted32
        }
        try ConnectionSignIn(entry: tui, secret: Self.encrypted64,
            passphrase: scenario == "provided" ? "source-phrase" : "", savePassphrase: scenario == "provided")
            .persist(defaults: defaults, using: keychain)
        try ConnectionSignIn(entry: core, secret: targetKey, passphrase: "target-phrase", savePassphrase: true)
            .persist(defaults: defaults, using: keychain)
        var submitted = try ConnectionSettingsView(connection: tui, editing: true, defaults: defaults, using: keychain)
            .signIn(defaults: defaults, using: keychain)
        switch path {
        case "selected":
            submitted.entry.id = core.id
            submitted.entry.backend = .core
            try submitted.persist(defaults: defaults, using: keychain, connected: false)
        case "server": try submitted.persistServer(from: tui, defaults: defaults, using: keychain, updateName: false)
        case "resolved": try submitted.resolving(.core, in: [tui, core]).persist(defaults: defaults, using: keychain)
        case "sibling": try submitted.persistSibling(.core, defaults: defaults, using: keychain)
        default: try submitted.persistDetected(backend: .core, found: [.tui, .core], defaults: defaults, using: keychain)
        }
        #expect(try KeychainStore.load(account: core.secretAccount, using: keychain) == Self.encrypted64)
        let expectedPhrase = ["same", "formatting"].contains(scenario) ? "target-phrase" : scenario == "provided" ? "source-phrase" : nil
        #expect(try KeychainStore.load(account: core.passphraseAccount, using: keychain) == expectedPhrase)
    }

    @MainActor @Test(arguments: ["owner-active", "owner-inactive", "sibling-inactive"], ["encrypted", "formatted-encrypted", "plaintext", "provided"])
    func editedKeyReplacementRejectsInheritedPassphrase(context: String, replacement: String) throws {
        let suite = "EditedKeyAssociation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let active = context == "owner-active"
        let tui = RecentConnection(host: "fixture.example", port: 22, username: "tester", authMode: active ? "privateKey" : "password", remember: true)
        let core = RecentConnection(host: tui.host, port: tui.port, username: tui.username, authMode: tui.authMode, remember: true, backend: .core)
        for runtime in [tui, core] {
            try ConnectionSignIn(entry: runtime, secret: active ? Self.encrypted64 : "password",
                passphrase: "inherited-phrase", savePassphrase: true, otherSecret: active ? "password" : Self.encrypted64)
                .persist(defaults: defaults, using: keychain)
        }
        var submitted = try ConnectionSettingsView(connection: tui, editing: true, defaults: defaults, using: keychain)
            .signIn(defaults: defaults, using: keychain)
        let newKey = replacement == "plaintext" ? Self.unencryptedPEM
            : replacement == "formatted-encrypted" ? Self.encrypted32.replacingOccurrences(of: "\n", with: "\r\n") : Self.encrypted32
        if active { submitted.secret = newKey } else { submitted.otherSecret = newKey }
        submitted.credentialEdits?.privateKey = true
        if replacement == "provided" {
            submitted.passphrase = "replacement-phrase"
            submitted.credentialEdits?.passphrase = true
        }
        let target = context == "sibling-inactive" ? core : tui
        if context == "sibling-inactive" { try submitted.persistSibling(.core, defaults: defaults, using: keychain) }
        else { try submitted.persist(defaults: defaults, using: keychain, connected: false) }
        #expect(try KeychainStore.load(account: target.credentialAccount(for: "privateKey"), using: keychain) == newKey)
        #expect(try KeychainStore.load(account: target.passphraseAccount, using: keychain) == (replacement == "provided" ? "replacement-phrase" : nil))
        #expect(submitted.passphrase == (replacement == "provided" ? "replacement-phrase" : "inherited-phrase"))
        #expect(submitted.savePassphrase)
    }

    @MainActor @Test(arguments: ["text", "broken-plaintext"])
    func unfinishedInactiveKeyRetainsPassphraseDraftAcrossSave(kind: String) throws {
        let suite = "UnfinishedInactiveKey.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let entry = RecentConnection(host: "fixture.example", port: 22, username: "tester", authMode: "password", remember: true)
        try ConnectionSignIn(entry: entry, secret: "password", passphrase: "saved-phrase", savePassphrase: true, otherSecret: Self.encrypted64)
            .persist(defaults: defaults, using: keychain)
        var submitted = try ConnectionSettingsView(connection: entry, editing: true, defaults: defaults, using: keychain)
            .signIn(defaults: defaults, using: keychain)
        let draft: String
        if kind == "broken-plaintext" {
            let body = Self.unencryptedPEM.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
            let bytes = try #require(Data(base64Encoded: body))
            draft = "-----BEGIN OPENSSH PRIVATE KEY-----\n" + bytes.dropLast(16).base64EncodedString() + "\n-----END OPENSSH PRIVATE KEY-----"
            _ = try OpenSSHEd25519.parsePublicKey(pem: draft)
            #expect(throws: OpenSSHKeyError.self) { try OpenSSHEd25519.parseRawPrivateKey(pem: draft) }
        } else { draft = "-----BEGIN OPENSSH PRIVATE KEY-----\nunfinished key edit" }
        submitted.otherSecret = draft
        submitted.credentialEdits?.privateKey = true
        try submitted.persist(defaults: defaults, using: keychain, connected: false)
        let reopened = ConnectionSettingsView(connection: entry, editing: true, defaults: defaults, using: keychain)
        #expect(reopened.password == "password")
        #expect(reopened.keyPEM == draft)
        #expect(reopened.keyPassphrase == "saved-phrase")
        #expect(reopened.rememberPassphrase)
    }

    @MainActor @Test func detectedRuntimeReceivesWorkingEncryptedKeyAndSavedPassphrase() throws {
        let suite = "WorkingEncryptedRuntimeSignIn.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let tui = RecentConnection(host: "fixture.example", port: 22, username: "tester", authMode: "privateKey", remember: true)
        let core = RecentConnection(host: tui.host, port: tui.port, username: tui.username, authMode: "privateKey", remember: true, backend: .core)
        try ConnectionSignIn(entry: tui, secret: Self.encrypted64, passphrase: "working-phrase", savePassphrase: true)
            .persist(defaults: defaults, using: keychain)
        try ConnectionSignIn(entry: core, secret: "old-key", passphrase: "old-phrase", savePassphrase: true)
            .persist(defaults: defaults, using: keychain)
        let submitted = try ConnectionSettingsView(connection: tui, defaults: defaults, using: keychain)
            .signIn(defaults: defaults, using: keychain)
        try submitted.persistDetected(backend: .core, found: [.tui, .core], defaults: defaults, using: keychain)
        for runtime in [tui, core] {
            let reopened = try ConnectionSignIn.load(runtime, using: keychain)
            #expect(reopened.secret == Self.encrypted64)
            #expect(reopened.passphrase == "working-phrase")
            #expect(reopened.savePassphrase)
        }
    }

    @MainActor
    @Test
    func connectionFormInspectsEncryptedKeysWithoutDecrypting() throws {
        let entry = RecentConnection(host: "fixture.example", port: 22,
            username: "tester", authMode: "privateKey", remember: true)
        try KeychainStore.save(Self.encrypted64, account: entry.secretAccount)
        defer {
            try? KeychainStore.delete(account: entry.secretAccount)
            try? KeychainStore.delete(account: entry.passphraseAccount)
        }
        let lockedForm = ConnectionSettingsView(connection: entry)
        #expect(lockedForm.keyValidationError == nil)
        #expect(lockedForm.derivedPublicKey != nil)
        #expect(!lockedForm.canConnect)
        // Passphrase verification belongs to the connection attempt, not rendering.
        try KeychainStore.save("wrong", account: entry.passphraseAccount)
        let readyForm = ConnectionSettingsView(connection: entry)
        #expect(readyForm.keyValidationError == nil)
        #expect(readyForm.derivedPublicKey != nil)
        #expect(readyForm.canConnect)
    }

    @MainActor
    @Test
    func encryptedKeyFormRendersOnInitialPresentation() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        let entry = RecentConnection(host: "fixture.example", port: 22,
            username: "tester", authMode: "privateKey", remember: true)
        try KeychainStore.save(Self.encrypted64, account: entry.secretAccount)
        defer { try? KeychainStore.delete(account: entry.secretAccount) }
        let form = ConnectionSettingsView(connection: entry)
        let controller = UIHostingController(rootView: form.environment(AppModel(autoConnectOnLaunch: false)))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        await Task.yield()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { context in
            controller.view.layer.render(in: context.cgContext)
        }
        #expect(image.size == CGSize(width: 390, height: 844))
    }

    @MainActor
    @Test
    func keyUnlockFailureReturnsToConnectionSelection() async throws {
        let errors: [OpenSSHKeyError] = [.passphraseRequired, .invalidPassphraseOrKey,
            .invalidFormat("damaged saved key"), .excessiveRounds]
        for error in errors {
            for wasOffline in [false, true] {
                let config = ConnectionConfig(host: "fixture.example", port: 22,
                    username: "tester", auth: .privateKey(Self.encrypted64, passphrase: "wrong"))
                let model = AppModel(autoConnectOnLaunch: false)
                // Launch auto-connect marks the session active before authentication.
                model.hasActiveSession = true
                model.phase = wasOffline ? .offline(host: config.host, username: config.username) : .disconnected
                let state = try #require(await model.prepareConnectAttempt(config: config))
                state.watchdog.cancel()
                #expect(LaunchCatOverlay.shouldShow(hasActiveSession: model.hasActiveSession,
                    phase: model.phase, hasHandedOff: false))
                model.handleConnectFailure(error, config: config, attempt: state.attempt,
                    wasOffline: state.wasOffline, isCheckingHerdr: false)
                #expect(!model.hasActiveSession)
                #expect(model.phase == .disconnected)
                #expect(model.connectionBanner == nil)
                #expect(model.autoReconnectTask == nil)
                #expect(model.lastError == error.errorDescription)
                #expect(!LaunchCatOverlay.shouldShow(hasActiveSession: model.hasActiveSession,
                    phase: model.phase, hasHandedOff: false))
            }
        }
    }

    @MainActor
    @Test
    func launchRequiresRememberedPassphraseForEncryptedKey() throws {
        let suite = "EncryptedKeyLaunch.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(LaunchPreference.autoConnect.rawValue, forKey: LaunchPreference.storageKey)
        let entry = RecentConnectionStore.entry(host: "test.example", port: 22, username: "tester",
            authMode: "privateKey", remember: true, in: [])
        _ = try RecentConnectionStore.record(entry, in: [], defaults: defaults)
        let keychain = FakeKeychainOperations()
        keychain.items[entry.secretAccount] = Data(Self.encrypted64.utf8)
        #expect(LaunchPreference.autoConnectConfig(defaults: defaults, keychain: keychain) == nil)
        keychain.items[entry.passphraseAccount] = Data("herdcats-test-passphrase".utf8)
        let config = try #require(LaunchPreference.autoConnectConfig(defaults: defaults, keychain: keychain))
        guard case let .privateKey(pem, passphrase) = config.auth else {
            Issue.record("Expected private key authentication")
            return
        }
        #expect(pem == Self.encrypted64)
        #expect(passphrase == "herdcats-test-passphrase")
        keychain.items[entry.secretAccount] = Data(Self.unencryptedPEM.utf8)
        keychain.items.removeValue(forKey: entry.passphraseAccount)
        #expect(LaunchPreference.autoConnectConfig(defaults: defaults, keychain: keychain) != nil)
    }

    @Test
    func rejectsExcessiveWorkBeforeDecryption() throws {
        let body = Self.encrypted64.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        var bytes = try #require(Data(base64Encoded: body))
        // magic, cipher string, KDF string, options length, salt string, rounds
        var offset = 15
        func length(at index: Int) -> Int {
            bytes[index..<(index + 4)].reduce(0) { ($0 << 8) | Int($1) }
        }
        offset += 4 + length(at: offset)
        offset += 4 + length(at: offset)
        offset += 4
        offset += 4 + length(at: offset)
        bytes.replaceSubrange(offset..<(offset + 4), with: [0, 0, 1, 1])
        let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n" + bytes.base64EncodedString() + "\n-----END OPENSSH PRIVATE KEY-----"
        #expect(throws: OpenSSHKeyError.excessiveRounds) {
            _ = try OpenSSHEd25519.parseRawPrivateKey(pem: pem, passphrase: "herdcats-test-passphrase")
        }
    }

    @Test
    func rejectsGarbage() {
        #expect(throws: OpenSSHKeyError.self) {
            _ = try OpenSSHEd25519.parseRawPrivateKey(pem: "not a key at all")
        }
    }

    @Test
    func formatsOpenSSHPublicKeyStringAndFingerprint() throws {
        let pubKeyString = try OpenSSHEd25519.parseOpenSSHPublicKeyString(pem: Self.unencryptedPEM)
        #expect(pubKeyString == OpenSSHParserFixture.publicKeyLine)

        let fingerprint = try OpenSSHEd25519.parseFingerprint(pem: Self.unencryptedPEM)
        #expect(fingerprint == SSHHostKeyValidatorDelegate.fingerprint(pubKeyString))
        #expect(fingerprint.hasPrefix("SHA256:"))
    }

    @Test
    func masksPrivateKeyPreservingOnlyLastTwoLines() {
        #expect(OpenSSHEd25519.maskPrivateKey(pem: "") == "")

        let masked = OpenSSHEd25519.maskPrivateKey(pem: Self.unencryptedPEM)
        let lines = masked.split(separator: "\n").map(String.init)
        #expect(lines.count == 4)
        #expect(lines[0] == "••••••••••••••••••••••••••••••••")
        #expect(lines[1] == "••••••••••••••••••••••••••••••••")
        #expect(lines[2] == String(Self.unencryptedPEM.split(separator: "\n").dropLast().last!))
        #expect(lines[3] == "-----END OPENSSH PRIVATE KEY-----")

        #expect(!masked.contains("BEGIN OPENSSH PRIVATE KEY"))
        #expect(!masked.contains("b3BlbnNzaC1rZXktdjE"))

        let twoLines = "line1\nline2"
        #expect(OpenSSHEd25519.maskPrivateKey(pem: twoLines) == "••••••••••••••••••••••••••••••••\nline1\nline2")
    }
}

@Suite("Long dictation")
struct DictationTranscriptTests {
    @Test func pauseWithoutTaskFinalKeepsEverySentence() {
        var transcript = DictationTranscript(committed: "Existing draft.")
        let ended1 = transcript.receive("First sent", isFinal: false)
        #expect(!ended1)
        let ended2 = transcript.receive("First sentence.", isFinal: false, speechDuration: 1.8)
        #expect(ended2)
        let ended3 = transcript.receive("Second", isFinal: false)
        #expect(!ended3)
        #expect(transcript.text == "Existing draft. First sentence. Second")
        let ended4 = transcript.receive("Second sentence.", isFinal: false, speechDuration: 2.1)
        #expect(ended4)
        let ended5 = transcript.receive("Third sentence.", isFinal: true)
        #expect(ended5)
        #expect(transcript.text == "Existing draft. First sentence. Second sentence. Third sentence.")
    }

    @Test func unfinishedHypothesesCanStillBeCorrected() {
        var transcript = DictationTranscript()
        let ended6 = transcript.receive("Send it on Monday", isFinal: false, speechDuration: 0)
        #expect(!ended6)
        let ended7 = transcript.receive("Send it on Tuesday", isFinal: false)
        #expect(!ended7)
        let ended8 = transcript.receive("Send it on Tuesday.", isFinal: false, speechDuration: 2)
        #expect(ended8)
        #expect(transcript.text == "Send it on Tuesday.")
        let ended9 = transcript.receive("Send it on Tuesday.", isFinal: true)
        #expect(ended9)
        // Repeating the same sentence in the next request is real speech, not a duplicate.
        #expect(transcript.text == "Send it on Tuesday. Send it on Tuesday.")
    }

    @Test func emptyFinalCallbackPreservesLastRecognizedWords() {
        var transcript = DictationTranscript()
        let ended10 = transcript.receive("Keep the last words", isFinal: false)
        #expect(!ended10)
        let ended11 = transcript.receive("", isFinal: true)
        #expect(ended11)
        #expect(transcript.text == "Keep the last words")
    }

    @Test func preservesDraftAndEarlierSegmentsWhenPartialResultsChange() {
        var transcript = DictationTranscript(committed: "Existing draft.")
        transcript.update("First incomplete")
        transcript.update("First sentence.")
        transcript.commit()
        transcript.update("Second")
        transcript.update("Second sentence.")
        #expect(transcript.text == "Existing draft. First sentence. Second sentence.")
        transcript.commit()
        #expect(transcript.text == "Existing draft. First sentence. Second sentence.")
    }

    @Test func preservesAllTextAcrossManyRecognitionSessions() {
        var transcript = DictationTranscript()
        let segments = (1...100).map { "Sentence \($0)." }
        for segment in segments {
            transcript.update(segment)
            transcript.commit()
        }
        #expect(transcript.text == segments.joined(separator: " "))
    }

    @Test func emptySegmentsAndExistingWhitespaceDoNotDuplicateText() {
        var transcript = DictationTranscript(committed: "Draft\n")
        transcript.commit()
        transcript.update("More words.")
        transcript.commit()
        transcript.commit()
        #expect(transcript.text == "Draft\nMore words.")
    }
}
