import SwiftUI
import UIKit

// MARK: - Status visuals

extension AgentStatus {
    /// System colors for status badges and dots, matching the Herdr TUI
    /// (`state_dot` / `state_label_color`). Quota, warnings and destructive
    /// actions keep the Moonlit `Theme.status*` tokens.
    var color: Color {
        switch self {
        case .working: .yellow
        case .blocked: .red
        case .unknown: .gray
        case .done: .teal
        case .idle: .green
        }
    }
}

/// Per-agent-kind branding for known agents, with graceful fallbacks.
enum AgentKindVisual {
    static func color(for kind: String) -> Color {
        switch kind {
        case "cursor": Color(red: 0.55, green: 0.75, blue: 0.95)
        case "codex": Color(red: 0.09, green: 0.64, blue: 0.51) // OpenAI green
        case "claude": Color(red: 0.85, green: 0.47, blue: 0.34) // Anthropic Claude
        case "pi": Color(red: 0.94, green: 0.56, blue: 0.51) // pi.dev coral
        case "agy", "agy-claude", "gemini": Color(red: 0.56, green: 0.46, blue: 0.70) // Gemini purple
        case "zai": Color(red: 0.12, green: 0.39, blue: 0.93) // Z.AI blue
        case "alibaba": Color(red: 0.95, green: 0.45, blue: 0.15)
        case "copilot": Color(red: 0.45, green: 0.55, blue: 0.95)
        case "grok": Color(red: 0.85, green: 0.85, blue: 0.90)
        case "kimi": Color(red: 0.35, green: 0.70, blue: 0.55)
        case "opencode-go": Color(red: 0.30, green: 0.70, blue: 0.65)
        default: .gray
        }
    }

    /// Asset-catalog brand mark when available; otherwise fall back to `symbol(for:)`.
    static func assetName(for kind: String) -> String? {
        switch kind {
        case "cursor": "AgentCursor"
        case "codex": "AgentCodex"
        case "claude": "AgentClaude"
        case "pi": "AgentPi"
        case "agy", "agy-claude", "gemini": "AgentGemini"
        case "zai": "AgentZai"
        default: nil
        }
    }

    /// Pi keeps its multi-color mark; other brand assets are template-tinted.
    static func usesOriginalAssetColors(for kind: String) -> Bool {
        kind == "pi"
    }

    static func symbol(for kind: String) -> String {
        switch kind {
        case "cursor": "cursorarrow.rays"
        case "codex": "sparkles"
        case "claude": "terminal.fill"
        case "pi": "function"
        case "agy", "agy-claude", "gemini": "diamond.fill"
        case "zai": "flame.fill"
        case "alibaba": "shippingbox.fill"
        case "copilot": "chevron.left.forwardslash.chevron.right"
        case "grok": "bolt.fill"
        case "kimi": "moon.stars.fill"
        case "opencode-go": "hammer.fill"
        default: "cpu"
        }
    }

    static func displayName(for kind: String) -> String {
        kind.prefix(1).uppercased() + kind.dropFirst()
    }
}

// MARK: - Status dot

struct StatusDot: View {
    let status: AgentStatus
    var animated = false

    @State private var pulsing = false

