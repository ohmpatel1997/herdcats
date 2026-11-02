import Foundation
import Testing
@testable import Herdcats

private extension HerdrConnection {
    func installForTest(_ snapshot: CoreSnapshot) { coreSnapshot = snapshot }
    func setLayoutsForTest(_ layouts: [String: CoreJSON]) { coreLayouts = layouts }
    var builds: Int { corePresentationBuilds }
}

@Suite("Core presentation memo")
struct CorePresentationMemoTests {
    @Test func repeatedCallsBuildOnceUntilSnapshotOrLayoutsChange() async throws {
        let connection = HerdrConnection()
        await connection.installForTest(try snapshot(seq: 1))

        _ = try await connection.cachedCorePresentation()
        _ = try await connection.cachedCorePresentation()
        #expect(await connection.builds == 1)

        // A new event advances the snapshot sequence.
        try await connection.applyCoreNotification(json("{\"method\":\"event\",\"params\":{\"seq\":2,\"type\":\"title\",\"terminal\":\"t1\",\"data\":{\"title\":\"New\"}}}"))
        let updated = try await connection.cachedCorePresentation()
        #expect(await connection.builds == 2)
        #expect(updated.panes.first?.terminalTitle == "New")
        _ = try await connection.cachedCorePresentation()
        #expect(await connection.builds == 2)

        // Assigning layouts invalidates even with an unchanged sequence.
        await connection.setLayoutsForTest(["": .null])
        _ = try await connection.cachedCorePresentation()
        #expect(await connection.builds == 3)
    }

    @Test func missedWithSameSequenceDropsTheMemo() async throws {
        let connection = HerdrConnection()
        await connection.installForTest(try snapshot(seq: 5, addresses: ["t1"]))
        let before = try await connection.cachedCorePresentation()
        #expect(before.panes.map(\.paneId) == ["t1"])

        // `missed` replaces terminals at an equal sequence: the memo key alone would match.
        let missed = try json("{\"method\":\"missed\",\"params\":{\"seq\":5,\"terminals\":[\(terminal("t2"))]}}")
        #expect(try await connection.applyCoreNotification(missed))
        let after = try await connection.cachedCorePresentation()
        #expect(after.panes.map(\.paneId) == ["t2"])
    }

    @Test func newSubscriptionWithSameSequenceDropsTheMemo() async throws {
        let connection = HerdrConnection()
        await connection.installForTest(try snapshot(seq: 5, addresses: ["t1"]))
        _ = try await connection.cachedCorePresentation()

        try await connection.replaceCoreSnapshot(
            subscription: json("{\"seq\":5,\"terminals\":[\(terminal("t3"))]}")
        )
        let replaced = try await connection.cachedCorePresentation()
        #expect(replaced.panes.map(\.paneId) == ["t3"])
    }

    @Test func closeCoreClearsTheMemo() async throws {
        let connection = HerdrConnection()
        await connection.installForTest(try snapshot(seq: 1))
        _ = try await connection.cachedCorePresentation()
        await connection.closeCore()
        await #expect(throws: (any Error).self) { try await connection.cachedCorePresentation() }
        await connection.installForTest(try snapshot(seq: 1))
        _ = try await connection.cachedCorePresentation()
        #expect(await connection.builds == 2)
    }

    private func terminal(_ address: String) -> String {
        "{\"address\":\"\(address)\",\"title\":\"Terminal\",\"state\":\"live\",\"cwd\":\"/p\",\"created_ms\":1,\"status\":null,\"reported\":false,\"labels\":{}}"
    }

    private func snapshot(seq: Int, addresses: [String] = ["t1"]) throws -> CoreSnapshot {
        try CoreSnapshot(subscription: json("{\"seq\":\(seq),\"terminals\":[\(addresses.map(terminal).joined(separator: ","))]}"))
    }

    private func json(_ value: String) throws -> CoreJSON {
        try JSONDecoder().decode(CoreJSON.self, from: Data(value.utf8))
    }
}
