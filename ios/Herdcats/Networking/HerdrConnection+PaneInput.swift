import Citadel
import Crypto
import Foundation
import NIOCore
import NIOSSH

extension HerdrConnection {
    static func paneSendTextArguments(paneId: String, text: String) -> String {
        "pane send-text \(shellSafeArgument(paneId)) \(shellSafeArgument(text))"
    }

    static func paneSendKeysArguments(paneId: String, keys: [String]) -> String {
        let target = shellSafeArgument(paneId)
        let keyArgs = keys.map(shellSafeArgument).joined(separator: " ")
        return "pane send-keys \(target) \(keyArgs)"
    }

    func paneTypeTextUnlocked(
        paneId: String,
        text: String,
        owned: ConnectionGeneration? = nil
    ) async throws {
        if let owned { try requireGeneration(owned) }
        if backend == .core {
            guard let keys = Self.coreTypedKeys(text) else {
                throw HerdrError.invalidConfiguration(Self.coreUntypeableMessage)
            }
            try await paneSendKeysUnlocked(paneId: paneId, keys, owned: owned)
            return
        }
        try await runHerdr(
            Self.paneSendTextArguments(paneId: paneId, text: text),
            allowEmptyOutput: true
        )
    }

    static let coreUntypeableMessage = "Herdr Core can’t type that character directly. Use Compose to send it."

    /// Core has no raw-text input; typed text becomes key presses. Returns nil
    /// when a character has no exact Core key (shifted symbols, non-ASCII), so
    /// nothing is sent rather than a different character.
    static func coreTypedKeys(_ text: String) -> [String]? {
        let unshifted = Set("=[]\\;',./`-")
        var keys: [String] = []
        for character in text {
            guard character.isASCII else { return nil }
            switch character {
            case "a"..."z", "0"..."9": keys.append(String(character))
            case "A"..."Z": keys.append("shift+" + character.lowercased())
            case " ": keys.append("space")
            case "\n", "\r", "\r\n": keys.append("enter")
            case "\t": keys.append("tab")
            default:
                guard unshifted.contains(character) else { return nil }
                keys.append(String(character))
            }
        }
        return keys
    }

    /// Sends logical key presses into the pane (`pane send-keys`).
    ///
    /// Keys follow Herdr’s key vocabulary (e.g. `esc`, `ctrl+c`, `enter`).
    func paneSendKeys(paneId: String, _ keys: String...) async throws {
        try await paneSendKeys(paneId: paneId, keys)
    }

    /// Sends logical key presses into the pane (`pane send-keys`).
    func paneSendKeys(paneId: String, _ keys: [String]) async throws {
        let owned = generation
        try await paneInput.run(paneId: paneId) {
            try await self.paneSendKeysUnlocked(paneId: paneId, keys, owned: owned)
        }
    }

    /// Rail keys for one pane, sent in the pane's input lane. A one-shot token
    /// sends a plain `pane send-keys` (TUI) or `terminal.keys` (Herdr Core) for
    /// the generation captured when the key was tapped. A Live token is sent
    /// only while it is still the active Live session; an expired one is
    /// refused with `notConnected` and never sent as a plain command.
    func sendPaneKeys(_ keys: [String], session: PaneLiveInputSession) async throws {
        try requireGeneration(session.generation)
        try await paneInput.run(paneId: session.paneId) {
            try await self.paneSendRailKeysUnlocked(keys, session: session)
        }
    }

    func paneSendRailKeysUnlocked(_ keys: [String], session: PaneLiveInputSession) async throws {
        switch Self.railKeyPath(session: session, active: activeLiveSessions[session.paneId]) {
        case .liveShell:
            try await paneLiveSendKeysUnlocked(keys, session: session)
        case .command:
            try await paneSendKeysUnlocked(paneId: session.paneId, keys, owned: session.generation)
            try requireGeneration(session.generation)
        case .expired:
            throw HerdrError.notConnected
        }
    }

