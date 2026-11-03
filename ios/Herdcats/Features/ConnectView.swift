import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Connect screen

enum OnboardingRoute: Equatable {
    static let introSeenKey = "hc.onboardingIntroSeen"

    case intro
    case connectionSelection

    static func initial(hasSeenIntro: Bool, hasSavedMachines: Bool, replay: Bool = false) -> Self {
        if replay { return .intro }
        return hasSeenIntro || hasSavedMachines ? .connectionSelection : .intro
    }
}

struct ConnectView: View {
    let replay: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppModel.self) private var appModel
    @AppStorage(OnboardingRoute.introSeenKey) private var hasSeenIntro = false
    @State private var recentConnections: [RecentConnection] = []
    @State private var selectedConnection: RecentConnection?
    @State private var signIn: ConnectionSignIn?
    @State private var attemptedSignIn: ConnectionSignIn?
    @State private var attempting = false
    @State private var showingSetupGuide = false
    @State private var openFormAfterSetup = false
    @State private var route: OnboardingRoute?
    @State private var showingManagement = false
    @State private var managementDefaults: UserDefaults?

    init(replay: Bool = false) {
        self.replay = replay
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                if let error = appModel.lastError {
                    if appModel.herdrMissingOnLastConnect {
                        MissingHerdrRecoveryCard(
                            inForm: false,
                            mismatch: appModel.runtimeMismatchOnLastConnect,
                            onConnect: connectWithInstalledRuntimeAction,
                            onSetup: { showingSetupGuide = true }
                        )
                    } else if appModel.herdrSessionUnavailableOnLastConnect {
                        SessionRecoveryCard(inForm: false)
                    } else {
                        ErrorBanner(message: error)
                    }
                }
                switch route {
                case nil:
                    EmptyView()
                case .intro:
                    introScreen
                case .connectionSelection:
                    header
                    if appModel.lastConnectNeedsSignIn, let attemptedSignIn {
                        Button("Update sign-in") {
                            var updated = attemptedSignIn
                            if !appModel.lastConnectPassphraseRejected { updated.secret = "" }
                            updated.passphrase = ""
                            signIn = updated
                        }
                        .buttonStyle(.herdrSecondary())
                    }
                    recentConnectionsSection
                    if recentConnections.isEmpty {
                        Button("Connection Setup Help") { showingSetupGuide = true }
                            .font(.jost(.subheadline))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 30)
            .padding(.bottom, 40)
        }
        .safeAreaInset(edge: .bottom) {
            if route == .intro {
                VStack(spacing: 4) {
                    Button("Continue") {
                        if !replay { hasSeenIntro = true }
                        route = .connectionSelection
                        openNewConnection()
                    }
                    .buttonStyle(.herdrPrimary())
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Theme.backgroundGradient)
            }
        }
        .onAppear {
            recentConnections = replay ? RecentConnectionStore.snapshot() : (try? RecentConnectionStore.load()) ?? []
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-connectionSelectionUITest") {
                recentConnections = [
                    RecentConnection(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, host: "studio-mac.local", port: 22, username: "alex", authMode: "password", remember: false),
                    RecentConnection(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, host: "build-server.local", port: 2222, username: "builder", authMode: "privateKey", remember: false)
                ]
                let defaults = UserDefaults(suiteName: "hc.connectionSelectionUITest")!
                defaults.removePersistentDomain(forName: "hc.connectionSelectionUITest")
                defaults.set(try? JSONEncoder().encode(recentConnections), forKey: RecentConnectionStore.storageKey)
                managementDefaults = defaults
                route = .connectionSelection
            }
            if let fixture = ConnectionUITestFixture.current, !fixture.cleanup {
                do {
                    try fixture.prepare()
                    recentConnections = [fixture.entry]
                    route = .connectionSelection
                } catch { appModel.lastError = error.localizedDescription }
            }
            #endif
            if route == nil {
                route = OnboardingRoute.initial(
                    hasSeenIntro: hasSeenIntro,
                    hasSavedMachines: !recentConnections.isEmpty,
                    replay: replay
                )
                if route == .connectionSelection && recentConnections.isEmpty && !replay {
                    openNewConnection()
                }
            }
        }
        .task {
            #if DEBUG
            if let fixture = ConnectionUITestFixture.current, fixture.cleanup {
                do {
                    try RecentConnectionStore.remove(fixture.entry)
                    try await SSHHostKeyStore.shared.removeUITestPin(host: fixture.entry.host, port: fixture.entry.port)
                    appModel.lastError = "Connection fixture cleaned up"
                } catch { appModel.lastError = error.localizedDescription }
            }
            #endif
        }
        .overlay {
            if appModel.isConnecting && selectedConnection == nil {
                LazyCatLoadingView(message: appModel.connectionProgressMessage)
                    .background(Theme.backgroundGradient.ignoresSafeArea())
            }
        }
        .sheet(item: $selectedConnection, onDismiss: {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-connectionSelectionUITest") { return }
            #endif
            if !replay { recentConnections = (try? RecentConnectionStore.load()) ?? recentConnections }
        }) { connection in
            ConnectionSettingsView(connection: connection, isReplay: replay, editing: !connection.host.isEmpty)
        }
        .sheet(isPresented: $showingManagement, onDismiss: {
            recentConnections = RecentConnectionStore.snapshot(defaults: managementDefaults ?? .standard)
        }) {
            ManageMachinesView(connections: recentConnections, defaults: managementDefaults ?? .standard)
        }
        .sheet(item: $signIn) { value in
            SavedConnectionSignInView(initial: value, replay: replay)
        }
        .background {
            // Only the foreground presentation owns a host-key challenge.
            if signIn == nil && selectedConnection == nil {
                Color.clear.hostKeyApprovalSheet {
                    if let attemptedSignIn { await dial(attemptedSignIn) }
                }
            }
        }
        .sheet(isPresented: $showingSetupGuide, onDismiss: {
            if openFormAfterSetup {
                openFormAfterSetup = false
                openNewConnection()
            }
        }, content: {
            HerdrSetupGuideView {
                openFormAfterSetup = true
                showingSetupGuide = false
            }
        })
    }

    private var introScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image("HerdrcatLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle.continuous(6))
                    .accessibilityHidden(true)
                Text("Herdcats")
                    .font(.jost(17, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            Text("Tame your autonomous agents from your pocket.")
                .font(.jost(34, weight: .bold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            AnimatedOnboardingBody()
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }

    private func openNewConnection() {
        selectedConnection = RecentConnection(
            host: "", port: 22, username: "", authMode: "password", remember: true
        )
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image("HerdrcatLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle.continuous(DesignSystem.CornerRadius.xl))
                .accessibilityHidden(true)
            VStack(spacing: 5) {
                Text("Herdcats")
                    .font(.appDisplay)
                Text(recentConnections.isEmpty
                     ? "Tame your autonomous coding agents from your iPhone."
                     : "Connect to a remote machine")
                    .font(.jost(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 14)
    }

    private func forget(_ connection: RecentConnection) {
        guard !replay else { return }
        do {
            recentConnections = try RecentConnectionStore.removeServer(connection)
        } catch {
            appModel.lastError = error.localizedDescription
            recentConnections = (try? RecentConnectionStore.load()) ?? recentConnections
        }
    }

    private var recentConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !recentConnections.isEmpty && !replay {
                HStack {
                    Spacer()
                    Button("Edit") { showingManagement = true }
                        .frame(minHeight: 44)
                        .accessibilityLabel("Manage Machines")
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 14) {
                let servers = RecentConnectionStore.servers(recentConnections)
                ForEach(servers) { connection in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            Task { await connectSaved(connection) }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    Text(connection.shortDisplayName(among: servers))
                                        .font(.jost(.headline))
                                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 44)
                                }
                                Image(systemName: "server.rack")
                                    .font(.jost(.title2))
                                    .foregroundStyle(Theme.accent)
                                Text("\(connection.username)@\(connection.host)")
                                    .font(.jost(.subheadline))
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .truncationMode(.middle)
                                Text("\(RecentConnectionStore.runtimeSummary(of: connection, in: recentConnections)) · Port \(String(connection.port))").font(.jost(.caption)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
                            .padding(16)
                            .herdrCard(showsBorder: false)
                        }
                        .buttonStyle(.herdrCard)
                        .accessibilityIdentifier("connect-machine-\(connection.id.uuidString)")
                        .accessibilityLabel("\(connection.shortDisplayName(among: servers)), \(connection.username) at \(connection.host), port \(String(connection.port)), \(RecentConnectionStore.runtimeSummary(of: connection, in: recentConnections))")
                        .accessibilityHint("Connects to this machine")
                        .contextMenu {
                            let runtimes = RecentConnectionStore.savedRuntimes(of: connection, in: recentConnections)
                            if runtimes.count > 1 {
                                ForEach(runtimes) { runtime in
                                    Button("Connect with \(runtime.backend.title)", systemImage: "arrow.left.arrow.right") {
                                        Task { await connectSaved(runtime) }
                                    }
                                }
                            }
                            if !replay {
                                Button("Forget Connection", systemImage: "trash", role: .destructive) { forget(connection) }
                            }
                        }
                        Button { selectedConnection = connection } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 20, weight: .medium))
                                .offset(y: 6)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .accessibilityLabel("Settings for \(connection.host)")
                        .accessibilityIdentifier("settings-machine-\(connection.id.uuidString)")
                    }
                }
            }

            Button {
                openNewConnection()
            } label: {
                Label(
                    recentConnections.isEmpty ? "Connect to a Remote Machine" : "New Connection",
                    systemImage: "plus"
                )
                .font(.jost(.headline))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 60)
                .padding(.horizontal, 16)
                .background(RoundedRectangle.continuous(DesignSystem.CornerRadius.xl).fill(Theme.cardBackground))
                .overlay {
                    RoundedRectangle.continuous(DesignSystem.CornerRadius.xl)
                        .strokeBorder(Theme.accent.opacity(0.65),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 7]))
                        .allowsHitTesting(false)
                }
            }
            .buttonStyle(.herdrCard)
        }
        .disabled(appModel.isConnecting || attempting)
    }

    private func connectSaved(_ connection: RecentConnection) async {
        guard !attempting, !appModel.isConnecting else { return }
        do {
            if attemptedSignIn?.entry.id != connection.id {
                appModel.lastError = nil
                appModel.lastConnectNeedsSignIn = false
                appModel.herdrMissingOnLastConnect = false
                appModel.runtimeMismatchOnLastConnect = nil
                appModel.herdrSessionUnavailableOnLastConnect = false
            }
            let value = try ConnectionSignIn.load(connection, readOnly: replay)
            attemptedSignIn = value
            if value.isReady { await dial(value) } else { signIn = value }
        } catch { appModel.lastError = error.localizedDescription }
    }

    /// The missing-runtime card's button, offered when the failed connection is
    /// one of the machines listed here.
    private var connectWithInstalledRuntimeAction: (() -> Void)? {
        guard !replay, let mismatch = appModel.runtimeMismatchOnLastConnect,
              let entry = recentConnections.first(where: { appModel.lastConnectWasFor($0) }) else { return nil }
        return { Task { await connectWithInstalledRuntime(mismatch.installed, from: entry) } }
    }

    /// Saves the runtime the machine has as a second entry for it, unless one is
    /// saved already, then connects with that entry. `entry` stays as it was.
    private func connectWithInstalledRuntime(_ backend: ConnectionBackend, from entry: RecentConnection) async {
        guard !attempting, !appModel.isConnecting else { return }
        do {
            let value: ConnectionSignIn
            if let attemptedSignIn, attemptedSignIn.entry.id == entry.id {
                // The sign-in that just reached the machine.
                value = attemptedSignIn
            } else {
                value = try ConnectionSignIn.load(entry)
            }
            let sibling = try value.siblingToConnect(backend)
            recentConnections = try RecentConnectionStore.load()
            await connectSaved(recentConnections.first { $0.id == sibling.entry.id } ?? sibling.entry)
        } catch { appModel.showPlainError(error.localizedDescription) }
    }

    private func dial(_ value: ConnectionSignIn) async {
        guard !attempting, !appModel.isConnecting else { return }
        attempting = true
        defer { attempting = false }
        attemptedSignIn = value
        do {
            if !replay { try value.prepareAttempt() }
            await appModel.connect(config: value.config)
            if case .connected = appModel.phase, !replay { try value.persist() }
        } catch { appModel.lastError = error.localizedDescription }
    }

}

