import SwiftUI
import UIKit

// MARK: - Sidebar tabs

/// What the sidebar's tab switcher needs from `ConnectedTabsView`: the
/// selected tab and the blocked-agent count for the Agents badge.
struct SidebarTabs {
    var selection: Binding<ConnectedTabsView.MainTab>
    var blockedCount: Int
}

private struct SidebarTabsKey: EnvironmentKey {
    static let defaultValue: SidebarTabs? = nil
}

extension EnvironmentValues {
    var sidebarTabs: SidebarTabs? {
        get { self[SidebarTabsKey.self] }
        set { self[SidebarTabsKey.self] = newValue }
    }
}

extension ConnectedTabsView.MainTab {
    var title: LocalizedStringKey {
        switch self {
        case .spaces: "Spaces"
        case .agents: "Agents"
        case .quota: "Quota"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .spaces: "square.grid.3x3"
        case .agents: "cpu"
        case .quota: "gauge.with.dots.needle.67percent"
        case .settings: "gearshape"
        }
    }

    static let displayOrder: [ConnectedTabsView.MainTab] = [.spaces, .agents, .quota, .settings]
}

/// Whether the tab switcher moves into the sidebar. Regular-width iPhones
/// (the Duo unfolded) keep the system tab bar across the bottom; the sidebar
/// pill is for iPad, whose system bar would float over the detail column.
enum SidebarTabLayout {
    static func usesSidebarSwitcher(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
        sizeClass == .regular && UIDevice.current.userInterfaceIdiom != .phone
    }
}

/// Column visibility is shared by every tab, so collapsing the sidebar in one
/// tab keeps it collapsed after switching to another.
enum SidebarVisibility {
    static let storageKey = "sidebar.columnVisibility"
}

// MARK: - Switcher

/// The tab switcher on regular width. It floats at the bottom of the sidebar
/// in place of the system tab bar, which floats over the detail column on iPad.
struct SidebarTabSwitcher: View {
    @Environment(\.sidebarTabs) private var tabs
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if let tabs {
            HStack(spacing: 2) {
                ForEach(ConnectedTabsView.MainTab.displayOrder, id: \.self) { tab in
                    item(tab, tabs: tabs)
                }
            }
            .padding(4)
            .modifier(FloatingGlass(reduceTransparency: reduceTransparency))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sidebar-tab-switcher")
        }
    }

    private func item(_ tab: ConnectedTabsView.MainTab, tabs: SidebarTabs) -> some View {
        let isSelected = tabs.selection.wrappedValue == tab
        return Button {
            tabs.selection.wrappedValue = tab
        } label: {
            VStack(spacing: 2) {
                // Filled symbols at the system tab bar's size.
                Image(systemName: tab.systemImage)
                    .font(.system(size: 22))
                    .symbolVariant(.fill)
                    .frame(height: 26)
                    .overlay(alignment: .topTrailing) {
                        if tab == .agents, tabs.blockedCount > 0 {
                            Text("\(tabs.blockedCount)")
                                .font(.jost(9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(Color.red, in: Capsule())
                                .offset(x: 11, y: -5)
                        }
                    }
                Text(tab.title)
                    .font(.jost(10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Theme.accent : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule().fill(Color.primary.opacity(0.1))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Like the system tab bar, whose fixed-size items show a larger
        // version of themselves while pressed at accessibility text sizes.
        .accessibilityShowsLargeContentViewer {
            Label(tab.title, systemImage: tab.systemImage)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("sidebar-tab-\(tab.rawValue)")
    }
}

/// The floating capsule the navigation bar gives its trailing buttons on iOS 26.
private struct FloatingGlass: ViewModifier {
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(Theme.cardBackground, in: Capsule())
            } else if #available(iOS 26.0, *) {
                content.glassEffect(.regular.interactive(), in: Capsule())
            } else {
                content.background(.ultraThinMaterial, in: Capsule())
            }
        }
        // The sidebar is nearly the glass's own colour, which hides its rim.
        .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: 1).allowsHitTesting(false) }
    }
}

// MARK: - Edge swipe

extension View {
    /// A swipe right from the leading edge brings the sidebar back while it
    /// is hidden. The strip exists only then, so it never takes touches from
    /// the content when the sidebar is showing.
    func revealsSidebarOnEdgeSwipe(_ visibility: Binding<NavigationSplitViewVisibility>) -> some View {
        overlay(alignment: .leading) {
            if visibility.wrappedValue == .detailOnly {
                Color.clear
                    .frame(width: 20)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { drag in
                                guard drag.translation.width > 40,
                                      abs(drag.translation.height) < drag.translation.width else { return }
                                withAnimation { visibility.wrappedValue = .all }
                            }
                    )
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Tabs without a list

/// Quota and Settings on regular width: the sidebar is only the tab switcher,
/// and the screen fills the detail column. Compact width shows the screen
/// as it always did.
struct TabSplitView<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @SceneStorage(SidebarVisibility.storageKey)
    private var visibilityRaw = NavigationSplitViewVisibility.all.storageValue
    let hint: LocalizedStringKey
    let content: Content

    init(hint: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.hint = hint
        self.content = content()
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { NavigationSplitViewVisibility(storageValue: visibilityRaw) },
            set: { visibilityRaw = $0.storageValue }
        )
    }

    var body: some View {
        // The sidebar holds only the tab switcher, so without it there is
        // nothing to split.
        if SidebarTabLayout.usesSidebarSwitcher(horizontalSizeClass) {
            NavigationSplitView(columnVisibility: columnVisibility) {
                Text(hint)
                    .font(.jost(.footnote))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.listBackground.ignoresSafeArea())
                    .safeAreaInset(edge: .bottom, spacing: 0) { SidebarTabSwitcher() }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 440)
            } detail: {
                content
                    .revealsSidebarOnEdgeSwipe(columnVisibility)
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            content
        }
    }
}

extension View {
    /// The sidebar's tab switcher replaces the system tab bar where it is used.
    func hidesSystemTabBarForSidebarSwitcher(_ sizeClass: UserInterfaceSizeClass?) -> some View {
        modifier(HidesSystemTabBar(isHidden: SidebarTabLayout.usesSidebarSwitcher(sizeClass)))
    }
}

private struct HidesSystemTabBar: ViewModifier {
    let isHidden: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.background(SystemTabBarHider(isHidden: isHidden))
        } else {
            // No UIKit hook before iOS 18, which also has no floating bar
            // whose top inset the SwiftUI modifier would leave behind.
            content.toolbar(isHidden ? .hidden : .automatic, for: .tabBar)
        }
    }
}

/// Hides the enclosing `UITabBarController`'s bar. SwiftUI's
/// `.toolbar(.hidden, for: .tabBar)` hides the iPad floating bar but leaves
/// its top inset on the tab shown at launch; UIKit updates the inset itself.
private struct SystemTabBarHider: UIViewControllerRepresentable {
    let isHidden: Bool

    func makeUIViewController(context: Context) -> Probe { Probe() }

    func updateUIViewController(_ probe: Probe, context: Context) {
        probe.isBarHidden = isHidden
        probe.apply()
    }

    final class Probe: UIViewController {
        var isBarHidden = false

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        func apply() {
            guard #available(iOS 18.0, *), let controller = tabBarController,
                  controller.isTabBarHidden != isBarHidden else { return }
            controller.setTabBarHidden(isBarHidden, animated: false)
        }
    }
}
