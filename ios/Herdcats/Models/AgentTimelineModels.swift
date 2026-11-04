import Foundation
import Observation
import OSLog

@Observable final class TimelineBridgeUpgrade {
    var bridgeVersion: String?
    var requested: Bool

    init(bridgeVersion: String? = nil, requested: Bool = false) {
        self.bridgeVersion = bridgeVersion
        self.requested = requested
    }

    func requestUpgrade() {
        requested = true
    }
}

enum AgentBridgeError: Error, LocalizedError, Equatable, Sendable {
    case invalidFrame, frameTooLarge, incompleteFrame, protocolMismatch, sequenceGap, identityMismatch
    case closed, timeout
    case unavailable(String)
    case questionFailure(code: String, stepsSent: Int?)
    var code: String {
        switch self {
        case .unavailable(let code): return code
        case .questionFailure(let code, _): return code
        case .timeout: return "bridge_timeout"
        case .protocolMismatch: return "protocol_mismatch"
        default: return "bridge_unavailable"
        }
    }
    var errorDescription: String? { "Timeline unavailable. Open Terminal to continue." }
}
struct AgentTimelineEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let kind: String
    let text: String
    let role: String?
    let toolName: String?
    let status: String?
    let details: String?
    let truncated: Bool
    var contentRef: String? = nil
    var recordRefs: [String]? = nil

    /// Only Codex turn-abort markers render as the interrupted status line.
    /// Error records are also assistant/failed but keep normal message
    /// rendering, so the marker is keyed on the entry id.
    var isTurnInterrupted: Bool {
        id.hasPrefix("turn_aborted:") && role == "assistant" && status == "failed"
    }
}
struct AgentTimelineIdentity: Codable, Equatable, Sendable {
    let paneId: String
    let terminalId: String
    let agent: String
    let nativeSessionId: String
    var nativeInstanceId: String? = nil
}
struct AgentBridgeCapabilities: Codable, Equatable, Sendable {
    let claudeTimeline: Bool
    var agy: Bool = false
    var pi: Bool = false
    var cursor: Bool = false
    var cursorPrompts: Bool = false
    var codexTimeline: Bool? = false
    var codexDaemonConfig: Bool? = false
    var codexDaemonStop: Bool? = false
    var questions: Bool? = nil
    var approvals: Bool? = nil
    var recordContent: Bool? = nil
    var modelControl: Bool = false

    init(
        claudeTimeline: Bool,
        agy: Bool = false,
        pi: Bool = false,
        cursor: Bool = false,
        cursorPrompts: Bool = false,
        codexTimeline: Bool? = false,
        codexDaemonConfig: Bool? = false,
        codexDaemonStop: Bool? = false,
        recordContent: Bool? = nil,
        approvals: Bool? = nil,
        questions: Bool? = nil,
        modelControl: Bool = false
    ) {
        self.agy = agy
        self.pi = pi
        self.cursor = cursor
        self.cursorPrompts = cursorPrompts
        self.claudeTimeline = claudeTimeline
        self.modelControl = modelControl
        self.codexTimeline = codexTimeline
        self.codexDaemonConfig = codexDaemonConfig
        self.codexDaemonStop = codexDaemonStop
        self.questions = questions
        self.approvals = approvals
        self.recordContent = recordContent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.agy = try container.decodeIfPresent(Bool.self, forKey: .agy) ?? false
        self.pi = try container.decodeIfPresent(Bool.self, forKey: .pi) ?? false
        self.cursor = try container.decodeIfPresent(Bool.self, forKey: .cursor) ?? false
        self.cursorPrompts = try container.decodeIfPresent(Bool.self, forKey: .cursorPrompts) ?? false
        self.modelControl = try container.decodeIfPresent(Bool.self, forKey: .modelControl) ?? false
        self.claudeTimeline = try container.decode(Bool.self, forKey: .claudeTimeline)
        self.codexTimeline = try container.decodeIfPresent(Bool.self, forKey: .codexTimeline) ?? false
        self.codexDaemonConfig = try container.decodeIfPresent(Bool.self, forKey: .codexDaemonConfig) ?? false
        self.codexDaemonStop = try container.decodeIfPresent(Bool.self, forKey: .codexDaemonStop) ?? false
        self.questions = try container.decodeIfPresent(Bool.self, forKey: .questions)
        self.approvals = try container.decodeIfPresent(Bool.self, forKey: .approvals)
        self.recordContent = try container.decodeIfPresent(Bool.self, forKey: .recordContent)
    }
}

struct CodexDaemonConfigResult: Decodable, Equatable, Sendable {
    let status: String?
    let backup: String?
    let error: String?
    /// `stopped`/`not_running`/`stop_failed`/`unknown`; present only with
    /// --stop-running and only when the config step succeeded.
    var daemon: String? = nil
    var updater: String? = nil