/// Own the editable state inside the presented view so validation and the
/// authentication fields update together, including on the first presentation.
struct MissingHerdrRecoveryCard: View {
    let inForm: Bool
    /// Set when the machine has the other runtime; nil when it has neither.
    var mismatch: AppModel.RuntimeMismatch?
    /// Connects with the runtime the machine has. The card shows the button only when this is set.
    var onConnect: (() -> Void)?
    /// Opens the setup steps when Herdr was not found. When the machine has the
    /// other runtime, the card opens that runtime's steps itself.
    let onSetup: () -> Void
    @State private var showingInstalledRuntimeSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let mismatch {
                Text("SSH worked. This machine runs \(mismatch.installed.runtimeName).")
                    .font(.jost(.headline))
                Text("This connection is set to \(mismatch.saved.runtimeName), which isn't installed here.")
                    .font(.jost(.subheadline))
                    .foregroundStyle(.secondary)
                if let onConnect {
                    Button("Connect with \(mismatch.installed.title)", action: onConnect)
                        .buttonStyle(.herdrPrimary())
                }
                Button("See Setup Steps") { showingInstalledRuntimeSetup = true }
                    .font(.jost(.subheadline))
            } else {
                Text("SSH worked. Herdr was not found.")
                    .font(.jost(.headline))
                Text(
                    "Install the Herdr desktop app, Herdr Core, or the Herdr TUI on the remote machine. "
                    + (inForm
                        ? "Your connection details stay in this form. Then tap Connect again."
                        : "Then tap your machine to connect again.")
                )
                    .font(.jost(.subheadline))
                    .foregroundStyle(.secondary)
                Button("See Setup Steps", action: onSetup)
                    .buttonStyle(.herdrSecondary())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .herdrCard()
        .sheet(isPresented: $showingInstalledRuntimeSetup) {
            // Steps for the runtime the machine has. Installing the missing one would
            // start a second, separate Herdr.
            HerdrSetupGuideView(backend: mismatch?.installed ?? .tui)
        }
    }
}

