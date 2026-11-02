import Foundation

/// Adapts Core's terminal/document models to existing UI presentation records.
/// None of these records is decoded as a legacy Herdr wire envelope.
struct CoreHierarchy {
    static let otherWorkspaceID = "core:other"
    var workspaces: [Workspace] = []
    var agents: [AgentEntry] = []
    var panes: [PaneEntry] = []
    var tabs: [TabEntry] = []
}

extension CoreSnapshot {
    func presentation(layout: CoreJSON?, remoteLayouts: [String: CoreJSON] = [:]) -> CoreHierarchy {
        var builder = CoreHierarchyBuilder(snapshot: self)
        if let layout { builder.addLayout(layout, machine: nil) }
        for machine in remoteLayouts.keys.sorted() {
            if let layout = remoteLayouts[machine] { builder.addLayout(layout, machine: machine) }
        }
        builder.addOtherTerminals()
        return builder.result
    }
}

private struct CoreHierarchyBuilder {
    let snapshot: CoreSnapshot
    private let live: [String: CoreJSON]
    /// Live terminals by creation time, ties broken by natural address order.
    private let orderedAddresses: [String]
    var result = CoreHierarchy()
    private var assigned: Set<String> = []
    private var spaceIDs: Set<String> = []
    private var tabIDs: Set<String> = []

    init(snapshot: CoreSnapshot) {
        self.snapshot = snapshot
        let live = snapshot.terminals.filter { $0.value["state"].stringValue == "live" }
        self.live = live
        orderedAddresses = live.keys.sorted {
            let left = live[$0]?["created_ms"].uint64Value ?? 0
            let right = live[$1]?["created_ms"].uint64Value ?? 0
            return left == right ? $0.localizedStandardCompare($1) == .orderedAscending : left < right
        }
    }

    mutating func addLayout(_ document: CoreJSON, machine: String?) {
        guard let spaces = document["spaces"].arrayValue else { return }
        for space in spaces {
            guard let rawSpaceID = nonempty(space["id"]),
                  let tabs = space["tabs"].arrayValue else { continue }
            let spaceID = identity("space", machine: machine, raw: rawSpaceID)
            guard spaceIDs.insert(spaceID).inserted else { continue }
            let firstPane = result.panes.count
            let firstTab = result.tabs.count
            for (index, tab) in tabs.enumerated() {
                guard let rawTabID = nonempty(tab["id"]) else { continue }
                let tabID = identity("tab", machine: machine, raw: rawSpaceID + "/" + rawTabID)
                guard tabIDs.insert(tabID).inserted else { continue }
                var addresses = terminalAddresses(in: tab["root"], machine: machine)
                // Labels make newly spawned desktop terminals visible before
                // the desktop publishes the matching layout block.
                let labeled = orderedAddresses.filter {
                    let terminal = live[$0]!
                    return machineFor($0) == machine
                        && terminal["labels"]["herdr.space"].stringValue == rawSpaceID
                        && terminal["labels"]["herdr.tab"].stringValue == rawTabID
                }
                addresses.append(contentsOf: labeled)
                let before = result.panes.count
                for address in addresses {
                    addTerminal(address, workspaceID: spaceID, tabID: tabID)
                }
                let panes = Array(result.panes[before...])
                result.tabs.append(TabEntry(
                    tabId: tabID, workspaceId: spaceID,
                    label: nonempty(tab["name"]) ?? String(index + 1), number: index + 1,
                    paneCount: panes.count, agentStatus: aggregate(panes), focused: false
                ))
            }
            let panes = Array(result.panes[firstPane...])
            let mappedTabs = Array(result.tabs[firstTab...])
            let localName = nonempty(space["name"])
                ?? nonempty(space["folder"]).map { ($0 as NSString).lastPathComponent }
                ?? rawSpaceID
            let label = machine.map { "\($0) · \(localName)" } ?? localName
            result.workspaces.append(Workspace(
                workspaceId: spaceID, label: label, number: result.workspaces.count + 1,
                tabCount: mappedTabs.count, paneCount: panes.count,
                activeTabId: mappedTabs.first?.tabId ?? "", agentStatus: aggregate(panes),
                focused: false, worktree: nil
            ))
        }
    }