    static func parse(_ raw: String) throws -> CodexDaemonConfigResult {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
        guard let data = line.data(using: .utf8) else {
            throw HerdrError.unexpectedResponse("Invalid response encoding")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CodexDaemonConfigResult.self, from: data)
    }

    static func message(for result: CodexDaemonConfigResult) -> String {
        if let err = result.error {
            switch err {
            case "config_invalid":
                return "Could not update Codex config: config.toml contains invalid TOML."
            case "features_not_table":
                return "Could not update Codex config: features in config.toml is not a table."
            case "daemon_setting_unsupported":
                return "Could not update Codex config: daemon_auto_start in config.toml has an unsupported shape. Edit it by hand."
            case "config_symlink":
                return "Could not update Codex config: config.toml is a symbolic link."
            case "write_failed":
                return "Could not update Codex config: failed to write file."
            case "verification_failed":
                return "Could not update Codex config: verification failed, restored from backup."
            case "helper_missing":
                return "Could not update Codex config: herdcats-bridge was not found."
            default:
                return "Could not update Codex config: \(err)."
            }
        }
        // The updater is checked first: the bridge never runs `daemon stop`
        // while the updater is alive (it TERM-and-waits precisely so the
        // updater cannot restart the daemon), so an updater failure is the
        // root cause whenever it appears — including the both-stop_failed
        // shape — and recovery must go through the updater-aware command.
        if result.updater == "stop_failed" || result.updater == "unknown" {
            let updaterSurvived = result.updater == "stop_failed"
            let daemonOff = result.daemon == "stopped" || result.daemon == "not_running"
            switch (updaterSurvived, daemonOff) {
            case (true, true):
                return "Codex's shared server was stopped, but its updater is still running and may restart it. Copy the turn-off command below and run it on this computer to stop the updater too, then restart Codex in this pane."
            case (true, false):
                return "Herdcats couldn't stop the updater that keeps Codex's shared server running. Copy the turn-off command below and run it on this computer to stop the updater and the server, then restart Codex in this pane."
            case (false, true):
                return "Codex's shared server was stopped, but Herdcats couldn't confirm the state of its updater, which may restart it. Copy the turn-off command below and run it on this computer, then restart Codex in this pane."
            case (false, false):
                return "Herdcats couldn't confirm the state of Codex's shared server or its updater. Copy the turn-off command below and run it on this computer, then restart Codex in this pane."
            }
        }
        if result.daemon == "stop_failed" {
            return "Codex's shared server is still running. Run `codex app-server daemon stop` on this computer, then restart Codex in this pane."
        }
        if result.daemon == "unknown" {
            return "Herdcats couldn't confirm the running server belongs to Codex, so it left it running. Run `codex app-server daemon stop` on this computer, then restart Codex in this pane."
        }
        switch result.status {
        case "codex_not_installed":
            return "Codex directory was not found on this host."
        default:
            // stopped, not_running, or a legacy reply without daemon fields.
            return "Codex's shared server is off. Quit Codex in this pane and start it again so Herdcats can identify the session."
        }
    }

    /// The updater survived the stop or could not be verified — on its own or
    /// alongside a daemon failure (the bridge refuses to stop the daemon
    /// while the updater is alive). Codex's own `daemon stop` cannot address
    /// the updater, so recovery always goes through the updater-aware bridge
    /// command.
    static func showsUpdaterStopCommand(for result: CodexDaemonConfigResult) -> Bool {
        guard result.error == nil else { return false }
        return result.updater == "stop_failed" || result.updater == "unknown"
    }