    /// Answers a numbered prompt with one key, only if a fresh read still
    /// shows the same prompt: the same question, command and file rows above
    /// the options, and the same options. The read is the poll's own read
    /// (`paneReadText`), parsed into the same rows, so the two can differ only
    /// if the screen changed. Runs in the pane's input lane, so it is ordered
    /// with every other input to the pane. Never retried.
    func paneAnswerChoice(
        paneId: String,
        expected: PaneChoicePrompt,
        option: Int,
        agent: String?,
        owned: ConnectionGeneration
    ) async throws -> PaneChoiceSendResult {
        // A stale connection fails before anything is read or sent.
        guard (try? requireGeneration(owned)) != nil else { return .notSent }
        return try await paneInput.run(paneId: paneId) {
            try await self.paneAnswerChoiceUnlocked(
                paneId: paneId, expected: expected, option: option, agent: agent, owned: owned
            )
        }
    }

    func paneAnswerChoiceUnlocked(
        paneId: String,
        expected: PaneChoicePrompt,
        option: Int,
        agent: String?,
        owned: ConnectionGeneration
    ) async throws -> PaneChoiceSendResult {
        try await PaneChoicePrompt.answer(
            expected: expected, option: option, agent: agent,
            read: {
                try await self.requireGeneration(owned)
                let screen = try await self.paneReadText(paneId: paneId)
                try await self.requireGeneration(owned)
                return screen
            },
            send: { key in
                try await self.paneSendKeysUnlocked(paneId: paneId, [key], owned: owned)
                try await self.requireGeneration(owned)
            }
        )
    }

    enum RailKeyPath: Equatable, Sendable {
        case liveShell
        case command
        case expired
    }

    static func railKeyPath(session: PaneLiveInputSession, active: PaneLiveInputSession?) -> RailKeyPath {
        switch session.kind {
        case .oneShot: .command
        case .live: active == session ? .liveShell : .expired
        }
    }

    func paneSendKeysUnlocked(
        paneId: String,
        _ keys: [String],
        owned: ConnectionGeneration? = nil
    ) async throws {
        if let owned { try requireGeneration(owned) }
        if backend == .core {
            _ = try await coreRequest("terminal.keys", params: ["terminal": .string(paneId), "keys": .array(keys.map(CoreJSON.string))], timeout: 30)
            return
        }
        try await runHerdr(
            Self.paneSendKeysArguments(paneId: paneId, keys: keys),
            allowEmptyOutput: true
        )
    }

    /// Submits a message so the conversation can continue on the Mac pane.
    ///
    /// Prefer `agent prompt` when the pane hosts an agent — it stages text with
    /// the agent's bracketed-paste mode and Enter, including Cursor follow-ups.
    /// Fall back to `pane run` for plain shell panes.
    ///
    /// Codex while `working` is special: its composer paste-burst window treats
    /// Enter immediately after a bracketed paste as a newline, so follow-ups
    /// never submit. Stage with raw `pane send-text`, wait out that window,
    /// then send a real Enter to steer the turn.
    func paneSubmit(
        paneId: String,
        text: String,
        agent: String?,
        status: AgentStatus? = nil
    ) async throws {
        let owned = generation
        try await paneInput.run(paneId: paneId) {
            try await self.paneSubmitUnlocked(
                paneId: paneId, text: text, agent: agent, status: status, owned: owned
            )
        }
    }

    static func shouldTypeAndEnterForTimelinePrompt(agent: String, agentStatus: String?) -> Bool {
        agent == "codex" && agentStatus == "working"
    }

    func paneSubmitWorkingCodexPromptUnlocked(
        paneId: String,
        text: String,
        owned: ConnectionGeneration
    ) async throws {
        try await paneTypeTextUnlocked(paneId: paneId, text: text, owned: owned)
        try await Task.sleep(for: .milliseconds(350))
        try requireGeneration(owned)
        try await paneSendKeysUnlocked(paneId: paneId, ["enter"], owned: owned)
    }