    mutating func addOtherTerminals() {
        let addresses = orderedAddresses.filter { !assigned.contains($0) }
        guard !addresses.isEmpty else { return }
        let workspaceID = CoreHierarchy.otherWorkspaceID
        let tabID = "core:other:terminals"
        let before = result.panes.count
        for address in addresses { addTerminal(address, workspaceID: workspaceID, tabID: tabID) }
        let panes = Array(result.panes[before...])
        let status = aggregate(panes)
        result.tabs.append(TabEntry(
            tabId: tabID, workspaceId: workspaceID, label: "Terminals", number: 1,
            paneCount: panes.count, agentStatus: status, focused: false
        ))
        result.workspaces.append(Workspace(
            workspaceId: workspaceID, label: "Other terminals", number: result.workspaces.count + 1,
            tabCount: 1, paneCount: panes.count, activeTabId: tabID, agentStatus: status,
            focused: false, worktree: nil
        ))
    }

    private mutating func addTerminal(_ address: String, workspaceID: String, tabID: String) {
        guard let terminal = live[address], assigned.insert(address).inserted else { return }
        let status = nonempty(terminal["status"]["state"]) ?? "unknown"
        let agent = agentName(terminal)
        let cwd = nonempty(terminal["foreground"]["cwd"]) ?? nonempty(terminal["cwd"])
        let title = nonempty(terminal["title"]) ?? nonempty(terminal["name"]) ?? address
        result.panes.append(PaneEntry(
            paneId: address, tabId: tabID, workspaceId: workspaceID,
            label: nil, agent: agent, agentStatus: status, cwd: cwd,
            terminalTitle: title, terminalTitleStripped: title,
            focused: false, revision: snapshot.revisions[address]
        ))
        if let agent {
            result.agents.append(AgentEntry(
                agent: agent, agentStatus: status,
                stateChangeSeq: snapshot.statusSequences[address], cwd: cwd,
                paneId: address, tabId: tabID, workspaceId: workspaceID,
                terminalTitle: title, terminalTitleStripped: title,
                focused: false, revision: snapshot.revisions[address]
            ))
        }
    }

    private func terminalAddresses(in node: CoreJSON, machine: String?, depth: Int = 0) -> [String] {
        guard depth < 128 else { return [] }
        if let object = node.objectValue {
            if let terminal = nonempty(node["content"]["terminal"]) {
                return [qualify(terminal, machine: machine)]
            }
            // Desktop documents may add stacks/floating layouts. Only inspect
            // layout-root descendants; unknown nonterminal panels stay opaque.
            return object.keys.sorted().flatMap {
                terminalAddresses(in: object[$0]!, machine: machine, depth: depth + 1)
            }
        }
        return node.arrayValue?.flatMap {
            terminalAddresses(in: $0, machine: machine, depth: depth + 1)
        } ?? []
    }

    private func agentName(_ terminal: CoreJSON) -> String? {
        guard let app = nonempty(terminal["status"]["app"]) else { return nil }
        switch app.lowercased() {
        case "claude-code", "claude": return "claude"
        case "codex", "codex-cli": return "codex"
        case "cursor", "cursor-agent": return "cursor"
        case "gemini", "gemini-cli": return "gemini"
        case "pi", "pi-coding-agent": return "pi"
        case "agy", "antigravity": return "agy"
        default: return app
        }
    }

    private func aggregate(_ panes: [PaneEntry]) -> String {
        panes.map(\.status).max { $0.attentionPriority < $1.attentionPriority }?.rawValue ?? "unknown"
    }

    private func nonempty(_ value: CoreJSON) -> String? {
        guard let text = value.stringValue, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private func qualify(_ address: String, machine: String?) -> String {
        // A document is local to its core. Even a reference to one of that
        // core's added machines needs the enclosing machine prefix here.
        guard let machine else { return address }
        return "\(machine)/\(address)"
    }

    private func machineFor(_ address: String) -> String? {
        guard let slash = address.firstIndex(of: "/") else { return nil }
        return String(address[..<slash])
    }

    private func identity(_ kind: String, machine: String?, raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value }
        let scope = machine.map { "remote:\(encode($0))" } ?? "local"
        return "core:\(kind):\(scope):\(encode(raw))"
    }
}