    /// The daemon itself survived the stop (or could not be verified) while
    /// the updater was handled: pair the message with Codex's own stop
    /// command.
    static func showsStopCommand(for result: CodexDaemonConfigResult) -> Bool {
        guard result.error == nil, !showsUpdaterStopCommand(for: result) else { return false }
        return result.daemon == "stop_failed" || result.daemon == "unknown"
    }
}
struct AgentBridgePayload: Codable, Sendable {
    var `protocol`: Int?
    var bridgeVersion: String?
    var version: String?
    var epoch: String?
    var capabilities: AgentBridgeCapabilities?
    var identity: AgentTimelineIdentity?
    var generation: UInt64?
    var entries: [AgentTimelineEntry]?
    var evictedIds: [String]?
    var hasMore: Bool?
    var before: String?
    var agentStatus: String?
    var unknownRecords: Int?
    var droppedEntries: Int?
    var delayed: Bool?
    var paneId: String?
    var code: String?
    var codexDaemon: String?
    var contentRef: String?
    var offset: Int?
    var nextOffset: Int?
    var total: Int?
    var hex: String?
    var requestId: String?
    var kind: String?
    var agent: String?
    var toolName: String?
    var command: String?
    var description: String?
    var justification: String?
    var environment: String?
    var message: String?
    var dialogOptions: [String]?
    var value: String?
    var title: String?
    var options: [AgentApprovalOption]?
    var selected: Int?
    var sent: String?
    var confirmed: Bool?
    var questionKind: String?
    var questions: [AgentQuestion]?
    var step: AgentQuestionStep?
    var fresh: Bool?
    var countdown: String?
    var model: AgentModelOption?
    var effort: String?
    var models: [AgentModelOption]?
    var efforts: [AgentEffortOption]?
    var catalog: AgentModelCatalogInfo?
    var applied: AgentModelPair?
    var error: String?
}
/// Where a model list came from. Only a fresh, complete list is verified
/// availability; cached or fallback lists are labelled as such.
struct AgentModelCatalogInfo: Codable, Equatable, Sendable {
    var source: String?
    var fresh: Bool?
    var complete: Bool?
    var error: String?

    /// A short note for lists that aren't freshly verified; nil when verified.
    var note: String? {
        if complete == true, fresh == true { return nil }
        switch source {
        case "cache": return "Showing saved model choices. They may be out of date."
        case "fallback": return "Showing common model names. Your account may offer different choices."
        case "unavailable": return "Available models couldn't be checked. Only the current model is shown."
        default: return "These model choices couldn't be verified."
        }
    }
}
struct AgentBridgeRemoteError: Codable, Sendable {
    let code: String
    var stepsSent: Int? = nil
}
struct AgentBridgeFrame: Decodable, Sendable {
    var id: String?
    var result: AgentBridgePayload?
    var error: AgentBridgeRemoteError?
    var event: String?
    var epoch: String?
    var seq: UInt64?
    var data: AgentBridgePayload?
    static func decode(_ bytes: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: bytes)
    }
}
struct AgentBridgeFramer {
    private var bytes = Data()
    let limit: Int
    init(limit: Int = 1024 * 1024) { self.limit = limit }
    mutating func append(_ chunk: Data) throws -> [AgentBridgeFrame] {
        var frames: [AgentBridgeFrame] = []
        var cursor = chunk.startIndex

        while cursor < chunk.endIndex {
            if let newlineIndex = chunk[cursor...].firstIndex(of: 0x0A) {
                let segment = chunk[cursor..<newlineIndex]
                cursor = chunk.index(after: newlineIndex)

                if bytes.count + segment.count > limit {
                    throw AgentBridgeError.frameTooLarge
                }

                bytes.append(segment)
                do {
                    frames.append(try AgentBridgeFrame.decode(bytes))
                } catch {
                    bytes.removeAll(keepingCapacity: true)
                    throw AgentBridgeError.invalidFrame
                }
                bytes.removeAll(keepingCapacity: true)
            } else {
                let segment = chunk[cursor...]
                cursor = chunk.endIndex

                if bytes.count + segment.count > limit {
                    throw AgentBridgeError.frameTooLarge
                }

                bytes.append(segment)
            }
        }
        return frames
    }
    func finish() throws {
        if !bytes.isEmpty { throw AgentBridgeError.incompleteFrame }
    }
}

/// Readiness plus transport identity; "connecting" must not share the stream
/// key of "connected" even though neither phase is classified as offline.
struct AgentTimelineConnectionState: Equatable, Sendable {
    let phase: AppModel.Phase
    let generation: ConnectionGeneration?
    var isReady: Bool {
        if case .connected = phase { return true }
        return false
    }
    func requireCurrent(_ current: Self) throws {
        guard isReady, self == current else { throw AgentBridgeError.closed }
    }
}

enum TimelineComposePolicy {
    /// Native history is optional; absent history uses the existing pane input
    /// path. A present identity must still pass native session/status checks.
    static func canCompose(identity: AgentTimelineIdentity?, paneId: String, status: String?, connected: Bool) -> Bool {
        connected && (identity == nil || canSend(identity: identity, paneId: paneId, status: status, connected: connected))
    }

    static func canSend(identity: AgentTimelineIdentity?, paneId: String, status: String?, connected: Bool)
        -> Bool
    {
        // Cursor is never typed into mid-turn: the bridge checks the screen for an
        // idle, empty composer, so a working pane cannot queue a message.
        let allowed = identity?.agent == "cursor" ? ["idle", "done"] : ["idle", "done", "working"]
        return connected && identity?.paneId == paneId && TimelineAgentAvailability.supports(agent: identity?.agent)
            && allowed.contains(status ?? "")
    }
}

