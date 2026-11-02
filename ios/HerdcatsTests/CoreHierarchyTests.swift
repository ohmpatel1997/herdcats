import Foundation
import Testing
@testable import Herdcats

@Suite("Core snapshot and hierarchy")
struct CoreHierarchyTests {
    @Test func snapshotsRequireSequenceAndTerminalIdentity() throws {
        #expect(throws: (any Error).self) {
            _ = try CoreSnapshot(subscription: json("{\"terminals\":[]}"))
        }
        #expect(throws: (any Error).self) {
            _ = try CoreSnapshot(subscription: json("{\"seq\":1,\"terminals\":[{}]}"))
        }
        #expect(throws: (any Error).self) {
            _ = try CoreSnapshot(subscription: json("{\"seq\":1,\"terminals\":[{\"address\":\"t1\"}]}"))
        }
    }

    @Test func typedTextMapsOnlyToExactCoreKeys() {
        #expect(HerdrConnection.coreTypedKeys("ls -A ./x") == ["l", "s", "space", "-", "shift+a", "space", ".", "/", "x"])
        #expect(HerdrConnection.coreTypedKeys("\t\n") == ["tab", "enter"])
        // No exact Core key: send nothing rather than a different character.
        #expect(HerdrConnection.coreTypedKeys("hi!") == nil)
        #expect(HerdrConnection.coreTypedKeys("\"") == nil)
        #expect(HerdrConnection.coreTypedKeys("é") == nil)
    }

    @Test func turnEventsDoNotOverwriteLiveLifecycle() throws {
        var snapshot = try fixture()
        _ = try snapshot.apply(event(11, "turn", "t2", "{\"turn\":3,\"state\":\"done\"}"))
        #expect(snapshot.terminals["t2"]?["state"].stringValue == "live")
        #expect(snapshot.terminals["t2"]?["turn"].intValue == 3)
        #expect(snapshot.presentation(layout: nil).panes.count == 2)
    }

    @Test func missedSnapshotReplacesTerminalsAndIgnoresOldEvents() throws {
        var snapshot = try fixture()
        let missed = try json("{\"method\":\"missed\",\"params\":{\"seq\":40,\"terminals\":[\(terminal("t2", app: "claude-code"))]}}")
        #expect(try snapshot.apply(missed))
        #expect(Set(snapshot.terminals.keys) == ["t2"])
        _ = try snapshot.apply(event(12, "created", "t1", terminal("t1")))
        #expect(Set(snapshot.terminals.keys) == ["t2"])
        #expect(snapshot.seq == 40)
        // A new subscription is a different sequence scope, even when lower.
        let replacement = try CoreSnapshot(subscription: json("{\"seq\":0,\"terminals\":[]}"))
        #expect(replacement.seq == 0)
        #expect(replacement.terminals.isEmpty)
    }

    @Test func heartbeatDoesNotConsumeAnEventSequence() throws {
        var snapshot = try fixture()
        #expect(try !snapshot.apply(json("{\"method\":\"heartbeat\",\"params\":{\"seq\":12}}")))
        _ = try snapshot.apply(event(11, "title", "t2", "{\"title\":\"Updated\"}"))
        #expect(snapshot.seq == 11)
        #expect(snapshot.terminals["t2"]?["title"].stringValue == "Updated")
    }

    @Test func documentsRequestRefreshWithoutTerminalIdentity() throws {
        var snapshot = try fixture()
        #expect(try snapshot.apply(json("{\"method\":\"event\",\"params\":{\"seq\":11,\"type\":\"doc\",\"data\":{\"name\":\"herdr-app\",\"version\":2}}}")))
        #expect(snapshot.terminals.count == 2)
        #expect(snapshot.seq == 11)
    }

    @Test func staleMissedCannotReplaceNewerState() throws {
        var snapshot = try fixture()
        #expect(try !snapshot.apply(json("{\"method\":\"missed\",\"params\":{\"seq\":9,\"terminals\":[]}}")))
        #expect(snapshot.seq == 10)
        #expect(snapshot.terminals.count == 2)
    }

    @Test func emptyCoreNeedsNoFabricatedWorkspace() throws {
        let snapshot = try CoreSnapshot(subscription: json("{\"seq\":0,\"terminals\":[]}"))
        let hierarchy = snapshot.presentation(layout: nil)
        #expect(hierarchy.workspaces.isEmpty)
        #expect(hierarchy.tabs.isEmpty)
        #expect(hierarchy.panes.isEmpty)
    }

    @Test func labelsReplaceAndForegroundCanClear() throws {
        var snapshot = try fixture()
        _ = try snapshot.apply(event(11, "labels", "t2", "{\"labels\":{\"new\":\"value\"}}"))
        _ = try snapshot.apply(event(12, "foreground", "t2", "null"))
        #expect(snapshot.terminals["t2"]?["labels"].objectValue?.keys.sorted() == ["new"])
        #expect(snapshot.terminals["t2"]?["foreground"] == .null)
    }

    @Test func createReplacesExistingRecordsAndFinishedDisappearsFromLivePresentation() throws {
        var snapshot = try fixture()
        _ = try snapshot.apply(event(11, "created", "t2", terminal("t2", title: "New incarnation")))
        #expect(snapshot.terminals["t2"]?["status"] == .null)
        _ = try snapshot.apply(event(12, "finished", "t2", "{\"reason\":\"exited\",\"exit_code\":0,\"signal\":null,\"finished_ms\":12}"))
        #expect(snapshot.terminals["t2"]?["state"].stringValue == "finished")
        #expect(snapshot.presentation(layout: nil).panes.map(\.paneId) == ["t1"])
        _ = try snapshot.apply(event(13, "removed", "t2", "{}"))
        #expect(snapshot.terminals["t2"] == nil)
    }

    @Test func missingOrMalformedLayoutShowsAllLiveTerminalsAsOther() throws {
        let snapshot = try fixture()
        for layout in [CoreJSON.null, try json("{\"spaces\":\"unexpected\"}"), try json("{\"spaces\":[{\"id\":\"broken\"}]}" )] {
            let hierarchy = snapshot.presentation(layout: layout)
            #expect(hierarchy.workspaces.map(\.label) == ["Other terminals"])
            #expect(Set(hierarchy.panes.map(\.paneId)) == ["t1", "t2"])
            #expect(hierarchy.agents.map(\.agent) == ["claude"])
            #expect(hierarchy.panes.first { $0.paneId == "t1" }?.agent == nil)
            #expect(hierarchy.panes.first { $0.paneId == "t1" }?.agentStatus == "unknown")
            #expect(hierarchy.panes.allSatisfy { !$0.focused })
        }
    }

    @Test func desktopLayoutTraversesNestedBlocksAndKeepsOtherTerminals() throws {
        let snapshot = try fixture()
        let layout = try json("""
        {"spaces":[{"id":"sp1","name":"Project","folder":"/project","tabs":[
          {"id":"tb1","name":"Claude","root":{"type":"row","children":[
            {"type":"column","children":[{"type":"block","id":"p1","content":{"terminal":"t2"}}]},
            {"type":"block","id":"panel","content":{"mod":"files"}}
          ]}}
        ]}]}
        """)
        let hierarchy = snapshot.presentation(layout: layout)
        #expect(hierarchy.workspaces.map(\.label) == ["Project", "Other terminals"])
        #expect(hierarchy.tabs.first?.label == "Claude")
        let agent = try #require(hierarchy.agents.first)
        #expect(agent.paneId == "t2")
        #expect(agent.workspaceId == hierarchy.workspaces.first?.workspaceId)
        #expect(hierarchy.workspaces.first?.activeTabId == hierarchy.tabs.first?.tabId)
        #expect(hierarchy.workspaces.first?.paneCount == 1)
        #expect(hierarchy.panes.count == 2)
    }

    @Test func duplicateNodesCannotDuplicateTerminalsOrWorkspaceIDs() throws {
        let snapshot = try fixture()
        let space = "{\"id\":\"sp1\",\"name\":\"Project\",\"tabs\":[{\"id\":\"tb1\",\"root\":{\"children\":[{\"content\":{\"terminal\":\"t2\"}},{\"content\":{\"terminal\":\"t2\"}}]}}]}"
        let hierarchy = snapshot.presentation(layout: try json("{\"spaces\":[\(space),\(space)]}"))
        #expect(Set(hierarchy.panes.map(\.paneId)).count == hierarchy.panes.count)
        #expect(Set(hierarchy.workspaces.map(\.workspaceId)).count == hierarchy.workspaces.count)
        #expect(Set(hierarchy.tabs.map(\.tabId)).count == hierarchy.tabs.count)
    }

    @Test func remoteDocumentsQualifyLocalAddressesAndLayoutIdentity() throws {
        let snapshot = try CoreSnapshot(subscription: json("{\"seq\":1,\"terminals\":[\(terminal("t1")),\(terminal("vps/t1", app:"codex"))]}"))
        let layout = try json("{\"spaces\":[{\"id\":\"same\",\"name\":\"Work\",\"tabs\":[{\"id\":\"same-tab\",\"root\":{\"content\":{\"terminal\":\"t1\"}}}]}]}")
        let hierarchy = snapshot.presentation(layout: layout, remoteLayouts: ["vps": layout])
        #expect(hierarchy.workspaces.count == 2)
        #expect(Set(hierarchy.workspaces.map(\.workspaceId)).count == 2)
        #expect(Set(hierarchy.panes.map(\.paneId)) == ["t1", "vps/t1"])
        #expect(hierarchy.agents.first?.paneId == "vps/t1")
        #expect(hierarchy.workspaces.last?.label.contains("vps") == true)
    }

    @Test func labelsCanPlaceNewlyCreatedTerminalInKnownDesktopTab() throws {
        let snapshot = try fixture()
        // A Core terminal may appear before its corresponding desktop block.
        let layout = try json("{\"spaces\":[{\"id\":\"sp1\",\"name\":\"Project\",\"tabs\":[{\"id\":\"tb1\",\"name\":\"Agent\",\"root\":{\"children\":[]}}]}]}")
        let hierarchy = snapshot.presentation(layout: layout)
        #expect(hierarchy.workspaces.first?.paneCount == 1)
        #expect(hierarchy.panes.first { $0.paneId == "t2" }?.tabId == hierarchy.tabs.first?.tabId)
    }

    @Test func remoteMachineNamedLocalCannotCollideWithThisMachine() throws {
        let snapshot = try CoreSnapshot(subscription: json("{\"seq\":1,\"terminals\":[\(terminal("t1")),\(terminal("local/t1"))]}"))
        let layout = try json("{\"spaces\":[{\"id\":\"sp1\",\"tabs\":[{\"id\":\"tb1\",\"root\":{\"content\":{\"terminal\":\"t1\"}}}]}]}")
        let hierarchy = snapshot.presentation(layout: layout, remoteLayouts: ["local": layout])
        #expect(hierarchy.workspaces.count == 2)
        #expect(!hierarchy.workspaces.contains { $0.workspaceId == CoreHierarchy.otherWorkspaceID })
        #expect(Set(hierarchy.workspaces.map(\.workspaceId)).count == 2)
    }

    @Test func remoteLayoutReferencesAreQualifiedEvenWhenTheyNameAnotherMachine() throws {
        let snapshot = try CoreSnapshot(subscription: json("{\"seq\":1,\"terminals\":[\(terminal("vps/peer/t1"))]}"))
        let layout = try json("{\"spaces\":[{\"id\":\"sp1\",\"tabs\":[{\"id\":\"tb1\",\"root\":{\"content\":{\"terminal\":\"peer/t1\"}}}]}]}")
        let hierarchy = snapshot.presentation(layout: nil, remoteLayouts: ["vps": layout])
        #expect(hierarchy.workspaces.count == 1)
        #expect(hierarchy.workspaces.first?.workspaceId != CoreHierarchy.otherWorkspaceID)
        #expect(hierarchy.panes.first?.paneId == "vps/peer/t1")
    }

    @Test func presentationOrderUsesCreationTimeThenNaturalAddressOrder() throws {
        func term(_ address: String, created: Int, labelled: Bool) -> String {
            let labels = labelled ? "{\"herdr.space\":\"sp1\",\"herdr.tab\":\"tb1\"}" : "{}"
            return "{\"address\":\"\(address)\",\"title\":\"T\",\"state\":\"live\",\"cwd\":\"/p\",\"created_ms\":\(created),\"status\":null,\"reported\":false,\"labels\":\(labels)}"
        }
        let terminals = [
            term("t10", created: 4, labelled: false), term("b", created: 2, labelled: true),
            term("vps/n", created: 3, labelled: false), term("t2", created: 4, labelled: false),
            term("a", created: 2, labelled: true), term("c", created: 1, labelled: true),
            term("vps/m", created: 3, labelled: false), term("z", created: 0, labelled: false)
        ].joined(separator: ",")
        let snapshot = try CoreSnapshot(subscription: json("{\"seq\":1,\"terminals\":[\(terminals)]}"))
        let layout = try json("""
        {"spaces":[
          {"id":"sp1","name":"One","tabs":[{"id":"tb1","name":"A","root":{"children":[]}},{"id":"tb2","name":"B","root":{"children":[]}}]},
          {"id":"sp2","name":"Two","tabs":[{"id":"tb1","name":"C","root":{"children":[]}}]}
        ]}
        """)
        let hierarchy = snapshot.presentation(layout: layout, remoteLayouts: ["vps": layout])
        // Labelled terminals fill their tab by creation time, ties by natural address order;
        // the rest follow in the same order under "Other terminals".
        #expect(hierarchy.panes.map(\.paneId) == ["c", "a", "b", "z", "vps/m", "vps/n", "t2", "t10"])
        #expect(hierarchy.tabs.map(\.paneCount) == [3, 0, 0, 0, 0, 0, 5])
    }

    private func fixture() throws -> CoreSnapshot {
        try CoreSnapshot(subscription: json("{\"seq\":10,\"terminals\":[\(terminal("t1")),\(terminal("t2", app: "claude-code"))]}"))
    }

    private func terminal(_ address: String, app: String? = nil, title: String = "Terminal") -> String {
        let status = app.map { "{\"app\":\"\($0)\",\"state\":\"idle\"}" } ?? "null"
        let labels = app == nil ? "{}" : "{\"herdr.space\":\"sp1\",\"herdr.tab\":\"tb1\"}"
        return "{\"address\":\"\(address)\",\"title\":\"\(title)\",\"state\":\"live\",\"cwd\":\"/project\",\"created_ms\":1,\"status\":\(status),\"reported\":\(app != nil),\"labels\":\(labels)}"
    }

    private func event(_ seq: Int, _ type: String, _ terminal: String, _ data: String) throws -> CoreJSON {
        try json("{\"method\":\"event\",\"params\":{\"seq\":\(seq),\"type\":\"\(type)\",\"terminal\":\"\(terminal)\",\"data\":\(data)}}")
    }

    private func json(_ value: String) throws -> CoreJSON {
        try JSONDecoder().decode(CoreJSON.self, from: Data(value.utf8))
    }
}