    func paneSubmitUnlocked(
        paneId: String,
        text: String,
        agent: String?,
        status: AgentStatus?,
        owned: ConnectionGeneration
    ) async throws {
        try requireGeneration(owned)
        if backend == .core {
            _ = try await coreRequest("terminal.send", params: ["terminal": .string(paneId), "text": .string(text)], timeout: 30)
            return
        }
        // Cursor prompts need the bridge's screen guard; never type into it blind.
        guard agent != "cursor" else { throw HerdrError.invalidConfiguration(CursorPromptPolicy.bridgeMessage) }
        if Self.shouldTypeAndEnterForTimelinePrompt(agent: agent ?? "", agentStatus: status?.rawValue) {
            try await paneSubmitWorkingCodexPromptUnlocked(paneId: paneId, text: text, owned: owned)
            return
        }
        if agent != nil {
            do {
                try await runHerdr(
                    "agent prompt \(Self.shellSafeArgument(paneId)) \(Self.shellSafeArgument(text))",
                    timeout: 30,
                    allowEmptyOutput: true
                )
            } catch where agent == "codex" && Self.isAgentBlocked(error) {
                // Herdr refuses prompts while blocked; a Codex question may
                // still take a typed answer ("Other" / notes).
                guard try await paneAnswerCodexQuestionUnlocked(
                    paneId: paneId, text: text, owned: owned
                ) else { throw error }
            }
        } else {
            try await paneSendTextUnlocked(paneId: paneId, text: text)
        }
    }

    /// Types `text` as the answer to a blocked Codex question, opening its
    /// answer field first when needed. Returns false, sending nothing, unless
    /// the screen shows a question answer field (never an approval menu).
    func paneAnswerCodexQuestionUnlocked(
        paneId: String,
        text: String,
        owned: ConnectionGeneration
    ) async throws -> Bool {
        let answer = CodexQuestionInput.answerText(text)
        guard !answer.isEmpty else { return false }
        var state = CodexQuestionInput.detect(try await paneReadVisibleText(paneId: paneId))
        try requireGeneration(owned)
        if let keys = state?.openingKeys {
            try await paneSendKeysUnlocked(paneId: paneId, keys, owned: owned)
            try await Task.sleep(for: .milliseconds(250))
            try requireGeneration(owned)
            state = CodexQuestionInput.detect(try await paneReadVisibleText(paneId: paneId))
            try requireGeneration(owned)
        }
        guard state == .answerField else { return false }
        try await paneTypeTextUnlocked(paneId: paneId, text: answer, owned: owned)
        try await Task.sleep(for: .milliseconds(350))
        try requireGeneration(owned)
        try await paneSendKeysUnlocked(paneId: paneId, ["enter"], owned: owned)
        return true
    }

    func paneReadVisibleText(paneId: String) async throws -> String {
        if backend == .core { return try await paneReadText(paneId: paneId, lines: 0) }
        return try await runHerdr(
            "pane read \(Self.shellSafeArgument(paneId)) --source visible --lines 60 --format text",
            allowEmptyOutput: true
        )
    }

    static func isAgentBlocked(_ error: Error) -> Bool {
        if case let HerdrError.api(code, _) = error { return code == "agent_blocked" }
        return String(describing: error).contains("agent_blocked")
    }

