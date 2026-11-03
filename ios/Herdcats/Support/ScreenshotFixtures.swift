#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftUI

/// Simulator fixtures for native screenshots and saved-connection UI tests.
enum ScreenshotFixtures {
    private struct SavedMachineFixture: Decodable {
        let id: UUID
        let host: String
        let port: Int
        let username: String
        let secret: String
        let authMode: String
        let name: String
    }

    static func seedMachinesIfRequested() throws {
        guard ProcessInfo.processInfo.arguments.contains("-hc.seed-machines"),
              let json = ProcessInfo.processInfo.environment["HC_SAVED_MACHINES"] else { return }
        let fixtures = try JSONDecoder().decode([SavedMachineFixture].self, from: Data(json.utf8))
        var entries: [RecentConnection] = []
        for fixture in fixtures {
            let entry = RecentConnection(id: fixture.id, host: fixture.host, port: fixture.port,
                username: fixture.username, authMode: fixture.authMode, remember: true, name: fixture.name)
            try KeychainStore.save(fixture.secret, account: entry.secretAccount)
            entries.append(entry)
        }
        UserDefaults.standard.set(try JSONEncoder().encode(entries), forKey: RecentConnectionStore.storageKey)
    }

    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-hc.screenshots") }
    static var screen: String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-hc.screen"), index + 1 < args.count else { return "spaces" }
        return args[index + 1]
    }

    static let projects = ["Herdcats", "Checkout redesign", "API performance"]
    static let providers = ["claude", "codex", "cursor"]
    static let statuses = ["blocked", "working", "done"]
    static let titles = ["Review the onboarding flow", "Build the checkout screens", "Optimize database queries"]
    static var workspaces: [[String: Any]] {
        projects.enumerated().map { index, label in
            ["workspace_id": "w\(index)", "label": label, "number": index + 1,
             "tab_count": 1, "pane_count": 1, "active_tab_id": "t\(index)",
             "agent_status": statuses[index], "focused": index == 0,
             "worktree": ["checkout_path": "/Users/demo/Projects/\(label.lowercased().replacingOccurrences(of: " ", with: "-"))",
                          "repo_name": label.lowercased().replacingOccurrences(of: " ", with: "-"),
                          "repo_root": "/Users/demo/Projects/\(label.lowercased().replacingOccurrences(of: " ", with: "-"))",
                          "is_linked_worktree": false]]
        }
    }
    static var paneAgent: String {
        if screen == "timeline-question-codex-plan" || screen == "timeline-question-codex-async" { return "codex" }
        if screen == "timeline-question-claude" { return "claude" }
        if screen == "timeline-approval-codex" { return "codex" }
        if screen == "timeline-approval-claude" { return "claude" }
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-hc.agent"), index + 1 < args.count else { return "claude" }
        return args[index + 1]
    }
    static var panes: [[String: Any]] {
        projects.indices.map { index in
            ["pane_id": "p\(index)", "tab_id": "t\(index)", "workspace_id": "w\(index)",
             "agent": index == 0 ? paneAgent : providers[index], "agent_status": statuses[index],
             "cwd": "/Users/demo/Projects/\(projects[index].lowercased().replacingOccurrences(of: " ", with: "-"))",
             "terminal_title_stripped": titles[index], "terminal_title": titles[index],
             "focused": index == 0, "revision": 1, "state_change_seq": 10 - index]
        }
    }
    static func json(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    static func response(_ args: String) throws -> String {
        if args == "--version" { return "herdr 0.8.0" }
        if args.hasPrefix("pane read") { return terminal }
        let result: [String: Any]
        if args == "workspace list" { result = ["workspaces": workspaces] }
        else if args == "agent list" { result = ["agents": panes] }
        else if args.hasPrefix("pane list") {
            result = ["panes": panes.filter {
                args.contains(HerdrConnection.shellSafeArgument($0["workspace_id"] as! String))
            }]
        } else if args.hasPrefix("tab list") {
            result = ["tabs": projects.indices.filter {
                args.contains(HerdrConnection.shellSafeArgument("w\($0)"))
            }.map { index in
                ["tab_id": "t\(index)", "workspace_id": "w\(index)", "label": "Agent", "number": 1,
                 "pane_count": 1, "agent_status": statuses[index], "focused": true] as [String: Any]
            }]
        } else { throw HerdrError.invalidConfiguration("Screenshot fixtures are read-only: \(args)") }
        return try json(["result": result])
    }
    static var quota: QuotaReport {
        let formatter = ISO8601DateFormatter()
        var entries: [QuotaProvider] = []
        for (index, provider) in ["claude", "codex", "cursor", "agy", "zai"].enumerated() {
            let session = QuotaWindow(id: "five_hour", resetsAt: formatter.string(from: Date().addingTimeInterval(7200)), percentRemaining: Double(82 - index * 9))
            let weekly = QuotaWindow(id: "weekly", resetsAt: formatter.string(from: Date().addingTimeInterval(172800)), percentRemaining: Double(64 - index * 7))
            let state = QuotaProviderState(status: "ok", stale: false, error: nil)
            entries.append(QuotaProvider(provider: provider, plan: "Pro", label: nil, windows: [session, weekly], state: state))
        }
        return QuotaReport(generatedAt: nil, schemaVersion: 1, providers: entries, cliVersion: nil)
    }

    static var terminal: String {
        if ProcessInfo.processInfo.arguments.contains("-hc.empty-terminal-output") { return "" }
        if ProcessInfo.processInfo.arguments.contains("-hc.long-terminal-selection") {
            return (0..<400).map { index in
                let marker = String(format: "%04d", index)
                return "row\(marker) target\(marker) " + String(repeating: "content ", count: index % 12)
            }.joined(separator: "\n")
        }
        return terminalPreview
    }

    private static let terminalPreview = """
    \u{001B}[38;5;208m╭─ Claude Code ───────────────────────────────────────╮\u{001B}[0m
      Herdcats · onboarding polish · Claude
    \u{001B}[38;5;208m╰────────────────────────────────────────────────────╯\u{001B}[0m

    \u{001B}[36m❯ Review the onboarding flow and improve the connection guidance.\u{001B}[0m

    ● Read the onboarding screens and checked the SSH connection setup from start to finish.

    ● Updated the connection guidance
      \u{001B}[32m✓ Clearer hints for the host address and SSH username
      ✓ Step-by-step instructions for connecting over Tailscale
      ✓ Host key verification explained before connecting\u{001B}[0m

    ● Ran the focused onboarding and connection tests
      \u{001B}[32m24 tests passed · 0 failures · ready for review\u{001B}[0m

    \u{001B}[1mReady for your review\u{001B}[0m
    The new copy is in place and the connection tests pass. Would you like me to commit these changes?

    \u{001B}[33m❯ Waiting for your input…\u{001B}[0m
    """
}