/// Phone prompts to Cursor go through the bridge, which reads the terminal first.
enum CursorPromptPolicy {
    /// Cursor runs a message that starts with "/" as one of its own commands
    /// (/quit, /model, /new ...) instead of sending it to the model. The phone
    /// refuses such a message rather than risk running one by accident.
    static func refusesSlashCommand(agent: String?, text: String) -> Bool {
        agent == "cursor" && text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
    }
    static let slashMessage = "Cursor treats a message that starts with “/” as a command, so Herdcats won't send it. Rephrase the message, or use Terminal."
    static let bridgeMessage = "Herdcats can only send Cursor messages through its conversation view, and it isn't connected to this Cursor chat right now. Check the connection or the message above the chat, or use Terminal."
    static func message(forCode code: String?) -> String {
        switch code {
        case "approval_pending": return "Cursor is waiting for a permission decision. Answer it first, or use Terminal."
        case "question_pending": return "Cursor is waiting for an answer to its question. Answer it first, or use Terminal."
        case "composer_not_empty": return "Clear Cursor's input box at the desk first, or use Terminal."
        case "agent_busy": return "Cursor is busy. Wait for it to finish, or use Terminal."
        case "picker_open": return "A Cursor menu is open at the desk. Close it first, or use Terminal."
        case "screen_unrecognized", "screen_unavailable": return "Herdcats can't tell what Cursor is showing. Use Terminal."
        case "slash_command_refused": return slashMessage
        case "stale": return "Cursor changed since this screen loaded. Check the conversation and try again."
        case "prompt_unconfirmed": return "Couldn't confirm the message was delivered. Check Cursor before sending it again."
        case "unsupported_capability", "unsupported_agent": return "This Herdcats Bridge can't send Cursor messages. Use Terminal."
        default: return "Couldn't send the message to Cursor. Use Terminal."
        }
    }
}

extension TimelineComposePolicy {
    static func shouldClearDraft(current: String, sent: String) -> Bool { current == sent }
}

/// A probe is read-only. Existing, unverifiable installations require an explicit replacement choice.
enum HostHelperProbe: Equatable, Sendable {
    case missing
    case present(version: String?, managed: Bool, compatible: Bool)

    init(output: String, agent: String? = nil) throws {
        let lines = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", omittingEmptySubsequences: false)
        guard let marker = lines.first else { throw HostHelperSetupError.invalidResponse }
        if marker == "HC_HELPER_MISSING", lines.count == 1 { self = .missing; return }
        if marker == "HC_HELPER_BLOCKED" { throw HostHelperSetupError.unsafeDestination }
        guard marker == "HC_HELPER_MANAGED" || marker == "HC_HELPER_EXTERNAL" else { throw HostHelperSetupError.invalidResponse }
        struct Report: Decodable {
            let name: String
            let version: String
            let `protocol`: Int
            let herdrProtocol: Int
            let agents: [String]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let bytes = Data(lines.dropFirst().joined(separator: "\n").utf8)
        let report = try? decoder.decode(Report.self, from: bytes)
        let version = report.flatMap { Self.versionNumbers($0.version) == nil ? nil : $0.version }
        let targetAgent = agent ?? "claude"
        let compatible = report.map {
            $0.name == "herdcats-bridge" && $0.protocol == 1 && $0.herdrProtocol == 22
                && $0.agents.contains(where: { TimelineAgentAvailability.canonical($0) == TimelineAgentAvailability.canonical(targetAgent) && TimelineAgentAvailability.canonical(targetAgent) != nil }) && Self.isAtLeastMinimum($0.version)
        } ?? false
        self = .present(version: version, managed: marker == "HC_HELPER_MANAGED", compatible: compatible)
    }
    static func versionNumbers(_ version: String) -> [Int]? {
        guard version.utf8.count <= 64 else { return nil }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == 3 ? numbers : nil
    }
    static func isAtLeastMinimum(_ version: String?) -> Bool {
        guard let version,
              let current = versionNumbers(version),
              let minimum = versionNumbers(HostHelperSetupPlan.minimumVersion)
        else { return false }
        return current == minimum || minimum.lexicographicallyPrecedes(current)
    }
    static func isOlderThanMinimum(_ version: String?) -> Bool {
        guard let version,
              let current = versionNumbers(version),
              let minimum = versionNumbers(HostHelperSetupPlan.minimumVersion)
        else { return false }
        return current.lexicographicallyPrecedes(minimum)
    }
    static func isAtLeastPinned(_ version: String?) -> Bool {
        guard let version,
              let current = versionNumbers(version),
              let pinned = versionNumbers(HostHelperSetupPlan.version)
        else { return false }
        return current == pinned || pinned.lexicographicallyPrecedes(current)
    }
    static func isOlderThanPinned(_ version: String?) -> Bool {
        guard let version,
              let current = versionNumbers(version),
              let pinned = versionNumbers(HostHelperSetupPlan.version)
        else { return false }
        return current.lexicographicallyPrecedes(pinned)
    }
}
enum HostHelperSetupDecision: Equatable, Sendable {
    case ready, missing
    case replacementRequired(HostHelperProbe)
    case install(replace: Bool)
    case unsupportedByPinnedInstaller(String)
}
enum HostHelperSetupReason: String, Equatable, Sendable {
    case missing = "helper_missing"
    case updateRequired = "helper_update_required"