    /// Uploads image bytes to the Herdr machine and returns the absolute remote path.
    ///
    /// Stores attachments in the remote user's private cache, outside the pane
    /// repository. SFTP creates the final UUID path exclusively.
    func uploadAttachment(
        data: Data,
        fileExtension: String,
        paneId: String? = nil
    ) async throws -> String {
        if backend == .core {
            guard let paneId else { throw HerdrError.invalidConfiguration("Select a Herdr Core terminal before uploading an image.") }
            return try await coreUploadAttachment(data: data, fileExtension: fileExtension, terminal: paneId)
        }
        guard let client else { throw HerdrError.notConnected }
        guard !data.isEmpty else {
            throw HerdrError.invalidConfiguration("Image data is empty.")
        }
        let owned = generation
        let ext = Self.sanitizedAttachmentExtension(fileExtension)
        let fileName = "\(UUID().uuidString).\(ext)"
        let directory = try await resolveAttachmentDirectory(owned: owned)
        try requireGeneration(owned)
        let remotePath = "\(directory)/\(fileName)"

        try await prepareAttachmentDirectory(directory, owned: owned)
        try requireGeneration(owned)

        #if DEBUG
        print("[HC] sftp upload \(data.count) bytes → \(remotePath)")
        #endif
        try await withTimeout(
            seconds: 60,
            label: "upload attachment",
            onTimeout: { [weak self] in
                await self?.timeoutTeardown(expected: owned)
            },
            operation: {
            try await client.withSFTP { sftp in
                var attrs = SFTPFileAttributes()
                attrs.permissions = 0o600
                try await sftp.withFile(
                    filePath: remotePath,
                    flags: [.write, .create, .forceCreate],
                    attributes: attrs
                ) { file in
                    try await file.write(ByteBuffer(data: data))
                }
            }
            }
        )
        guard generation == owned else { throw HerdrError.notConnected }
        return remotePath
    }
}

private struct TimelinePromptAgentResult: Decodable {
    let agent: TimelinePromptAgent
}
private struct TimelinePromptAgent: Decodable {
    let paneId: String
    let terminalId: String
    let agent: String
    let agentStatus: String
    let agentSession: Reference?
    struct Reference: Decodable {
        let agent: String
        let source: String
        let kind: String
        let value: String
    }
    enum CodingKeys: String, CodingKey {
        case paneId = "pane_id", terminalId = "terminal_id", agent
        case agentStatus = "agent_status", agentSession = "agent_session"
    }
}
extension HerdrConnection {
    /// Native composition uses the existing prompt API, with a fresh occupant
    /// check. It never falls back to shell input or answers a blocked request.
    func submitTimelinePrompt(text: String, identity: AgentTimelineIdentity, owned: ConnectionGeneration) async throws {
        guard identity.agent != "cursor" else { throw HerdrError.invalidConfiguration(CursorPromptPolicy.bridgeMessage) }
        try await paneInput.run(paneId: identity.paneId) {
            try await self.requireGeneration(owned)
            let live = try await self.fetch(TimelinePromptAgentResult.self,args:"agent get \(Self.shellSafeArgument(identity.paneId))").agent
            let reference = live.agentSession
            let sessionId = reference?.kind == "path" ? URL(fileURLWithPath:reference?.value ?? "").deletingPathExtension().lastPathComponent : reference?.value
            guard live.paneId == identity.paneId, live.terminalId == identity.terminalId,
                  TimelineAgentAvailability.matchesSession(agent: live.agent, referenceAgent: reference?.agent, source: reference?.source, identityAgent: identity.agent, referenceKind: reference?.kind ?? ""),
                  TimelineAgentAvailability.supports(agent: identity.agent),
                  sessionId == identity.nativeSessionId,
                  TimelineComposePolicy.canSend(identity:identity,paneId:live.paneId,status:live.agentStatus,connected:true)
            else {throw AgentBridgeError.identityMismatch}
            try await self.requireGeneration(owned)
            try Task.checkCancellation()
            if Self.shouldTypeAndEnterForTimelinePrompt(agent: identity.agent, agentStatus: live.agentStatus) {
                try await self.paneSubmitWorkingCodexPromptUnlocked(paneId: identity.paneId, text: text, owned: owned)
                return
            }
            _ = try await self.executeHerdr("agent prompt \(Self.shellSafeArgument(identity.paneId)) \(Self.shellSafeArgument(text))",timeout:30,allowEmptyOutput:true,expectedGeneration:owned)
        }
    }
}
