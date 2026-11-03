import Foundation
import Testing
@testable import Herdcats

@Suite("Core connection profiles")
struct CoreConnectionProfileTests {
    @Test func oldProfilesDecodeAsTUI() throws {
        let id = UUID()
        let data = Data("""
        {"id":"\(id)","host":"mac.local","port":22,"username":"alex","authMode":"password","remember":true}
        """.utf8)
        let profile = try JSONDecoder().decode(RecentConnection.self, from: data)
        #expect(profile.id == id)
        #expect(profile.backend == .tui)
    }

    @Test func coreProfileSurvivesEncoding() throws {
        let profile = RecentConnection(host: "mac.local", port: 22, username: "alex",
                                       authMode: "password", remember: true, backend: .core)
        let decoded = try JSONDecoder().decode(RecentConnection.self, from: JSONEncoder().encode(profile))
        #expect(decoded == profile)
        #expect(decoded.backend == .core)
    }

    @Test func sameEndpointCanHaveBothBackends() {
        let tui = RecentConnectionStore.entry(host: "mac.local", port: 22, username: "alex",
                                              authMode: "password", remember: true, in: [])
        let core = RecentConnectionStore.entry(host: "MAC.local", port: 22, username: "alex",
                                               authMode: "password", remember: true, backend: .core, in: [tui])
        #expect(core.id != tui.id)
        #expect(core.secretAccount != tui.secretAccount)
        #expect(core.backend == .core)
        let reused = RecentConnectionStore.entry(host: "mac.local", port: 22, username: "alex",
                                                 authMode: "privateKey", remember: false, backend: .core,
                                                 in: [tui, core])
        #expect(reused.id == core.id)
        #expect(reused.authMode == "privateKey")
    }

    @Test func coreDraftHistoryScopeIsSeparateAndTUIKeepsExistingKeys() {
        let tui = ConnectionIdentity(host: "Mac.local", port: 22, username: "Alex")
        let core = ConnectionIdentity(host: "Mac.local", port: 22, username: "Alex", backend: .core)
        #expect(tui.storageKey == "u=Alex|h=mac.local|p=22")
        #expect(core.storageKey == "u=Alex|h=mac.local|p=22|b=core")
        #expect(tui != core)
        #expect(PanePersistenceKeys.draft(scope: tui, paneId: "t1") != PanePersistenceKeys.draft(scope: core, paneId: "t1"))
        #expect(PanePersistenceKeys.history(scope: tui, paneId: "t1") != PanePersistenceKeys.history(scope: core, paneId: "t1"))
    }