    init(code: String?) {
        if code == "helper_update_required" {
            self = .updateRequired
        } else {
            self = .missing
        }
    }
}
enum HostHelperSetupStage: Equatable, Sendable {
    case idle, checking, installing, verifying, uncertain, installed
    case replacementRequired(HostHelperProbe)
    var isBusy: Bool { self == .checking || self == .installing || self == .verifying }
}
enum HostHelperSetupError: Error, LocalizedError, Equatable {
    case unsafeDestination, invalidResponse, failed(String), busy
    var errorDescription: String? {
        switch self {
        case .unsafeDestination: "The install location is a link or another nonregular file. Use manual setup to choose a safe location."
        case .invalidResponse: "Herdcats Bridge could not be verified. Check the installation or use manual setup."
        case .busy: "A Herdcats Bridge setup is already running on this connection. Check again when it finishes."
        case .failed(let code):
            switch code {
            case "curl_missing": "This host needs curl to download Herdcats Bridge. Use manual setup to install it."
            case "checksum_tool_missing": "This host needs shasum or sha256sum to verify the download."
            case "download_failed": "The host could not download the installer. Check its network access, or use manual setup."
            case "checksum_mismatch": "The installer did not match the app’s pinned checksum. Nothing was executed. Use manual setup or update Herdcats."
            default: "The host could not complete installation. Check its permissions and required tools, or use manual setup."
            }
        }
    }
}

/// Mirrors adapters implemented by the current bridge; agent detection alone
/// does not imply that native session history is available.
enum TimelineAgentAvailability {
    static func displayName(for agent: String) -> String {
        if let approvalAgent = ApprovalAgent(rawValue: agent) { return approvalAgent.displayName }
        if agent == "pi" { return "Pi" }
        switch canonical(agent) {
        case "antigravity_cli": return "Agy"
        case "cursor": return "Cursor"
        default: return agent
        }
    }
    static func canonical(_ agent: String?) -> String? {
        switch agent {
        case "agy", "antigravity_cli": return "antigravity_cli"
        case "claude", "codex", "pi", "cursor": return agent
        default: return nil
        }
    }
    static func supports(agent: String?) -> Bool { canonical(agent) != nil }
    static func matchesSession(agent: String, referenceAgent: String?, source: String?, identityAgent: String, referenceKind: String = "id") -> Bool {
        guard let canonical = canonical(identityAgent), Self.canonical(agent) == canonical,
              Self.canonical(referenceAgent) == canonical else { return false }
        // Agy and Cursor identify a chat by ID only; a path reference is never a chat.
        guard !["antigravity_cli", "cursor"].contains(canonical) || referenceKind == "id" else { return false }
        return source == "herdr:\(canonical)"
    }
}

/// Only references into the bridge's bounded, verified source snapshot.
enum TimelineContentReference {
    static func length(_ reference: String) -> Int? {
        guard reference.utf8.count <= 128 else { return nil }
        let parts = reference.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "source",
              parts[1].allSatisfy({ $0.isASCII && $0.isNumber }), parts[2].allSatisfy({ $0.isASCII && $0.isNumber }),
              let start = Int(parts[1]), let length = Int(parts[2]), start >= 0, length > 0,
              start <= 64 * 1024 * 1024, length <= 64 * 1024 * 1024 - start else { return nil }
        return length
    }
}

enum TimelineSourcePages {
    static func ranges(_ bytes: Data) -> [Range<Int>] {
        guard !bytes.isEmpty else { return [0..<0] }
        var result: [Range<Int>] = []; var start = 0
        while start < bytes.count {
            var end = min(start + 32768, bytes.count)
            while end < bytes.count && bytes[end] & 0xc0 == 0x80 { end -= 1 }
            result.append(start..<end); start = end
        }
        return result
    }
}

/// Adjacent tool calls form one activity; messages and images keep their order.
struct TimelineConversationItem: Identifiable, Equatable {
    var entries: [AgentTimelineEntry]
    var id: String { entries[0].id }
    var isActivity: Bool { entries[0].kind == "tool" }