struct SessionRecoveryCard: View {
    let inForm: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Herdr was found. Check its session.")
                .font(.jost(.headline))
            Text(
                "On the remote machine, run herdr from a project directory to start or attach "
                + "to the default session. "
                + (inForm
                    ? "Then tap Connect again here."
                    : "Then tap your machine to connect again.")
            )
                .font(.jost(.subheadline))
                .foregroundStyle(.secondary)
            Link("Herdr Quick Start", destination: URL(string: "https://herdr.dev/docs/quick-start/")!)
                .font(.jost(.subheadline))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .herdrCard()
    }
}

// MARK: - Animated onboarding body

struct AnimatedOnboardingBody: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleWordCount = 0

    private static let paragraph1Words = [
        "Herding", "AI", "agents", "used", "to", "feel", "impossible",
        "the", "moment", "you", "stepped", "away", "from", "your", "desk."
    ]

    private static let paragraph2Words = [
        "Herdcats", "connects", "directly", "to", "Herdr", "over", "SSH",
        "so", "you", "can", "monitor", "progress,", "unblock", "agents,",
        "and", "keep", "the", "herd", "moving —", "right", "from", "your", "iPhone."
    ]

    private static let totalWords = paragraph1Words.count + paragraph2Words.count

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            WordFlowLayout(horizontalSpacing: 7, verticalSpacing: 11) {
                ForEach(Array(Self.paragraph1Words.enumerated()), id: \.offset) { index, word in
                    let isVisible = index < visibleWordCount
                    Text(word)
                        .font(.jost(28, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                        .opacity(isVisible ? 1 : 0)
                        .offset(y: isVisible ? 0 : 5)
                        .blur(radius: isVisible ? 0 : 3)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: isVisible)
                }
            }

            WordFlowLayout(horizontalSpacing: 7, verticalSpacing: 11) {
                ForEach(Array(Self.paragraph2Words.enumerated()), id: \.offset) { index, word in
                    let globalIndex = Self.paragraph1Words.count + index
                    let isVisible = globalIndex < visibleWordCount
                    Text(word)
                        .font(.jost(28, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                        .opacity(isVisible ? 1 : 0)
                        .offset(y: isVisible ? 0 : 5)
                        .blur(radius: isVisible ? 0 : 3)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: isVisible)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.25)) {
                visibleWordCount = Self.totalWords
            }
        }
        .task {
            if reduceMotion {
                visibleWordCount = Self.totalWords
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            for i in 1...Self.totalWords {
                if Task.isCancelled { break }
                visibleWordCount = i
                let delay: UInt64 = (i == Self.paragraph1Words.count) ? 260_000_000 : 90_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Herding AI agents used to feel impossible the moment you stepped away from your desk. "
            + "Herdcats connects directly to Herdr over SSH so you can monitor progress, "
            + "unblock agents, and keep the herd moving—right from your iPhone."
        )
    }
}

private struct WordFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = (proposal.width == nil || proposal.width == .infinity) ? 350 : proposal.width!
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + horizontalSpacing
        }
        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + horizontalSpacing
        }
    }
}

