import Citadel
import Foundation

extension HerdrConnection {
    /// Resolved by the remote login user's shell, without a PTY. Protocol stdout
    /// is never merged with stderr, and this command has no legacy fallback.
    static var coreConnectCommand: String {
        let script = """
        export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:$PATH"
        B=$(command -v hc 2>/dev/null)
        if [ -z "$B" ]; then
          printf '%s\\n' 'Herdr Core (hc) was not found. Install and start Core on this machine.' >&2
          exit 127
        fi
        exec "$B" connect
        """
        return "exec /bin/sh -c \(shellSafeArgument(script))"
    }

    static let tuiFoundMarker = "HERDRCAT_HAS_TUI"
    static let coreFoundMarker = "HERDRCAT_HAS_CORE"

    /// Auto mode: looks for each runtime's CLI on the same paths its connect uses.
    static var backendProbeCommand: String {
        let script = """
        export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:$PATH"
        command -v herdr >/dev/null 2>&1 && echo \(tuiFoundMarker)
        command -v hc >/dev/null 2>&1 && echo \(coreFoundMarker)
        exit 0
        """
        return "exec /bin/sh -c \(shellSafeArgument(script))"
    }

    static func detectedBackends(_ output: String) -> Set<ConnectionBackend> {
        let lines = Set(output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        var found: Set<ConnectionBackend> = []
        if lines.contains(tuiFoundMarker) { found.insert(.tui) }
        if lines.contains(coreFoundMarker) { found.insert(.core) }
        return found
    }

    /// Pass `expected` to run the check only on that attempt's connection.
    func detectBackends(expected: ConnectionGeneration? = nil) async throws -> Set<ConnectionBackend> {
        let owned = expected ?? generation
        let client = try slot.ownedClient(owned)
        let command = Self.backendProbeCommand
        let buffer = try await withTimeout(seconds: 10, label: "Herdr runtime check", operation: {
            try await client.executeCommand(command, maxResponseSize: 64 * 1024)
        })
        try requireGeneration(owned)
        return Self.detectedBackends(String(buffer: buffer))
    }

    /// Whether the saved runtime's first check failed the way it does when
    /// that runtime isn't installed.
    static func mayMeanRuntimeIsMissing(_ error: Error, backend: ConnectionBackend) -> Bool {
        switch backend {
        case .tui: (error as? HerdrError) == .herdrNotFound
        case .core: (error as? HerdrError) == .coreStartupClosed
        }
    }

    /// The error to report after the runtime check. Keeps `error` when the
    /// check could not run (`found` is nil) or found the saved runtime.
    /// Otherwise names the runtime the machine has instead, if any.
    static func missingRuntimeError(_ error: Error, saved: ConnectionBackend, found: Set<ConnectionBackend>?) -> Error {
        guard let found, !found.contains(saved) else { return error }
        return HerdrError.runtimeNotInstalled(saved: saved, available: ConnectionBackend.allCases.first(where: found.contains))
    }

    func setRuntimeChangeHandler(_ handler: @escaping @Sendable (ConnectionGeneration) -> Void) {
        runtimeChangeHandler = handler
    }

    func requireTUIFeature() throws {
        guard backend == .tui else {
            throw HerdrError.invalidConfiguration("This action is unavailable in Herdr Core mode. Manage the desktop layout in Herdr.")
        }
    }

    /// One opening operation is shared by concurrent list/readiness queries.
    func startCore() async throws -> CoreRPCClient {
        try requireGeneration(generation)
        guard backend == .core else { throw HerdrError.invalidConfiguration("Select Herdr Core for this connection.") }
        if let coreOpening {
            let owned = generation
            let token = coreSessionID
            try await coreOpening.value
            try requireGeneration(owned)
            guard coreSessionID == token, let coreRPC else { throw HerdrError.notConnected }
            return coreRPC
        }
        if let coreRPC, coreSnapshot != nil { return coreRPC }
        let owned = generation
        let token = UUID()
        coreSessionID = token
        coreStartupClosed = false
        let client = try slot.ownedClient(owned)
        let rpc = CoreRPCClient(onNotification: { [weak self] message in
            try await self?.receiveCoreNotification(message, owned: owned, session: token)
        }, onClose: { [weak self] in
            await self?.coreStreamClosed(owned: owned, session: token)
        })
        coreRPC = rpc
        let opening = Task { [weak self] in
            guard let self else { throw HerdrError.notConnected }
            let hello = try await rpc.open(client: client, command: Self.coreConnectCommand)
            let required = Set(["terminal.list", "terminal.read", "terminal.send", "terminal.keys", "terminal.interrupt", "events.subscribe"])
            let methods = Set(hello["methods"].arrayValue?.compactMap(\.stringValue) ?? [])
            guard hello["generation"].intValue == 1, required.isSubset(of: methods) else {
                throw HerdrError.invalidConfiguration("This Core version does not support the terminal API Herdcats needs. Update Herdr Core and try again.")
            }
            let subscription = try await rpc.subscribeEvents()
            try await self.installCoreSnapshot(subscription, hello: hello, owned: owned, session: token)
            try await self.reloadCoreDocuments(owned: owned, session: token)
            let isOpen = await rpc.isOpen
            try await self.finishCoreStartup(isOpen: isOpen, owned: owned, session: token)
        }
        coreOpening = opening
        do {
            try await opening.value
            try requireGeneration(owned)
            guard coreSessionID == token else { throw HerdrError.notConnected }
            return rpc
        } catch {
            let startupFailed = coreSnapshot == nil
            if coreSessionID == token { closeCore() }
            await rpc.close()
            if startupFailed, (error as? CoreRPCError) == .closed {
                throw HerdrError.coreStartupClosed
            }
            throw error
        }
    }

    /// Promotion belongs to the shared startup operation, so all concurrent
    /// callers observe the same readiness boundary and close notifications
    /// become active before any of their awaits can return.
    private func finishCoreStartup(isOpen: Bool, owned: ConnectionGeneration, session: UUID) throws {
        try requireGeneration(owned)
        guard coreSessionID == session else { throw HerdrError.notConnected }
        guard isOpen, !coreStartupClosed else { throw CoreRPCError.closed }
        coreOpening = nil
    }

    private func installCoreSnapshot(_ value: CoreJSON, hello: CoreJSON, owned: ConnectionGeneration, session: UUID) throws {
        try requireGeneration(owned)
        guard coreSessionID == session else { throw HerdrError.notConnected }
        coreHello = hello
        try replaceCoreSnapshot(subscription: value)
        for message in earlyCoreNotifications { try applyCoreNotification(message) }
        earlyCoreNotifications = []
    }

    /// Installs a fresh subscription snapshot. Its sequence may equal the old
    /// one's (sequences reset per Core process), so the memo is dropped.
    func replaceCoreSnapshot(subscription value: CoreJSON) throws {
        coreSnapshot = try CoreSnapshot(subscription: value)
        invalidateCorePresentation()
    }

    /// Applies one event to the snapshot and drops the memo when it asks for
    /// a refetch (`missed` replacement or a layout document change).
    @discardableResult
    func applyCoreNotification(_ value: CoreJSON) throws -> Bool {
        let refetch = try coreSnapshot?.apply(value) ?? false
        if refetch { invalidateCorePresentation() }
        return refetch
    }

    private func receiveCoreNotification(_ value: CoreJSON, owned: ConnectionGeneration, session: UUID) throws {
        guard slot.matches(owned), coreSessionID == session else { return }
        guard coreSnapshot != nil else {
            guard earlyCoreNotifications.count < 1024 else {
                throw HerdrError.unexpectedResponse("Herdr Core sent too many events before its snapshot.")
            }
            earlyCoreNotifications.append(value)
            return
        }
        let refetch = try applyCoreNotification(value)
        if refetch {
            coreDocumentsRevision &+= 1
            scheduleCoreDocumentReload(owned: owned, session: session)
        }
        if value["method"].stringValue != "heartbeat" { runtimeChangeHandler?(owned) }
    }

    private func scheduleCoreDocumentReload(owned: ConnectionGeneration, session: UUID) {
        guard coreDocumentTask == nil else { return }
        coreDocumentTask = Task { [weak self] in
            guard let self else { return }
            await self.runCoreDocumentReload(owned: owned, session: session)
        }
    }

    private func runCoreDocumentReload(owned: ConnectionGeneration, session: UUID) async {
        // Coalesce event bursts; repeat if another doc changed during an await.
        while !Task.isCancelled, slot.matches(owned), coreSessionID == session {
            let revision = coreDocumentsRevision
            do { try await reloadCoreDocuments(owned: owned, session: session) }
            catch { break }
            guard revision != coreDocumentsRevision else { break }
        }
        guard coreSessionID == session else { return }
        coreDocumentTask = nil
        runtimeChangeHandler?(owned)
    }

    private func reloadCoreDocuments(owned: ConnectionGeneration, session: UUID) async throws {
        guard let rpc = coreRPC, coreSessionID == session else { throw HerdrError.notConnected }
        let methods = Set(coreHello["methods"].arrayValue?.compactMap(\.stringValue) ?? [])
        guard methods.contains("doc.get") else { coreLayouts = [:]; return }
        var layouts: [String: CoreJSON] = [:]
        let machines = Set(coreSnapshot?.terminals.keys.compactMap { address in
            address.contains("/") ? String(address.split(separator: "/", maxSplits: 1)[0]) : nil
        } ?? [])
        for machine in [""] + machines.sorted() {
            var params: [String: CoreJSON] = ["name": .string("herdr-app")]
            if !machine.isEmpty { params["on"] = .string(machine) }
            do {
                let document = try await rpc.request("doc.get", params: params, timeout: 5, closeOnTimeout: false)
                try requireGeneration(owned)
                guard coreSessionID == session else { throw HerdrError.notConnected }
                layouts[machine] = document["value"]
            } catch {
                try requireGeneration(owned)
                // Layout is optional. A missing/unavailable app/machine still
                // leaves its terminals accessible in Other terminals.
            }
        }
        try requireGeneration(owned)
        guard coreSessionID == session else { throw HerdrError.notConnected }
        coreLayouts = layouts
    }

    private func coreStreamClosed(owned: ConnectionGeneration, session: UUID) {
        guard slot.matches(owned), coreSessionID == session else { return }
        // During startup the opening task owns the actionable readiness error.
        // A generic disconnect here would invalidate AppModel's attempt before
        // its catch can report a missing/incompatible Core. startCore checks
        // transport liveness before promoting this session.
        guard coreOpening == nil else {
            coreStartupClosed = true
            return
        }
        // Fail this SSH generation even if only its exec channel closed.
        // Existing AppModel recovery then reconnects and obtains a new snapshot.
        let handler = disconnectHandler
        invalidateAndTeardown(expected: owned)
        Task.detached { handler?() }
    }

    func closeCore() {
        coreSessionID = nil
        coreStartupClosed = false
        coreOpening?.cancel()
        coreOpening = nil
        coreDocumentTask?.cancel()
        coreDocumentTask = nil
        let old = coreRPC
        coreRPC = nil
        coreSnapshot = nil
        invalidateCorePresentation()
        coreHello = .null
        coreLayouts = [:]
        earlyCoreNotifications = []
        if let old { Task { await old.close() } }
    }

    /// True while Core mode has a live event subscription: snapshot installed
    /// and startup finished. Events then drive refreshes through
    /// `runtimeChangeHandler`.
    var coreEventsOpen: Bool {
        backend == .core && coreSessionID != nil && coreOpening == nil && coreSnapshot != nil
    }

    func corePresentation() async throws -> CoreHierarchy {
        _ = try await startCore()
        return try cachedCorePresentation()
    }

    /// Builds the hierarchy at most once per snapshot sequence and layouts
    /// revision, so one refresh's workspace/agent/tab/pane queries share it.
    func cachedCorePresentation() throws -> CoreHierarchy {
        guard let coreSnapshot else { throw HerdrError.notConnected }
        if let memo = corePresentationMemo,
           memo.seq == coreSnapshot.seq, memo.layoutsRevision == coreLayoutsRevision {
            return memo.value
        }
        let value = coreSnapshot.presentation(layout: coreLayouts[""], remoteLayouts: coreLayouts.filter { !$0.key.isEmpty })
        #if DEBUG
        corePresentationBuilds += 1
        #endif
        corePresentationMemo = (coreSnapshot.seq, coreLayoutsRevision, value)
        return value
    }

    /// The snapshot was replaced (new subscription, `missed`, close) or a
    /// document changed, so a same-sequence memo can no longer be trusted.
    func invalidateCorePresentation() {
        corePresentationMemo = nil
    }

    func coreRequest(_ method: String, params: [String: CoreJSON], timeout: TimeInterval = 15,
                     expectedGeneration: ConnectionGeneration? = nil) async throws -> CoreJSON {
        let owned = expectedGeneration ?? generation
        try requireGeneration(owned)
        let rpc = try await startCore()
        try requireGeneration(owned)
        let result = try await rpc.request(method, params: params, timeout: timeout)
        try requireGeneration(owned)
        return result
    }

    func coreInterrupt(terminal: String) async throws {
        let owned = generation
        try await paneInput.run(paneId: terminal) {
            _ = try await self.coreRequest("terminal.interrupt", params: ["terminal": .string(terminal)], expectedGeneration: owned)
        }
    }

    func coreUploadAttachment(data: Data, fileExtension: String, terminal: String) async throws -> String {
        guard !data.isEmpty, data.count <= 8 * 1024 * 1024 else {
            throw HerdrError.invalidConfiguration("Herdr Core images must be between 1 byte and 8 MB.")
        }
        let result = try await coreRequest("terminal.put", params: [
            "terminal": .string(terminal), "name": .string("\(UUID().uuidString).\(Self.sanitizedAttachmentExtension(fileExtension))"),
            "data": .string(data.base64EncodedString())
        ], timeout: 60)
        guard let path = result["path"].stringValue, !path.isEmpty else {
            throw HerdrError.unexpectedResponse("Herdr Core returned no attachment path.")
        }
        return path
    }
}