    /// Fallback `record` entries stay hidden unless the caller opts in (Codex timelines).
    static func group(_ entries: [AgentTimelineEntry], showsRecords: Bool = false) -> [Self] {
        var items: [Self] = []
        for entry in entries where showsRecords || entry.kind != "record" {
            if entry.kind == "tool", items.last?.isActivity == true {
                items[items.count - 1].entries.append(entry)
            } else {
                items.append(Self(entries: [entry]))
            }
        }
        return items
    }
}

/// Who an item belongs to in the conversation layout.
enum TimelineTurnLayout {
    enum Role: Equatable {
        /// Your messages and images: a bubble on the trailing side.
        case user
        /// The agent's messages and images: open text under the agent's name.
        case agent
        /// A group of tool steps: a quiet summary row inside the agent's turn.
        case activity
        /// Interrupted turns and unsupported records: a centred caption.
        case notice
    }

    static func role(_ item: TimelineConversationItem) -> Role {
        item.isActivity ? .activity : role(entry: item.entries[0])
    }

    static func role(entry: AgentTimelineEntry) -> Role {
        if entry.kind == "tool" { return .activity }
        if entry.kind == "record" || entry.isTurnInterrupted { return .notice }
        return entry.role == "user" ? .user : .agent
    }
}

/// The name shown above each agent turn.
enum TimelineSpeaker {
    /// Uses the app's existing display names ("Claude", "Codex", "Agy", "Pi",
    /// "Cursor"), so a raw identity such as "antigravity_cli" never shows.
    static func name(agent: String?) -> String {
        guard let agent, TimelineAgentAvailability.supports(agent: agent) else { return "Agent" }
        return TimelineAgentAvailability.displayName(for: agent)
    }

    /// The agent string `AgentKindIcon` has artwork for. Agy's timeline
    /// identity is "antigravity_cli", but its icon is registered as "agy".
    static func iconKind(agent: String?) -> String {
        TimelineAgentAvailability.canonical(agent) == "antigravity_cli" ? "agy" : (agent ?? "")
    }
}

/// One child of the Timeline's lazy stack. Speaker names and the space
/// between turns are rows of their own, outside the message row. Only item
/// rows carry the scroll id and report their frame, so loading older
/// messages can add or remove a speaker row, or resize a gap, above the
/// message being read without moving that message's own content.
enum TimelineRow: Identifiable, Equatable {
    /// Space before the item with this id.
    case gap(beforeItemID: String, height: CGFloat)
    /// The agent's name above the first item of its turn.
    case speaker(firstItemID: String, agent: String)
    case item(TimelineConversationItem)

    /// Prefixed so a bridge id that happens to start with "gap:" can never
    /// collide with another row. The scroll id of an item is separate.
    var id: String {
        switch self {
        case .gap(let itemID, _): "gap:\(itemID)"
        case .speaker(let itemID, _): "speaker:\(itemID)"
        case .item(let item): "item:\(item.id)"
        }
    }
}

enum TimelineRows {
    /// Space where the speaker changes, for example from you to the agent.
    static let turnGap: CGFloat = 24
    /// Space between items of the same turn.
    static let itemGap: CGFloat = 12

    /// Builds the rows in one pass over the items.
    ///
    /// - A gap row sits between every two items: `turnGap` when the speaker
    ///   changes, `itemGap` otherwise. Tool steps never get a gap between
    ///   them, because adjacent tool entries are already one activity item.
    /// - A speaker row sits above the first agent message or tool group after
    ///   one of your messages, and above the first one in the loaded history.
    ///   Notices don't start or end a turn.
    static func build(items: [TimelineConversationItem], agent: String) -> [TimelineRow] {
        var rows: [TimelineRow] = []
        rows.reserveCapacity(items.count * 2 + 1)
        var previous: TimelineTurnLayout.Role?
        var needsSpeaker = true
        for item in items {
            let role = TimelineTurnLayout.role(item)
            if let previous {
                let height = side(previous) == side(role) ? itemGap : turnGap
                rows.append(.gap(beforeItemID: item.id, height: height))
            }
            switch role {
            case .user:
                needsSpeaker = true
            case .agent, .activity:
                if needsSpeaker {
                    rows.append(.speaker(firstItemID: item.id, agent: agent))
                    needsSpeaker = false
                }
            case .notice:
                break
            }
            rows.append(.item(item))
            previous = role
        }
        return rows
    }

    private enum Side { case you, agent, notice }