struct SavedConnectionSignInView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let replay: Bool
    let requestsSecret: Bool
    let switcher: ActiveMachine?
    @State private var switchError: String?
    @State private var value: ConnectionSignIn
    @State private var attempting = false
    @State private var editingRejectedSecret = false
    @State private var keyImporterPresented = false
    @State private var importError: String?
    private var showsKeyEditor: Bool { value.isKey && (requestsSecret || editingRejectedSecret) }
    private var needsSignIn: Bool {
        switcher.map { $0.signInFailure?.needsSignIn ?? false } ?? appModel.lastConnectNeedsSignIn
    }
    private var passphraseRejected: Bool {
        switcher.map { $0.signInFailure?.passphraseRejected ?? false } ?? appModel.lastConnectPassphraseRejected
    }

    init(initial: ConnectionSignIn, replay: Bool, switcher: ActiveMachine? = nil) {
        self.replay = replay
        self.switcher = switcher
        requestsSecret = initial.needsSecret
        _value = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(value.entry.username) at \(value.entry.host):\(String(value.entry.port))")
                        .font(.jost(.headline))
                        .textSelection(.enabled)
                    if let error = switchError ?? (switcher == nil ? appModel.lastError : switcher?.pending?.lastError) {
                        ErrorBanner(message: error)
                    }
                    if appModel.herdrMissingOnLastConnect {
                        if let mismatch = appModel.runtimeMismatchOnLastConnect {
                            // The error above names the runtime the machine has.
                            if canConnectWithInstalledRuntime {
                                Button("Connect with \(mismatch.installed.title)") {
                                    Task { await connectWithInstalledRuntime(mismatch.installed) }
                                }
                                .buttonStyle(.herdrSecondary())
                                .disabled(attempting)
                            }
                        } else {
                            Text("Install the Herdr desktop app, Herdr Core, or the Herdr TUI on this machine, then try Connect again.")
                            Link("Herdr Quick Start", destination: URL(string: "https://herdr.dev/docs/quick-start/")!)
                        }
                    } else if appModel.herdrSessionUnavailableOnLastConnect {
                        SessionRecoveryCard(inForm: true)
                    }
                    if requestsSecret || editingRejectedSecret {
                        if value.isKey {
                            ConnectionPrivateKeyField(key: $value.secret) { keyImporterPresented = true }
                            if let importError { Text(importError).foregroundStyle(Theme.destructive) }
                            if !value.secret.isEmpty && value.needsSecret {
                                Text("Enter a valid OpenSSH ed25519 private key.").foregroundStyle(Theme.warning)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password").font(.jost(.subheadline, weight: .medium)).foregroundStyle(.secondary)
                                SecureField("Password", text: $value.secret).textContentType(.password)
                            }
                            .padding(12)
                            .modifier(ConnectionInputSurface())
                        }
                    }
                    if value.encrypted {
                        ConnectionPassphraseField(passphrase: $value.passphrase)
                        if value.entry.remember {
                            Toggle("Save passphrase on this iPhone", isOn: $value.savePassphrase)
                        }
                    }
                    Toggle("Save credentials on this iPhone", isOn: $value.entry.remember)
                    if needsSignIn {
                        Button("Update sign-in") {
                            editingRejectedSecret = !passphraseRejected
                            if editingRejectedSecret { value.secret = "" }
                            value.passphrase = ""
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.backgroundGradient)
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        Task {
                            await switcher?.cancelSwitch()
                            dismiss()
                        }
                    }.disabled(attempting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Connect") { Task { await connect() } }
                    .buttonStyle(.herdrPrimary())
                    .disabled(!value.isReady || attempting)
                    .padding(16)
                    .background(Theme.backgroundGradient)
            }
        }
        .overlay {
            if attempting {
                LazyCatLoadingView(message: switcher?.pending?.connectionProgressMessage ?? appModel.connectionProgressMessage)
                    .background(Theme.backgroundGradient.ignoresSafeArea())
            }
        }
        .fileImporter(isPresented: $keyImporterPresented, allowedContentTypes: [.item, .data, .plainText]) { result in
            do {
                value.secret = try ConnectionSignIn.importPrivateKey(from: result.get())
                importError = nil
            } catch {
                if (error as? CocoaError)?.code != .userCancelled { importError = error.localizedDescription }
            }
        }
        .onChange(of: value.secret) { _, _ in
            value.passphrase = ""
            value.savePassphrase = false
        }
        .background {
            if switcher == nil {
                Color.clear.hostKeyApprovalSheet { await connect() }
            } else if let switcher, let pending = switcher.pending {
                Color.clear.hostKeyApprovalSheet(onCancelled: {
                    guard switcher.pending === pending else { return }
                    await switcher.cancelSwitch()
                }, onApproved: {
                    guard switcher.pending === pending else { return }
                    attempting = true
                    defer { attempting = false }
                    do { handleSwitchOutcome(try await switcher.finishSignIn(using: value, replay: replay)) }
                    catch { switchError = error.localizedDescription }
                })
                .environment(pending)
                .id(ObjectIdentifier(pending))
            }
        }
        .onAppear { switcher?.pendingHostKeyOwnedByForm = true }
        .onDisappear {
            switcher?.pendingHostKeyOwnedByForm = false
            if let switcher, let pending = switcher.pending {
                Task { if switcher.pending === pending { await switcher.cancelSwitch() } }
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize || showsKeyEditor ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(attempting)
    }

    private func connect() async {
        guard !attempting, !appModel.isConnecting else { return }
        attempting = true
        defer { attempting = false }
        do {
            if let switcher {
                switchError = nil
                handleSwitchOutcome(try await switcher.signIn(using: value, replay: replay))
            } else {
                if !replay { try value.prepareAttempt() }
                await appModel.connect(config: value.config)
                guard case .connected = appModel.phase else { return }
                if !replay { try value.persist() }
                dismiss()
            }
        } catch {
            if switcher != nil { switchError = error.localizedDescription }
            else { appModel.lastError = error.localizedDescription }
        }
    }

    /// The last connect failed for this sign-in's machine and runtime.
    private var canConnectWithInstalledRuntime: Bool {
        switcher == nil && !replay && appModel.lastConnectWasFor(value.entry)
    }

    /// Saves the runtime the machine has as a second entry, unless one is saved
    /// already, then connects with it using this sign-in.
    private func connectWithInstalledRuntime(_ backend: ConnectionBackend) async {
        guard !attempting, !appModel.isConnecting else { return }
        do {
            value = try value.siblingToConnect(backend)
        } catch {
            appModel.showPlainError(error.localizedDescription)
            return
        }
        await connect()
    }

    private func handleSwitchOutcome(_ outcome: ActiveMachine.SwitchOutcome) {
        switch outcome {
        case .switched, .alreadyActive: dismiss()
        case .failed:
            if switcher?.pending?.hostKeyChallenge == nil {
                switchError = switcher?.switchError ?? "Connection failed"
                switcher?.switchError = nil
            }
        case .needsCredentials, .superseded: break
        }
    }
}