struct ScreenshotRootView: View {
    @State private var model: AppModel = {
        let app = AppModel(autoConnectOnLaunch: false)
        app.phase = .connected(host: "studio-mac", username: "demo")
        app.hasActiveSession = true
        if ScreenshotFixtures.screen == "timeline-connecting" { app.phase = .connecting }
        if ScreenshotFixtures.screen == "timeline-offline" || ScreenshotFixtures.screen.hasPrefix("loading-audit-offline-") {
            app.phase = .offline(host: "studio-mac", username: "demo")
            app.connectionBanner = .offline(message: "Offline · Connection lost", canRetry: true)
        }
        app.connectionIdentity = ConnectionIdentity(host: "studio-mac", port: 22, username: "demo")
        // Keep each capture independent of previous timeline/terminal navigation.
        if ProcessInfo.processInfo.arguments.contains("-hc.capture-surface"), let identity = app.connectionIdentity {
            let terminal = ["pane", "agent-pane", "keys"].contains(ScreenshotFixtures.screen)
            UserDefaults.standard.set(terminal, forKey: TimelineSetupPreference.key(scope: identity))
        }
        if ProcessInfo.processInfo.arguments.contains("-hc.timeline-intro-reset"), let identity = app.connectionIdentity {
            UserDefaults.standard.removeObject(forKey: TimelineSetupPreference.key(scope: identity))
        }
        return app
    }()
    var body: some View {
        Group {
            if ScreenshotFixtures.screen.hasPrefix("loading-audit-") {
                LoadingAuditFixtureView()
            } else if ScreenshotFixtures.screen == "onboarding" {
                ConnectView(replay: true)
                    .background(Theme.backgroundGradient)
            } else if ScreenshotFixtures.screen == "pane" || ScreenshotFixtures.screen == "agent-pane" || ["keys", "compose", "voice", "turn-interrupted", "optional-upgrade-menu"].contains(ScreenshotFixtures.screen) || ScreenshotFixtures.screen.hasPrefix("timeline") {
                NavigationStack {
                    if let pane = try? JSONDecoder().decode(PaneEntry.self, from: Data(ScreenshotFixtures.json(ScreenshotFixtures.panes[0]).utf8)) {
                        PaneDetailView(pane: pane)
                            .connectionStatusBanner(appModel: model)
                            .toolbar {
                                if ScreenshotFixtures.screen == "timeline-offline-transition" {
                                    Button("Go offline") {
                                        model.phase = .offline(host: "studio-mac", username: "demo")
                                        model.connectionBanner = .offline(message: "Offline · Connection lost", canRetry: true)
                                    }
                                    .accessibilityIdentifier("fixture-go-offline")
                                }
                            }
                    }
                }
            } else if ScreenshotFixtures.screen == "connect" {
                ConnectionSettingsView(connection: RecentConnection(
                    host: "studio-mac.tailnet.ts.net", port: 22, username: "demo",
                    authMode: "password", remember: false
                ))
            } else {
                MainTabView()
            }
        }
        .environment(model)
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-hc.light") ? .light : .dark)
        .tint(Theme.accent)
        .foregroundStyle(Theme.text)
        .font(.jost(.body))
        .transformEnvironment(\.dynamicTypeSize) { value in
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-hc.accessibility-type-max") {
                value = .accessibility5
            } else if args.contains("-hc.accessibility-type") {
                value = .accessibility3
            }
        }
    }
}
/// Static, isolated presentation fixtures. These never dial a host or alter saved machines.
private struct LoadingAuditFixtureView: View {
    @Environment(AppModel.self) private var appModel
    @State private var quota: SpacesModel
    @State private var layout = PaneLayout()
    @State private var retryCount = 0
    private var screen: String { ScreenshotFixtures.screen }