    private static func side(_ role: TimelineTurnLayout.Role) -> Side {
        switch role {
        case .user: .you
        case .agent, .activity: .agent
        case .notice: .notice
        }
    }
}

/// Picks the message to hold still while older messages load above it.
enum TimelineHistoryAnchor {
    /// The topmost item whose frame overlaps the visible band, preferring
    /// anything that isn't a notice. A notice can be the first loaded item
    /// with a speaker row below it; that row disappears when the older page
    /// arrives, so holding the notice still would let the message under it
    /// jump. Falls back to a notice when nothing else is visible.
    static func pick(frames: [String: CGRect], items: [TimelineConversationItem],
                     visibleTop: CGFloat, visibleBottom: CGFloat) -> (id: String, frame: CGRect)? {
        let notices = Set(items.filter { TimelineTurnLayout.role($0) == .notice }.map(\.id))
        let visible = frames.filter { $0.value.maxY > visibleTop && $0.value.minY < visibleBottom }
        let topmost: ([String: CGRect]) -> (key: String, value: CGRect)? = { candidates in
            candidates.min { $0.value.minY < $1.value.minY }
        }
        guard let chosen = topmost(visible.filter { !notices.contains($0.key) }) ?? topmost(visible) else { return nil }
        return (chosen.key, chosen.value)
    }
}

enum TimelineActivitySummary {
    static func isCommand(_ entry: AgentTimelineEntry) -> Bool {
        ["bash", "run_command", "exec_command", "shell_command", "shell"].contains(entry.toolName?.lowercased() ?? "")
    }
    static func isRunning(_ entry: AgentTimelineEntry) -> Bool {
        entry.status != "completed" && entry.status != "failed"
    }
    static func title(_ entries: [AgentTimelineEntry]) -> String {
        let commands = entries.filter(isCommand).count
        let notifications = entries.filter { $0.toolName == "Background task" }.count
        let tools = entries.count - commands - notifications
        let running = entries.contains(where: isRunning)
        var parts: [String] = []
        if commands > 0 {
            parts.append("\(running ? "Running" : "Ran") \(commands == 1 ? "a command" : "\(commands) commands")")
        }
        if tools > 0 {
            parts.append("\(running ? "Using" : "Used") \(tools == 1 ? "a tool" : "\(tools) tools")")
        }
        if notifications > 0 {
            parts.append(notifications == 1 ? "Background task update" : "\(notifications) background task updates")
        }
        return parts.joined(separator: " · ")
    }
    static func purpose(_ entry: AgentTimelineEntry) -> String {
        if entry.toolName == "Background task" { return String(entry.text.prefix(240)) }
        let input = entry.details.flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        if let description = input["description"] as? String,
           let firstLine = description.split(whereSeparator: \.isNewline).first,
           !firstLine.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(firstLine.prefix(180))
        }
        // Agy 1.4.7 encodes toolSummary as a JSON string inside args.
        // Decode only this verified field; leave the original details untouched.
        if entry.toolName?.lowercased() == "run_command",
           let encoded = input["toolSummary"] as? String,
           let data = encoded.data(using: .utf8),
           let summary = try? JSONDecoder().decode(String.self, from: data),
           let line = summary.split(whereSeparator: \.isNewline).first,
           !line.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(line.prefix(180))
        }
        let path = (input["file_path"] ?? input["path"] ?? input["notebook_path"]) as? String
        let file = path.map { URL(fileURLWithPath: $0).lastPathComponent }
        switch entry.toolName?.lowercased() {
        case "read": return file.map { "Read \($0)" } ?? "Read a file"
        case "edit", "multiedit", "notebookedit": return file.map { "Edit \($0)" } ?? "Edit a file"
        case "write": return file.map { "Write \($0)" } ?? "Write a file"
        case "grep", "glob": return "Search project files"
        case "websearch": return "Search the web"
        case "webfetch": return "Read a web page"
        case "bash", "run_command", "exec_command", "shell_command", "shell": return "Run a shell command"
        case "ask_question", "askquestion": return "Ask a question"
        default: return entry.toolName.map { "Use \($0)" } ?? "Use a tool"
        }
    }
    static func status(_ entry: AgentTimelineEntry) -> String {
        switch entry.status {
        case "completed": "Completed"
        case "failed": "Failed or interrupted"
        default: "Running"
        }
    }
}


/// Metadata-only diagnostics, available in Xcode and the device's unified log.
enum TimelineHistoryDiagnostics {
    private static let logger = Logger(subsystem: "com.enchantinglabs.herdrcat", category: "TimelineHistory")

    static func record(_ message: String, failure: Bool = false) {
        if failure { logger.error("[TimelineHistory] \(message, privacy: .public)") }
        else { logger.info("[TimelineHistory] \(message, privacy: .public)") }
    }

