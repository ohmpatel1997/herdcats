import Observation
import SwiftUI

@main
struct HerdcatsApp: App {
    @State private var active = ActiveMachine()
    @AppStorage(AppearancePreference.storageKey)
    private var appearanceRaw = AppearancePreference.default.rawValue

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .default
    }

    init() {
#if DEBUG && targetEnvironment(simulator)
        do {
            try ScreenshotFixtures.seedMachinesIfRequested()
        } catch {
            assertionFailure("Could not seed saved machine fixtures")
        }
#endif
        PlainTextInput.install()
        AppTypeface.installUIKitAppearance()
    }

#if DEBUG
    private var screenshotModeEnabled: Bool {
#if targetEnvironment(simulator)
        ScreenshotFixtures.enabled
#else
        false
#endif
    }
    @ViewBuilder private var screenshotRoot: some View {
#if targetEnvironment(simulator)
        ScreenshotRootView()
#endif
    }
#endif

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if screenshotModeEnabled {
                screenshotRoot
            } else if ProcessInfo.processInfo.arguments.contains("-quotaNotSetupPreview") {
                QuotaNotSetupPreviewView()
                    .preferredColorScheme(appearance.colorScheme)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.text)
                    .font(.jost(.body))
            } else if ProcessInfo.processInfo.arguments.contains("-quotaRetryUITest")
                || ProcessInfo.processInfo.arguments.contains("-quotaRetryErrorUITest") {
                QuotaRetryUITestView()
            } else {
                AppRootView()
                    .environment(active.model)
                    .environment(active)
                    .preferredColorScheme(appearance.colorScheme)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.text)
                    .font(.jost(.body))
            }
#else
            AppRootView()
                .environment(active.model)
                .environment(active)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
                .foregroundStyle(Theme.text)
                .font(.jost(.body))
#endif
        }
    }
}

#if DEBUG
private struct QuotaNotSetupPreviewView: View {
    @State private var model = SpacesModel()
    @State private var appModel = AppModel()
    @State private var selectedTab = ConnectedTabsView.MainTab.quota
    @State private var layout = PaneLayout()

    var body: some View {
        TabView(selection: $selectedTab) {
            SpacesScreen(model: model, layout: $layout)
                .tabItem {
                    Label("Spaces", systemImage: "square.grid.3x3")
                }
                .tag(ConnectedTabsView.MainTab.spaces)

            AgentsScreen(model: model, layout: $layout)
                .tabItem {
                    Label("Agents", systemImage: "person.2")
                }
                .tag(ConnectedTabsView.MainTab.agents)

            QuotaScreen(model: model)
                .tabItem {
                    Label("Quota", systemImage: "gauge.with.dots.needle.67percent")
                }
                .tag(ConnectedTabsView.MainTab.quota)

            SettingsScreen(model: model)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(ConnectedTabsView.MainTab.settings)
        }
        .environment(appModel)
        .task {
            model.quotaReportFetch = {
                throw HerdrError.quotaAxiNotFound
            }
            await model.refreshUsage(appModel.connection, force: true)
        }
    }
}

private struct QuotaRetryUITestView: View {
    @State private var model = SpacesModel()
    @State private var requestedProvider: String?

    var body: some View {
        VStack {
            Text(requestedProvider.map { "Requested \($0)" } ?? "No retry requested")
                .accessibilityIdentifier("quota-retry-request")
            QuotaCardsView(model: model)
        }
        .environment(AppModel())
        .task {
            let errorCase = ProcessInfo.processInfo.arguments.contains("-quotaRetryErrorUITest")
            let initialJSON = errorCase ? """
                {"providers":[
                  {"provider":"claude","windows":[],
                   "state":{"status":"error","error":"keychain_access_denied"}},
                  {"provider":"codex",
                   "windows":[{"id":"weekly","kind":"weekly","percentRemaining":42}],
                   "state":{"status":"fresh"}}
                ]}
                """ : #"{"providers":[]}"#
            guard let report = try? QuotaReport.decode(initialJSON) else { return }
            model.applyUsageReport(report)
            model.quotaRetryFetch = { provider in
                requestedProvider = provider
                return try QuotaReport.decode("""
                {"providers":[{"provider":"claude","windows":[
                  {"id":"seven_day","kind":"weekly","percentRemaining":9}
                ],"state":{"status":"fresh"}}]}
                """)
            }
        }
    }
}
#endif

// MARK: - Root

struct AppRootView: View {
    @Environment(ActiveMachine.self) private var active
    private var appModel: AppModel { active.model }
    @State private var hasHandedOff = false

    private var showsLaunchCat: Bool {
        LaunchCatOverlay.shouldShow(
            hasActiveSession: appModel.hasActiveSession,
            phase: appModel.phase,
            hasHandedOff: hasHandedOff
        )
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            if appModel.hasActiveSession {
                MainTabView()
                    .hostKeyApprovalSheet {
                        await appModel.reconnect()
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                ConnectView()
                    .transition(.opacity)
            }

            if showsLaunchCat {
                LaunchHerdLoadingView(message: LaunchCatOverlay.message(phase: appModel.phase))
                    .background(Theme.backgroundGradient.ignoresSafeArea())
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showsLaunchCat)
        .animation(.easeInOut(duration: 0.35), value: appModel.hasActiveSession)
        .onChange(of: appModel.phase) { _, phase in
            switch phase {
            case .connected, .offline:
                hasHandedOff = true
            case .connecting, .disconnected:
                break
            }
        }
        .task {
            if let config = AutoConnect.configIfRequested()
                ?? LaunchPreference.autoConnectConfig() {
                await appModel.connect(config: config)
            }
        }
    }
}

// MARK: - Connection banner

enum ConnectionBanner: Equatable, Sendable {
    case offline(message: String, canRetry: Bool)
    case connecting(message: String)
    case backOnline(message: String)

    var message: String {
        switch self {
        case let .offline(msg, _): msg
        case let .connecting(msg): msg
        case let .backOnline(msg): msg
        }
    }

    var canRetry: Bool {
        switch self {
        case let .offline(_, retry): retry
        default: false
        }
    }

    var showsProgress: Bool {
        switch self {
        case .connecting: true
        default: false
        }
    }

    var systemImage: String {
        switch self {
        case .offline: "wifi.slash"
        case .connecting: "arrow.clockwise"
        case .backOnline: "checkmark.circle.fill"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .offline:
            Color(red: 0.88, green: 0.35, blue: 0.15)
        case .connecting:
            Color(red: 0.18, green: 0.48, blue: 0.68)
        case .backOnline:
            Theme.successGreen
        }
    }

    var tintColor: Color { backgroundColor }
}

struct ConnectAttemptState {
    let attempt: UInt64
    let reserved: ConnectionGeneration
    let wasOffline: Bool
    let watchdog: Task<Void, Never>
}

enum ConnectFailureDisposition: Equatable {
    case readinessRecovery
    case offlineRetry
    case disconnected
}

// MARK: - App model