    @Test func oldIdentitiesDecodeWithoutChangingTheirScope() throws {
        let data = Data(#"{"host":"mac.local","port":22,"username":"alex"}"#.utf8)
        let identity = try JSONDecoder().decode(ConnectionIdentity.self, from: data)
        #expect(identity.backend == .tui)
        #expect(identity.storageKey == "u=alex|h=mac.local|p=22")
    }

    @Test func configurationPreservesBackendInIdentity() {
        let legacy = ConnectionConfig(host: "mac.local", port: 22, username: "alex", auth: .password("secret"))
        let core = ConnectionConfig(host: "mac.local", port: 22, username: "alex", auth: .password("secret"), backend: .core)
        #expect(legacy.backend == .tui)
        #expect(ConnectionIdentity(core).backend == .core)
    }

    @Test func sameHostBackendMenuNamesAreDistinct() {
        let tui = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true)
        let core = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true, backend: .core)
        #expect(tui.shortDisplayName(among: [tui, core]).hasSuffix(" · TUI"))
        #expect(core.shortDisplayName(among: [tui, core]).hasSuffix(" · Herdr Core"))
        #expect(tui.shortDisplayName(among: [tui]) == "mac")
    }

    @Test func explicitNamesStillDisambiguateMatchingBackendProfiles() {
        let tui = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true, name: "Studio")
        let core = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true, name: "Studio", backend: .core)
        #expect(tui.shortDisplayName(among: [tui, core]) == "Studio · TUI")
        #expect(core.shortDisplayName(among: [tui, core]) == "Studio · Herdr Core")
    }

    @Test func runtimeProbeReportsEachCLIFound() {
        let both = "\(HerdrConnection.tuiFoundMarker)\n\(HerdrConnection.coreFoundMarker)\n"
        #expect(HerdrConnection.detectedBackends(both) == [.tui, .core])
        #expect(HerdrConnection.detectedBackends(HerdrConnection.coreFoundMarker) == [.core])
        #expect(HerdrConnection.detectedBackends("motd\n").isEmpty)
    }

    @Test func onlyAMissingRuntimeStartsTheRuntimeCheck() {
        #expect(HerdrConnection.mayMeanRuntimeIsMissing(HerdrError.herdrNotFound, backend: .tui))
        #expect(HerdrConnection.mayMeanRuntimeIsMissing(HerdrError.coreStartupClosed, backend: .core))
        // Herdr answered or the connection failed, so the runtime is not the problem.
        #expect(!HerdrConnection.mayMeanRuntimeIsMissing(HerdrError.herdrExit(1), backend: .tui))
        #expect(!HerdrConnection.mayMeanRuntimeIsMissing(HerdrError.timeout("herdr command"), backend: .tui))
        #expect(!HerdrConnection.mayMeanRuntimeIsMissing(CoreRPCError.unsupportedGeneration, backend: .core))
        #expect(!HerdrConnection.mayMeanRuntimeIsMissing(HerdrError.notConnected, backend: .core))
    }

    @Test func missingSavedRuntimeNamesTheRuntimeTheMachineHas() {
        let tuiMissing = HerdrError.herdrNotFound
        let coreMissing = HerdrError.coreStartupClosed
        func reported(_ error: HerdrError, saved: ConnectionBackend, found: Set<ConnectionBackend>?) -> HerdrError? {
            HerdrConnection.missingRuntimeError(error, saved: saved, found: found) as? HerdrError
        }
        // A TUI entry on a machine with only Herdr Core, and the reverse.
        #expect(reported(tuiMissing, saved: .tui, found: [.core]) == .runtimeNotInstalled(saved: .tui, available: .core))
        #expect(reported(coreMissing, saved: .core, found: [.tui]) == .runtimeNotInstalled(saved: .core, available: .tui))
        // Neither runtime is on the machine.
        #expect(reported(tuiMissing, saved: .tui, found: []) == .runtimeNotInstalled(saved: .tui, available: nil))
        #expect(reported(coreMissing, saved: .core, found: []) == .runtimeNotInstalled(saved: .core, available: nil))
        // The saved runtime is there after all, or the check could not run: keep the first error.
        #expect(reported(coreMissing, saved: .core, found: [.tui, .core]) == coreMissing)
        #expect(reported(tuiMissing, saved: .tui, found: nil) == tuiMissing)
    }

    @Test func missingRuntimeMessagesSayWhatIsInstalled() {
        let tuiOnCore = HerdrConnection.friendlyMessage(for: HerdrError.runtimeNotInstalled(saved: .tui, available: .core))
        #expect(tuiOnCore.contains("This machine runs Herdr Core"))
        #expect(tuiOnCore.contains("set to the Herdr TUI"))
        let coreOnTUI = HerdrConnection.friendlyMessage(for: HerdrError.runtimeNotInstalled(saved: .core, available: .tui))
        #expect(coreOnTUI.contains("This machine runs the Herdr TUI"))
        #expect(coreOnTUI.contains("set to Herdr Core"))
        let neither = HerdrConnection.friendlyMessage(for: HerdrError.runtimeNotInstalled(saved: .tui, available: nil))
        #expect(neither.contains("Install the Herdr desktop app, Herdr Core, or the Herdr TUI"))
        // When Core is installed but won't open, the message stays as it was.
        #expect(HerdrConnection.friendlyMessage(for: HerdrError.coreStartupClosed).hasPrefix("Could not open Herdr Core"))
    }

    @Test func autoConnectSavesBothRuntimesWithOneSignIn() throws {
        let suite = "CoreConnectionProfileTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let entry = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true)
        let value = ConnectionSignIn(entry: entry, secret: "pw", detectsBackend: true)
        #expect(value.config.detectsBackend)
        try value.persistDetected(backend: .tui, found: [.tui, .core], defaults: defaults, using: keychain)
        let saved = try RecentConnectionStore.load(defaults: defaults, using: keychain)
        #expect(Set(saved.map(\.backend)) == [.tui, .core])
        let core = try #require(saved.first { $0.backend == .core })
        #expect(core.lastConnectedAt == nil)
        #expect(try ConnectionSignIn.load(core, using: keychain).secret == "pw")
        // A second Auto connect reuses both entries.
        try value.persistDetected(backend: .tui, found: [.tui, .core], defaults: defaults, using: keychain)
        #expect(try RecentConnectionStore.load(defaults: defaults, using: keychain).count == 2)
    }

    @Test func autoConnectToOnlyCoreNeverRepointsASavedTUIEntry() throws {
        let tui = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true)
        let fresh = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true)
        let resolvedSaved = ConnectionSignIn(entry: tui, detectsBackend: true).resolving(.core, in: [tui])
        #expect(resolvedSaved.entry.backend == .core)
        #expect(resolvedSaved.entry.id != tui.id)
        let resolvedFresh = ConnectionSignIn(entry: fresh, detectsBackend: true).resolving(.core, in: [tui])
        #expect(resolvedFresh.entry.id == fresh.id)
        let core = resolvedSaved.entry
        #expect(ConnectionSignIn(entry: tui).resolving(.core, in: [tui, core]).entry.id == core.id)
    }

    @Test func autoReusesTheSavedRuntimeWhenTheSignInMethodChanges() {
        let core = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true, backend: .core)
        let keyed = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "privateKey", remember: true)
        let resolved = ConnectionSignIn(entry: keyed, detectsBackend: true).resolving(.core, in: [core])
        #expect(resolved.entry.id == core.id)
        #expect(resolved.entry.authMode == "privateKey")
    }

    @Test func listsShowOneServerOnTheRuntimeUsedLast() {
        let tui = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true,
                                   lastConnectedAt: Date(timeIntervalSince1970: 1))
        let other = RecentConnection(host: "pi.local", port: 22, username: "alex", authMode: "password", remember: true)
        let core = RecentConnection(host: "MAC.local", port: 22, username: "alex", authMode: "password", remember: true,
                                    lastConnectedAt: Date(timeIntervalSince1970: 2), backend: .core)
        let servers = RecentConnectionStore.servers([tui, other, core])
        #expect(servers.map(\.id) == [core.id, other.id])
        #expect(RecentConnectionStore.runtimeSummary(of: tui, in: [tui, other, core]) == "TUI + Herdr Core")
        #expect(RecentConnectionStore.runtimeSummary(of: other, in: [tui, other, core]) == "TUI")
        #expect(core.shortDisplayName(among: servers) == "MAC")
    }

    @Test func managingAServerEditsEveryRuntime() {
        let tui = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true)
        let other = RecentConnection(host: "pi.local", port: 22, username: "alex", authMode: "password", remember: true)
        let core = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true, backend: .core)
        var draft = RecentConnectionStore.ManagementDraft(connections: [tui, other, core])
        #expect(draft.servers.count == 2)
        draft.rename(id: core.id, to: "Studio")
        #expect(draft.connections.filter { $0.name == "Studio" }.count == 2)
        draft.move(fromOffsets: [1], toOffset: 0)
        #expect(draft.connections.map(\.id) == [other.id, tui.id, core.id])
        draft.delete(at: [1])
        #expect(draft.connections.map(\.id) == [other.id])
    }

    @Test func autoRefreshesTheSavedSiblingWithTheWorkingSignIn() throws {
        let suite = "CoreConnectionProfileTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let core = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true, backend: .core)
        try ConnectionSignIn(entry: core, secret: "old").persist(defaults: defaults, using: keychain)
        let tui = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true)
        try ConnectionSignIn(entry: tui, secret: "new", detectsBackend: true)
            .persistDetected(backend: .tui, found: [.tui, .core], defaults: defaults, using: keychain)
        let saved = try RecentConnectionStore.load(defaults: defaults, using: keychain)
        let refreshed = try #require(saved.first { $0.backend == .core })
        #expect(refreshed.id == core.id)
        #expect(refreshed.lastConnectedAt != nil)
        #expect(try ConnectionSignIn.load(refreshed, using: keychain).secret == "new")
    }

    @Test func autoHostChangeMovesEveryRuntimeOfTheServer() throws {
        let suite = "CoreConnectionProfileTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let tui = RecentConnection(host: "old.local", port: 22, username: "alex", authMode: "password", remember: true,
                                   lastConnectedAt: Date(timeIntervalSince1970: 1))
        let core = RecentConnection(host: "old.local", port: 22, username: "alex", authMode: "password", remember: true,
                                    lastConnectedAt: Date(timeIntervalSince1970: 2), backend: .core)
        try ConnectionSignIn(entry: tui, secret: "old").persist(defaults: defaults, using: keychain)
        try ConnectionSignIn(entry: core, secret: "old").persist(defaults: defaults, using: keychain)
        var edited = core
        edited.host = "new.local"
        try ConnectionSignIn(entry: edited, secret: "new", detectsBackend: true)
            .persistServer(from: core, defaults: defaults, using: keychain, updateName: false)
        let saved = try RecentConnectionStore.load(defaults: defaults, using: keychain)
        #expect(saved.count == 2)
        #expect(Set(saved.map(\.id)) == [tui.id, core.id])
        #expect(saved.allSatisfy { $0.host == "new.local" })
        #expect(RecentConnectionStore.servers(saved).count == 1)
        for entry in saved { #expect(try ConnectionSignIn.load(entry, using: keychain).secret == "new") }
        // Detection afterwards reuses the moved entries instead of adding new ones.
        let detected = ConnectionSignIn(entry: edited, secret: "new", detectsBackend: true)
        try detected.persistDetected(backend: .tui, found: [.tui, .core], defaults: defaults, using: keychain)
        #expect(Set(try RecentConnectionStore.load(defaults: defaults, using: keychain).map(\.id)) == [tui.id, core.id])
    }

    @Test func savingARuntimeReplacesItsDuplicateEntries() throws {
        let suite = "CoreConnectionProfileTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychainOperations()
        let first = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true)
        let core = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: true, backend: .core)
        let duplicate = RecentConnection(host: "MAC.local", port: 22, username: "alex", authMode: "password", remember: true)
        // Builds before this fix could save two TUI entries for one server.
        defaults.set(try JSONEncoder().encode([first, core, duplicate]), forKey: RecentConnectionStore.storageKey)
        #expect(RecentConnectionStore.savedRuntimes(of: first, in: [first, core, duplicate]).map(\.backend) == [.tui, .core])
        try KeychainStore.save("stale", account: first.secretAccount, using: keychain)
        try ConnectionSignIn(entry: duplicate, secret: "pw").persist(defaults: defaults, using: keychain)
        let saved = try RecentConnectionStore.load(defaults: defaults, using: keychain)
        #expect(saved.map(\.id) == [core.id, duplicate.id])
        #expect(try KeychainStore.load(account: first.secretAccount, using: keychain) == nil)
    }

    #if canImport(UIKit)
    @MainActor @Test func editingAServerWithBothRuntimesOpensOnAuto() throws {
        let suite = "CoreConnectionProfileTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tui = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: false)
        let core = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: false, backend: .core)
        defaults.set(try JSONEncoder().encode([tui, core]), forKey: RecentConnectionStore.storageKey)
        let form = ConnectionSettingsView(connection: core, editing: true, defaults: defaults, using: FakeKeychainOperations())
        #expect(form.backend == nil)
        #expect(form.destination.backend == .core)
    }
    #endif

    #if canImport(UIKit)
    @MainActor @Test func newConnectionsDefaultToAutoAndSavedOnesKeepTheirRuntime() throws {
        let suite = "CoreConnectionProfileTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let blank = RecentConnection(host: "", port: 22, username: "", authMode: "password", remember: true)
        let form = ConnectionSettingsView(connection: blank, using: FakeKeychainOperations())
        #expect(form.backend == nil)
        let saved = RecentConnection(host: "mac.local", port: 22, username: "alex", authMode: "password", remember: false)
        let savedForm = ConnectionSettingsView(connection: saved, editing: true, using: FakeKeychainOperations())
        #expect(savedForm.backend == .tui)
        #expect(try savedForm.signIn(defaults: defaults, using: FakeKeychainOperations()).detectsBackend == false)
    }
    #endif

    #if canImport(UIKit)
    @MainActor @Test func formAndCredentialBuildersPreserveCoreSelection() throws {
        let suite = "CoreConnectionProfileTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profile = RecentConnection(host: "mac.local", port: 22, username: "alex",
                                       authMode: "password", remember: false, backend: .core)
        let form = ConnectionSettingsView(connection: profile, editing: true, using: FakeKeychainOperations())
        #expect(form.destination.backend == .core)
        #expect(try form.signIn(defaults: defaults, using: FakeKeychainOperations()).config.backend == .core)
        #expect(ConnectionSignIn(entry: profile, secret: "fixture").config.backend == .core)
    }
    #endif
}