struct ManageMachinesView: View {
    @Environment(\.dismiss) private var dismiss
    let defaults: UserDefaults
    @State private var draft: RecentConnectionStore.ManagementDraft
    @State private var renaming: RecentConnection?
    @State private var error: String?

    init(connections: [RecentConnection], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _draft = State(initialValue: RecentConnectionStore.ManagementDraft(connections: connections))
    }

    var body: some View {
        NavigationStack {
            List {
                if let error { ErrorBanner(message: error) }
                ForEach(draft.servers) { connection in
                    Button {
                        renaming = connection
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connection.displayName).font(.jost(.headline))
                            Text("\(connection.username)@\(connection.host) · Port \(String(connection.port))")
                                .font(.jost(.subheadline)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("manage-machine-\(connection.id.uuidString)")
                }
                .onMove { draft.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { draft.delete(at: $0) }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient)
            .navigationTitle("Manage Machines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").frame(width: 48, height: 48)
                    }
                    .accessibilityLabel("Close")
                    .accessibilityHint("Discard management changes")
                    .accessibilityIdentifier("manage-machines-close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        do { try draft.save(defaults: defaults); dismiss() }
                        catch { self.error = error.localizedDescription }
                    } label: {
                        Image(systemName: "checkmark").frame(width: 48, height: 48)
                    }
                    .accessibilityLabel("Save Changes")
                    .accessibilityIdentifier("manage-machines-save")
                }
            }
            .sheet(item: $renaming) { connection in
                RenameMachineView(connection: connection) { name in
                    draft.rename(id: connection.id, to: name)
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct RenameMachineView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String) throws -> Void
    @State private var name: String
    @State private var error: String?

    init(connection: RecentConnection, onSave: @escaping (String) throws -> Void) {
        self.onSave = onSave
        _name = State(initialValue: connection.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (optional)", text: $name)
                if let error { ErrorBanner(message: error) }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient)
            .navigationTitle("Rename Machine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try onSave(name); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

#if DEBUG
/// Opt-in simulator fixture; its profile and host trust have a unique run identity.
private struct ConnectionUITestFixture {
    let entry: RecentConnection
    let key: String
    let cleanup: Bool

    static var current: Self? {
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("-connectionReadyUITest"),
              let run = process.environment["HC_CONNECTION_READY_RUN"], let id = UUID(uuidString: run),
              let key = process.environment["HC_CONNECTION_READY_KEY"],
              let port = Int(process.environment["HC_CONNECTION_READY_PORT"] ?? ""),
              let user = process.environment["HC_CONNECTION_READY_USER"] else { return nil }
        return Self(entry: RecentConnection(id: id, host: "127.0.0.1", port: port,
            username: user, authMode: "privateKey", remember: true), key: key,
            cleanup: process.arguments.contains("-connectionFixtureCleanup"))
    }

    func prepare() throws {
        try KeychainStore.save(key, account: entry.secretAccount)
        try RecentConnectionStore.record(entry, in: RecentConnectionStore.load(), stampConnected: false)
    }
}
#endif