    init() {
        let model = SpacesModel()
        let screen = ScreenshotFixtures.screen
        // Inject only the fetch boundary. QuotaScreen owns its actual refresh task,
        // GeometryReader, scroll view, navigation, and recovery UI.
        model.quotaReportFetch = {
            if screen.hasSuffix("error") { throw HerdrError.unexpectedResponse("Quota fixture failed") }
            if screen.hasSuffix("missing") { throw HerdrError.quotaAxiNotFound }
            if screen.hasSuffix("empty") { throw CancellationError() }
            // A controlled pending request, canceled with the screen; no host access or timer.
            let pending = AsyncStream<QuotaReport> { _ in }
            for await report in pending { return report }
            throw CancellationError()
        }
        if screen.hasSuffix("retained") {
            model.applyUsageReport(ScreenshotFixtures.quota)
            model.usageLastUpdated = .distantPast
        }
        _quota = State(initialValue: model)
    }

    var body: some View {
        if screen.hasPrefix("loading-audit-offline-") {
            if screen.hasSuffix("action") {
                NavigationStack {
                    OfflineHerdView()
                        .overlay(alignment: .bottom) { Text("Retries: \(retryCount)").accessibilityIdentifier("fixture-retry-count") }
                        .connectionStatusBanner(banner: .offline(message: "Offline · Connection lost", canRetry: true)) {
                            retryCount += 1
                        }
                }
            } else {
                TabView {
                    Group {
                        if screen.hasSuffix("agents") { AgentsScreen(model: quota, layout: $layout) }
                        else if screen.hasSuffix("spaces") { SpacesScreen(model: quota, layout: $layout) }
                        else if screen.hasSuffix("quota") { QuotaScreen(model: quota) }
                        else if screen.hasSuffix("terminal") {
                            NavigationStack {
                                PaneOutputScrollView(output: "", selectableText: AttributedString(), outputRevision: 0,
                                    outputPointSize: 14, paneScrollBehavior: .holdPosition, keyboardFocused: false,
                                    isOffline: true, isLoading: false, reservesMarkAsReadSpace: false,
                                    topOverlayInset: 60, bottomOverlayInset: 100, paneId: "fixture",
                                    shouldPinToBottom: .constant(false), onUserScroll: {}, onTapOutput: {}, onSelectionChange: { _ in })
                                    .navigationTitle("Terminal")
                                    .overlay(alignment: .bottom) { Text("Retries: \(retryCount)").accessibilityIdentifier("fixture-retry-count") }
                                    .connectionStatusBanner(banner: appModel.connectionBanner) { retryCount += 1 }
                            }
                        }
                        else {
                            NavigationStack {
                                Text("Verified retained content")
                                    .padding(16)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .overlay(alignment: .bottom) { Text("Retries: \(retryCount)").accessibilityIdentifier("fixture-retry-count") }
                                    .connectionStatusBanner(banner: retryCount == 0 ? appModel.connectionBanner : .connecting(message: "Reconnecting…")) { retryCount += 1 }
                            }
                        }
                    }
                    .tabItem { Label("Offline", systemImage: "wifi.slash") }
                }
                .environment(quota)
            }
        } else if screen.contains("quota") {
            TabView {
                QuotaScreen(model: quota)
                    .tabItem { Label("Quota", systemImage: "gauge.with.dots.needle.67percent") }
                Text("Fixture").tabItem { Label("Spaces", systemImage: "square.grid.3x3") }
            }
        } else {
            NavigationStack {
                Group {
                    if screen.contains("worktree") {
                        if let workspace = try? JSONDecoder().decode(Workspace.self, from: Data(ScreenshotFixtures.json(ScreenshotFixtures.workspaces[0]).utf8)) {
                            OpenWorktreeDrawer(space: Space(workspace: workspace, agents: []), connection: appModel.connection,
                                onOpen: { _, _ in }, onCancel: {})
                        }
                    } else {
                        let text = screen.hasSuffix("retained") ? "Verified terminal output" : ""
                        PaneOutputScrollView(output: text, selectableText: PaneOutputPresentation.selectableText(from: ANSIText.lines(from: text)), outputRevision: 0,
                            outputPointSize: 14, paneScrollBehavior: .holdPosition, keyboardFocused: false,
                            isOffline: false, isLoading: true, reservesMarkAsReadSpace: false,
                            topOverlayInset: 60, bottomOverlayInset: 100, paneId: "fixture",
                            shouldPinToBottom: .constant(false), onUserScroll: {}, onTapOutput: {}, onSelectionChange: { _ in })
                    }
                }
                .background(Theme.background)
                .navigationTitle(screen.contains("worktree") ? "Open worktree" : "Terminal output")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
#endif