    var body: some View {
        Group {
            if status == .working {
                WorkingStatusIcon()
            } else {
                Circle()
                    .fill(status == .idle ? Color.clear : status.color)
                    .overlay {
                        if status == .idle {
                            Circle().strokeBorder(status.color, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 9, height: 9)
                    .scaleEffect(animated && pulsing ? 1.25 : 0.9)
                    .animation(
                        animated ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                        value: pulsing
                    )
                    .onAppear {
                        guard animated else { return }
                        pulsing = true
                    }
            }
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Navigation title

struct StatusNavigationTitle: View {
    let title: String
    let status: AgentStatus
    var subtitle: String? = nil
    var agent: String? = nil

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 6) {
                StatusDot(status: status, animated: status == .working)
                Text(title)
                    .font(.jost(.headline))
                    .lineLimit(1)
            }
            if let subtitle, !subtitle.isEmpty {
                HStack(spacing: 4) {
                    if let agent, !agent.isEmpty {
                        AgentKindIcon(kind: agent, size: 10)
                    }
                    Text(subtitle)
                        .font(.jost(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if let agent, !agent.isEmpty {
                AgentKindIcon(kind: agent, size: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isHeader)
    }

    private var accessibilityText: String {
        var parts: [String] = [title]
        if let agent, !agent.isEmpty {
            parts.append(AgentKindVisual.displayName(for: agent))
        }
        if let subtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }
        parts.append(status.label)
        return parts.joined(separator: ", ")
    }
}

// MARK: - Status pill

struct StatusPill: View {
    let status: AgentStatus

    var body: some View {
        HStack(spacing: 5) {
            StatusDot(status: status, animated: status == .working)
            Text(status.label)
                .font(.jost(.caption2, weight: .semibold))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(status.color.opacity(0.16)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.label)
    }
}

// MARK: - Agent badge

struct AgentBadge: View {
    let kind: String

    private var tint: Color { AgentKindVisual.color(for: kind) }

    var body: some View {
        HStack(spacing: 4) {
            AgentKindIcon(kind: kind, size: 10)
            Text(AgentKindVisual.displayName(for: kind))
                .font(.jost(10, weight: .bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(tint.opacity(0.15))
        )
    }
}

/// Badge for a plain shell pane with no recognized agent.
struct CommandLineBadge: View {
    private var tint: Color { .secondary }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "terminal")
                .font(.jost(10, weight: .bold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text("Command line")
                .font(.jost(10, weight: .bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Theme.subtleFill)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Command line")
    }
}

/// Brand mark from the asset catalog when present; SF Symbol otherwise.
struct AgentKindIcon: View {
    let kind: String
    var size: CGFloat = 10

    @ViewBuilder
    var body: some View {
        if let asset = AgentKindVisual.assetName(for: kind) {
            if AgentKindVisual.usesOriginalAssetColors(for: kind) {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .accessibilityHidden(true)
            } else {
                Image(asset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .foregroundStyle(AgentKindVisual.color(for: kind))
                    .accessibilityHidden(true)
            }
        } else {
            Image(systemName: AgentKindVisual.symbol(for: kind))
                .font(.jost(size, weight: .bold))
                .foregroundStyle(AgentKindVisual.color(for: kind))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Quiet list rows

extension VerticalAlignment {
    private enum ListTitleCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let listTitleCenter = VerticalAlignment(ListTitleCenter.self)
}

/// Shared geometry for the Spaces and Agents lists: a narrow leading status
/// column replaces the `#number`, so every title starts at the same x.
enum QuietListMetrics {
    static let statusColumn: CGFloat = 14
    static let columnSpacing: CGFloat = 10
    /// Gap between a row's title line and its detail line.
    static let lineSpacing: CGFloat = 4
    static let rowVerticalPadding: CGFloat = 11
    static var titleInset: CGFloat { statusColumn + columnSpacing }
}

/// Visible separator under a list row, inset to the title column.
struct QuietListDivider: View {
    var leadingInset: CGFloat = QuietListMetrics.titleInset

    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

/// Last-activity time pinned to a row's top-right corner.
struct RowTimestamp: View {
    let date: Date?

    var body: some View {
        if let date {
            Text(PaneUpdatedFormat.label(for: date))
                .font(.jost(.footnote))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - Stat chip

struct StatChip: View {
    let icon: String
    let value: String
    let caption: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.jost(10, weight: .semibold))
            Text(value)
                .font(.jost(13, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(value)")
    }
}

// MARK: - Repo pill

struct RepoPill: View {
    let worktree: Worktree

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: worktree.isLinkedWorktree ? "arrow.triangle.branch" : "folder.fill")
                .font(.jost(9, weight: .semibold))
            Text(worktree.repoName)
                .font(.jost(11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.subtleFill))
    }
}

// MARK: - Error banner

struct ErrorBanner: View {
    let message: String
    var dismiss: (() -> Void)? = nil
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
                .font(.jost(14, weight: .semibold))
            Text(message)
                .font(.jost(.footnote))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let retry {
                Button("Retry", action: retry)
                    .buttonStyle(.herdrSecondary(fullWidth: false))
                    .controlSize(.small)
            }
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss error")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle.continuous(DesignSystem.CornerRadius.lg)
                .fill(Theme.warning.opacity(0.12))
        )
    }
}

// MARK: - Connection status bar

private struct ConnectionRetryActionKey: EnvironmentKey {
    static var defaultValue: (() -> Void)? { nil }
}

extension EnvironmentValues {
    var connectionRetryAction: (() -> Void)? {
        get { self[ConnectionRetryActionKey.self] }
        set { self[ConnectionRetryActionKey.self] = newValue }
    }
}

struct ConnectionRecoveryLayout {
    var hasContentRetry = false
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
}

struct ConnectionRecoveryLayoutKey: PreferenceKey {
    static var defaultValue: ConnectionRecoveryLayout { .init() }
    static func reduce(value: inout ConnectionRecoveryLayout, nextValue: () -> ConnectionRecoveryLayout) {
        let next = nextValue()
        value.hasContentRetry = value.hasContentRetry || next.hasContentRetry
        value.topInset = max(value.topInset, next.topInset)
        value.bottomInset = max(value.bottomInset, next.bottomInset)
    }
}

/// The session owner supplies recovery beneath the offline explanation.
/// Reporting this placement suppresses the retained-content recovery card.
struct ConnectionContentRetryButton: View {
    @Environment(\.connectionRetryAction) private var retryAction

    var body: some View {
        if let retryAction {
            OutlinedConnectionRetryButton(action: retryAction)
                .preference(key: ConnectionRecoveryLayoutKey.self, value: .init(hasContentRetry: true))
        }
    }
}

private struct OutlinedConnectionRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button("Retry", action: action)
            .buttonStyle(.herdrSecondary(fullWidth: false))
            .controlSize(.regular)
            .accessibilityIdentifier("connection-content-retry")
    }
}

/// Retains cached content and supplies recovery when no offline empty state is shown.
private struct ConnectionRecoveryCard: View {
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("You're offline. Reconnect to bring the cats back.")
                .font(.jost(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            OutlinedConnectionRetryButton(action: retryAction)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .modifier(PaneInputGlassSurface(cornerRadius: 24, backgroundOpacity: 0.98))
        .padding(16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connection-offline-recovery")
    }
}

/// Keeps recovery within the usable output area even with a tall draft and keyboard.
struct ConnectionRecoveryViewport<Recovery: View>: View {
    let recovery: Recovery

    init(@ViewBuilder recovery: () -> Recovery) {
        self.recovery = recovery()
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            recovery
            ScrollView {
                recovery.frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ConnectionStatusBar: View {
    let banner: ConnectionBanner

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: banner.systemImage)
                .font(.jost(13, weight: .bold))

            Text(banner.message)
                .font(.jost(13, weight: .semibold))
                .lineLimit(1)

            if banner.showsProgress {
                CircularArcSpinner(size: 13, color: banner.tintColor)
            }
        }
        .foregroundStyle(banner.tintColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(banner.message)
        .accessibilityIdentifier("connection-status-bar")
    }
}

struct ConnectionStatusBannerModifier: ViewModifier {
    let banner: ConnectionBanner?
    var retryAction: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(ConnectionRecoveryLayoutKey.self) { layout in
                if !layout.hasContentRetry, banner?.canRetry == true, let retryAction {
                    ConnectionRecoveryViewport {
                        ConnectionRecoveryCard(retryAction: retryAction)
                    }
                    .padding(.top, layout.topInset)
                    .padding(.bottom, layout.bottomInset)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let banner {
                    ConnectionStatusBar(banner: banner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .environment(\.connectionRetryAction, banner?.canRetry == true ? retryAction : nil)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: banner)
    }
}

extension View {
    /// Insets the top of the scrollable content with the connection status bar,
    /// ensuring it sits beneath the navigation bar without overlapping content.
    func connectionStatusBanner(banner: ConnectionBanner?, retryAction: (() -> Void)? = nil) -> some View {
        modifier(ConnectionStatusBannerModifier(banner: banner, retryAction: retryAction))
    }

    /// Convenience overload resolving the current session from the given `AppModel`.
    /// A machine switch in progress (or its failure) takes this slot too, so it
    /// sits beneath each screen's navigation bar like every other status.
    func connectionStatusBanner(appModel: AppModel) -> some View {
        modifier(SessionStatusBannerModifier(appModel: appModel))
    }
}

private struct SessionStatusBannerModifier: ViewModifier {
    let appModel: AppModel
    @Environment(ActiveMachine.self) private var active: ActiveMachine?

    func body(content: Content) -> some View {
        content
            .connectionStatusBanner(
                banner: active?.pendingLabel.map { .connecting(message: "Connecting to \($0)…") }
                    ?? appModel.connectionBanner
            ) {
                Task { await appModel.reconnect() }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let active, let error = active.switchError {
                    ErrorBanner(message: error, dismiss: { active.switchError = nil })
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("machine-switch-error")
                }
            }
    }
}

// MARK: - Host key approval

extension View {
    /// Presents SSH host key approval or verified replacement; `onApproved` retries the connection.
    func hostKeyApprovalSheet(
        onCancelled: (@MainActor () async -> Void)? = nil,
        onApproved: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(HostKeyApprovalModifier(onCancelled: onCancelled, onApproved: onApproved))
    }
}

private struct HostKeyApprovalModifier: ViewModifier {
    @Environment(AppModel.self) private var appModel
    let onCancelled: (@MainActor () async -> Void)?
    let onApproved: @MainActor () async -> Void

    func body(content: Content) -> some View {
        content.sheet(item: Binding(
            get: { appModel.hostKeyChallenge.map(HostKeyApprovalItem.init) },
            set: { if $0 == nil, appModel.hostKeyChallenge != nil { appModel.cancelHostKeyApproval() } }
        ), onDismiss: {
            if appModel.hostKeyVerificationBlocked {
                Task { await onCancelled?() }
            }
        }) { item in
            HostKeyApprovalView(challenge: item.challenge, onApproved: onApproved)
                .id(item.id)
        }
    }
}

private struct HostKeyApprovalItem: Identifiable {
    let challenge: SSHHostKeyChallenge
    var id: String { "\(challenge.host):\(challenge.port) \(challenge.publicKey) \(challenge.previousPublicKey ?? "")" }
}

private struct HostKeyApprovalView: View {
    @Environment(AppModel.self) private var appModel
    let challenge: SSHHostKeyChallenge
    let onApproved: @MainActor () async -> Void
    @State private var isApproving = false
    @State private var approvalError: String?
    @State private var verifiedReplacement = false

    private var isReplacement: Bool { challenge.previousPublicKey != nil }

    private func fingerprint(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.jost(.subheadline, weight: .semibold))
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle.continuous(DesignSystem.CornerRadius.lg)
                        .fill(Theme.fieldBackground)
                )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(isReplacement
                        ? "The SSH identity of \(challenge.host):\(challenge.port) has changed. Connection is blocked. "
                            + "This can happen after a rebuild or key rotation, but could also mean someone is impersonating your computer."
                        : "Herdcats hasn't connected to \(challenge.host):\(challenge.port) before. "
                            + "Compare this fingerprint with the server's before you trust it.")
                        .font(.jost(.subheadline))
                        .foregroundStyle(.secondary)
                    if let previousFingerprint = challenge.previousFingerprint {
                        fingerprint(previousFingerprint, label: "Previously approved fingerprint")
                    }
                    fingerprint(challenge.fingerprint, label: isReplacement ? "New fingerprint" : "Server fingerprint")
                    Text("Verify the fingerprint directly on your computer or with its administrator through a trusted channel. "
                        + "For an Ed25519 host key, run on the server: ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub")
                        .font(.jost(.footnote))
                        .foregroundStyle(.secondary)
                    if isReplacement {
                        Toggle("I verified the new fingerprint through a trusted channel", isOn: $verifiedReplacement)
                            .font(.jost(.subheadline))
                            .disabled(isApproving)
                        Text("Replacing this key updates trust only for this hostname and port. Your login credentials are kept.")
                            .font(.jost(.footnote))
                            .foregroundStyle(.secondary)
                    }
                    if let error = approvalError {
                        Text(error)
                            .font(.jost(.footnote))
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task {
                            isApproving = true
                            defer { isApproving = false }
                            approvalError = nil
                            if await appModel.approveHostKey(challenge) {
                                await onApproved()
                            } else {
                                approvalError = appModel.lastError
                            }
                        }
                    } label: {
                        Text(isReplacement ? "Replace Approved Key and Connect" : "Trust and Connect")
                    }
                    .buttonStyle(.herdrPrimary)
                    .disabled(isApproving || (isReplacement && !verifiedReplacement))
                }
                .padding(20)
            }
            .background(Theme.backgroundGradient)
            .navigationTitle(isReplacement ? "Host Key Changed" : "Verify Host Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        appModel.cancelHostKeyApproval()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.jost(16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Close")
                    .disabled(isApproving)
                }
            }
        }
        .interactiveDismissDisabled(isApproving)
    }
}