    static func reason(_ error: any Error) -> String {
        if error is CancellationError { return "cancelled" }
        guard let error = error as? AgentBridgeError else { return "type=\(String(reflecting: type(of: error)))" }
        switch error {
        case .closed: return "closed"
        case .timeout: return "timeout"
        case .identityMismatch: return "identity_mismatch"
        case .invalidFrame: return "invalid_frame"
        case .frameTooLarge: return "frame_too_large"
        case .incompleteFrame: return "incomplete_frame"
        case .protocolMismatch: return "protocol_mismatch"
        case .sequenceGap: return "sequence_gap"
        case .unavailable(let code), .questionFailure(let code, _):
            let safe = code.prefix(64).filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
            return "remote_\(safe)"
        }
    }
}

struct AgentEffortOption: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let label: String
}

/// Status replies carry an object; model.updated carries just the model id.
struct AgentModelOption: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    var efforts: [AgentEffortOption] = []
    var current: Bool? = nil

    init(id: String, label: String, efforts: [AgentEffortOption] = [], current: Bool? = nil) {
        self.id = id
        self.label = label
        self.efforts = efforts
        self.current = current
    }
    init(from decoder: Decoder) throws {
        if let id = try? decoder.singleValueContainer().decode(String.self) {
            self.init(id: id, label: Self.label(for: id))
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(id: try c.decode(String.self, forKey: .id),
                label: try c.decode(String.self, forKey: .label),
                efforts: try c.decodeIfPresent([AgentEffortOption].self, forKey: .efforts) ?? [],
                current: try c.decodeIfPresent(Bool.self, forKey: .current))
        }
    }
    static func label(for id: String) -> String {
        let parts = id.replacingOccurrences(of: "claude-", with: "").split(separator: "-")
        if let tier = parts.first, ["opus", "sonnet", "haiku", "fable"].contains(String(tier)) {
            let version = parts.dropFirst().prefix(while: { part in
                part.count <= 2 && part.allSatisfy { $0.isASCII && $0.isNumber }
            }).joined(separator: ".")
            return tier.capitalized + (version.isEmpty ? "" : " " + version)
        }
        return id
    }
}

struct AgentModelPair: Codable, Equatable, Sendable {
    var model: AgentModelOption?
    var effort: String?
}

/// Nulls must be encoded: the bridge requires both keys even before the first turn.
struct AgentModelExpectation: Encodable, Sendable {
    let model: String?
    let effort: String?
    var identity: AgentTimelineIdentity? = nil
    var generation: UInt64? = nil
    enum CodingKeys: String, CodingKey { case model, effort, identity, generation }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(effort, forKey: .effort)
        try c.encodeIfPresent(identity, forKey: .identity)
        try c.encodeIfPresent(generation, forKey: .generation)
    }
}

/// Pi forwards the exact extension dialog; boolean confirmation never implies
/// a permission scope. Custom dialogs remain in Terminal.
enum AgentPiDialogValue: Encodable, Equatable, Sendable {
    case boolean(Bool), text(String)
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .boolean(let flag): try value.encode(flag)
        case .text(let text): try value.encode(text)
        }
    }
}
struct AgentPiDialog: Equatable, Sendable {
    let identity: AgentTimelineIdentity
    let generation: UInt64
    let requestId: String
    let kind: String
    let title: String
    let message: String?
    let options: [String]
    let value: String?
    var isTerminalOnly: Bool { !["confirm", "select", "input"].contains(kind) }
    func accepts(_ answer: AgentPiDialogValue) -> Bool {
        switch (kind, answer) {
        case ("confirm", .boolean): return true
        case ("select", .text(let text)): return options.contains(text)
        case ("input", .text(let text)): return text.utf8.count <= 65536
        default: return false
        }
    }
    static func decode(_ payload: AgentBridgePayload) throws -> Self {
        guard let identity = payload.identity, identity.agent == "pi", let generation = payload.generation,
              let requestId = payload.requestId, !requestId.isEmpty, requestId.utf8.count <= 264,
              let kind = payload.kind, kind.utf8.count <= 64,
              let title = payload.title, title.utf8.count <= 8192,
              (payload.message?.utf8.count ?? 0) <= 8192,
              (payload.value?.utf8.count ?? 0) <= 65536 else { throw AgentBridgeError.invalidFrame }
        let options = payload.dialogOptions ?? []
        guard options.count <= 100, options.allSatisfy({ $0.utf8.count <= 8192 }),
              kind != "select" || (!options.isEmpty && Set(options).count == options.count) else { throw AgentBridgeError.invalidFrame }
        return Self(identity: identity, generation: generation, requestId: requestId, kind: kind,
            title: title, message: payload.message, options: options, value: payload.value)
    }
}
