import SwiftUI

// MARK: - Pane chrome environment

private struct ShowsPaneSwitcherKey: EnvironmentKey {
    static let defaultValue = true
}

private struct ShowsPaneBackButtonKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether a pane shows its sibling-pane switcher strip. The split view
    /// turns it off while the list column is visible, because the list
    /// already switches panes.
    var showsPaneSwitcher: Bool {
        get { self[ShowsPaneSwitcherKey.self] }
        set { self[ShowsPaneSwitcherKey.self] = newValue }
    }

    /// Whether a pane draws its own Back control. Off in the split view's
    /// detail column, where the split view owns navigation.
    var showsPaneBackButton: Bool {
        get { self[ShowsPaneBackButtonKey.self] }
        set { self[ShowsPaneBackButtonKey.self] = newValue }
    }

    /// Closes the open item by clearing the list selection. The split view's
    /// detail column has no stack for `dismiss` to pop, so a pane that closes
    /// itself (workspace closed, last pane killed) uses this instead.
    var closeDetail: CloseDetailAction? {
        get { self[CloseDetailKey.self] }
        set { self[CloseDetailKey.self] = newValue }
    }
}

struct CloseDetailAction {
    let action: () -> Void
    func callAsFunction() { action() }

    /// Clears `selection` only while it still names `id`. A pane's close can
    /// finish after the user has opened another item (the SSH request runs in
    /// an unstructured task), and it must not close that other item.
    init(selection: Binding<String?>, id: String) {
        action = {
            if selection.wrappedValue == id { selection.wrappedValue = nil }
        }
    }
}

private struct CloseDetailKey: EnvironmentKey {
    static let defaultValue: CloseDetailAction? = nil
}

// MARK: - Selection split view

/// A list that opens its items in a second column on regular width and
/// pushes them on a stack on compact width. Both layouts read one
/// `selection`, a stable id, so folding or unfolding keeps the user's place:
/// the stack's path is derived from it, and the split view selects it.
///
/// Callers draw rows that set `selection` directly when `horizontalSizeClass`
/// is regular and use `NavigationLink(value: id)` when compact.
struct SelectionSplitView<Sidebar: View, Detail: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @SceneStorage(SidebarVisibility.storageKey)
    private var visibilityRaw = NavigationSplitViewVisibility.all.storageValue
    @Binding var selection: String?
    let emptyTitle: LocalizedStringKey
    let sidebar: Sidebar
    let detail: (String) -> Detail

    init(
        selection: Binding<String?>,
        emptyTitle: LocalizedStringKey,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: @escaping (String) -> Detail
    ) {
        _selection = selection
        self.emptyTitle = emptyTitle
        self.sidebar = sidebar()
        self.detail = detail
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { NavigationSplitViewVisibility(storageValue: visibilityRaw) },
            set: { visibilityRaw = $0.storageValue }
        )
    }

    /// Switching between the split view and the stack rebuilds the detail,
    /// so the open sibling pane is remembered here, above both layouts.
    @State private var openPaneMemory = OpenPaneMemory()

    /// The stack's path is just the selected id, so Back clears the selection.
    private var stackPath: Binding<[String]> {
        Binding(
            get: { selection.map { [$0] } ?? [] },
            set: { selection = $0.last }
        )
    }

    /// Clearing the selection empties the detail column and pops the stack.
    /// Scoped to the item the detail was built for.
    private func closeDetail(for id: String) -> CloseDetailAction {
        CloseDetailAction(selection: $selection, id: id)
    }

    var body: some View {
        layout
            .onChange(of: selection) { _, selected in
                if selected == nil { openPaneMemory.forget() }
            }
    }

    @ViewBuilder
    private var layout: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView(columnVisibility: columnVisibility) {
                sidebar
                    .safeAreaInset(edge: .bottom, spacing: 0) { SidebarTabSwitcher() }
                    .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 440)
            } detail: {
                Group {
                    if let selection {
                        detail(selection)
                            .environment(\.openPaneMemory, OpenPaneSlot(memory: openPaneMemory, selection: selection))
                            .environment(\.closeDetail, closeDetail(for: selection))
                            // A new item gets fresh pane state, not the last item's.
                            .id(selection)
                    } else {
                        ContentUnavailableView {
                            Label {
                                Text(emptyTitle)
                            } icon: {
                                // The herd's cat stands in for a symbol, as in the loading states.
                                Image("LaunchCat")
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 72)
                                    .accessibilityHidden(true)
                            }
                        }
                            .background(Theme.backgroundGradient.ignoresSafeArea())
                    }
                }
                .revealsSidebarOnEdgeSwipe(columnVisibility)
                .environment(\.showsPaneSwitcher, columnVisibility.wrappedValue == .detailOnly)
                .environment(\.showsPaneBackButton, false)
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack(path: stackPath) {
                sidebar
                    .navigationDestination(for: String.self) { id in
                        detail(id)
                            .environment(\.openPaneMemory, OpenPaneSlot(memory: openPaneMemory, selection: id))
                            .environment(\.closeDetail, closeDetail(for: id))
                    }
            }
        }
    }
}

/// The sibling pane open in the selected item's detail. It is keyed by the
/// list selection, which survives a size-class change that rebuilds the
/// detail; unlike the entry pane, the selection can't change underneath it.
/// Backing out clears it, so opening the item again starts fresh.
final class OpenPaneMemory {
    private var selection: String?
    private var paneID: String?

    func remember(_ paneID: String, forSelection selection: String) {
        self.selection = selection
        self.paneID = paneID
    }

    func paneID(forSelection selection: String) -> String? {
        self.selection == selection ? paneID : nil
    }

    func forget() {
        selection = nil
        paneID = nil
    }
}

/// `OpenPaneMemory` bound to the selection a detail was built for.
struct OpenPaneSlot {
    let memory: OpenPaneMemory
    let selection: String

    var paneID: String? { memory.paneID(forSelection: selection) }

    func remember(_ paneID: String) {
        memory.remember(paneID, forSelection: selection)
    }
}

private struct OpenPaneMemoryKey: EnvironmentKey {
    static let defaultValue: OpenPaneSlot? = nil
}

extension EnvironmentValues {
    var openPaneMemory: OpenPaneSlot? {
        get { self[OpenPaneMemoryKey.self] }
        set { self[OpenPaneMemoryKey.self] = newValue }
    }
}

extension NavigationSplitViewVisibility {
    /// `NavigationSplitViewVisibility` isn't `RawRepresentable`, so scene
    /// storage keeps it as a string.
    var storageValue: String {
        switch self {
        case .detailOnly: "detailOnly"
        case .doubleColumn: "doubleColumn"
        case .automatic: "automatic"
        default: "all"
        }
    }

    init(storageValue: String) {
        switch storageValue {
        case "detailOnly": self = .detailOnly
        case "doubleColumn": self = .doubleColumn
        case "automatic": self = .automatic
        default: self = .all
        }
    }
}

// MARK: - Readable width

extension View {
    /// Centres content in a readable column on regular width so Quota and
    /// Settings don't stretch across a whole iPad. Compact width is unchanged.
    func regularWidthReadable(maxWidth: CGFloat = 680) -> some View {
        modifier(RegularWidthReadable(maxWidth: maxWidth))
    }
}

private struct RegularWidthReadable: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}
