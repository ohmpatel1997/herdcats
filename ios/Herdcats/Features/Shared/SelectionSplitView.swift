import Observation
import SwiftUI

// MARK: - Pane chrome environment

private struct ShowsPaneSwitcherKey: EnvironmentKey {
    static let defaultValue = true
}

/// Shows or hides the list column. A split pane's own header carries the button,
/// because the system toolbar that normally holds it is hidden while split.
struct SidebarToggleAction {
    /// While the list shows, its own toolbar has the button, so a pane's header leaves it out.
    let isListShowing: Bool
    let action: () -> Void
    func callAsFunction() { action() }
}

private struct SidebarToggleKey: EnvironmentKey {
    static let defaultValue: SidebarToggleAction? = nil
}

private struct ShowsPaneBackButtonKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether a pane shows its sibling-pane switcher strip. On by default,
    /// in the detail column and each split slot alike; a screen can turn it off.
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

    var sidebarToggle: SidebarToggleAction? {
        get { self[SidebarToggleKey.self] }
        set { self[SidebarToggleKey.self] = newValue }
    }

    /// Closes this pane's slot. The split view's detail column has no stack
    /// for `dismiss` to pop, so a pane that closes itself (workspace closed,
    /// last pane killed) uses this instead.
    var closeDetail: CloseDetailAction? {
        get { self[CloseDetailKey.self] }
        set { self[CloseDetailKey.self] = newValue }
    }
}

struct CloseDetailAction {
    let action: () -> Void
    func callAsFunction() { action() }

    /// Closes `slot` only while it still holds `ref`. A pane's close can
    /// finish after the user has opened another pane there (the SSH request
    /// runs in an unstructured task), and it must not close that other pane.
    /// In the compact stack, closing also pops back to the list.
    init(layout: Binding<PaneLayout>, slot: PaneLayout.Slot, ref: PaneRef, popsCompactStack: Bool = false) {
        action = {
            guard layout.wrappedValue.ref(in: slot) == ref else { return }
            layout.wrappedValue.close(slot)
            if popsCompactStack { layout.wrappedValue.compactDetailVisible = false }
        }
    }
}

private struct CloseDetailKey: EnvironmentKey {
    static let defaultValue: CloseDetailAction? = nil
}

// MARK: - Selection split view

/// A list that opens its panes in the detail column on regular width (up to
/// two side by side) and pushes the focused one on a stack on compact width.
/// Both layouts read one `PaneLayout`, so folding or unfolding keeps the
/// user's place: the stack's path is derived from it, and the detail column
/// shows its slots.
///
/// Callers draw rows that call `layout.openInFocused` when `horizontalSizeClass`
/// is regular and use `NavigationLink(value: PaneRef)` when compact.
struct SelectionSplitView<Sidebar: View, Detail: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @SceneStorage(SidebarVisibility.storageKey)
    private var visibilityRaw = NavigationSplitViewVisibility.all.storageValue
    @Binding var layout: PaneLayout
    /// Owned by the screen, so its list rows can read it as well as the sidebar.
    let openPaneMemory: OpenPaneMemory
    /// Which list the pane picker mirrors.
    let pickerKind: PanePickerKind
    let emptyTitle: LocalizedStringKey
    let sidebar: Sidebar
    let detail: (PaneRef) -> Detail

    init(
        layout: Binding<PaneLayout>,
        memory: OpenPaneMemory,
        pickerKind: PanePickerKind,
        emptyTitle: LocalizedStringKey,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: @escaping (PaneRef) -> Detail
    ) {
        _layout = layout
        openPaneMemory = memory
        self.pickerKind = pickerKind
        self.emptyTitle = emptyTitle
        self.sidebar = sidebar()
        self.detail = detail
    }

    /// The list column's ideal width, used to decide whether two panes still fit beside it.
    private static var listColumnWidth: CGFloat { 360 }

    /// Width of the whole split view, to tell whether the list fits beside two panes.
    @State private var totalWidth: CGFloat = 0
    /// The list is hidden because two panes would be too narrow with it. It is
    /// separate from the stored preference, which returns when this clears.
    @State private var listHiddenForSplit = false

    private var splitNeedsListHidden: Bool {
        totalWidth > 0 && !PaneLayout.listFits(
            totalWidth: totalWidth,
            listWidth: Self.listColumnWidth,
            isSplit: layout.isSplit
        )
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                listHiddenForSplit ? .detailOnly : NavigationSplitViewVisibility(storageValue: visibilityRaw)
            },
            set: { newValue in
                if listHiddenForSplit {
                    // The user brought the list in over the split.
                    guard newValue != .detailOnly else { return }
                    listHiddenForSplit = false
                }
                visibilityRaw = newValue.storageValue
            }
        )
    }

    /// The slot the pane picker is choosing for.
    @State private var pickerSlot: PaneLayout.Slot?

    /// The compact stack's path is the focused pane while it is pushed.
    private var stackPath: Binding<[PaneRef]> {
        Binding(
            get: { layout.compactPath },
            set: { layout.setCompactPath($0, shown: OpenPaneMemory.resolver(openPaneMemory)) }
        )
    }

    /// The other slot's pane while split, for the folded pane switcher's partner tile.
    private var compactPartner: PanePartner? {
        guard layout.isSplit, let partner = layout.ref(in: layout.focused.other) else { return nil }
        return PanePartner(ref: partner, focus: { layout.focus(layout.focused.other) })
    }

    var body: some View {
        content(for: horizontalSizeClass)
            .onChange(of: layout) { _, layout in
                openPaneMemory.retain(Set([layout.left, layout.right].compactMap { $0?.memoryKey }))
            }
            .onChange(of: horizontalSizeClass) { old, new in
                if old == .regular, new == .compact { layout.enteredCompact() }
            }
    }

    @ViewBuilder
    private func content(for sizeClass: UserInterfaceSizeClass?) -> some View {
        if sizeClass == .regular {
            NavigationSplitView(columnVisibility: columnVisibility) {
                sidebar
                    .environment(\.paneMemoryStore, openPaneMemory)
                    .safeAreaInset(edge: .bottom, spacing: 0) { SidebarTabSwitcher() }
                    .navigationSplitViewColumnWidth(min: 320, ideal: Self.listColumnWidth, max: 440)
            } detail: {
                Group {
                    if layout.left != nil {
                        TwoPaneDetail(layout: $layout, memory: openPaneMemory, pick: { pickerSlot = $0 }, content: detail)
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
                .paneDropTarget(layout: $layout, memory: openPaneMemory)
                .revealsSidebarOnEdgeSwipe(columnVisibility)
                .environment(\.showsPaneBackButton, false)
                .environment(\.sidebarToggle, SidebarToggleAction(isListShowing: columnVisibility.wrappedValue != .detailOnly) {
                    withAnimation {
                        columnVisibility.wrappedValue = columnVisibility.wrappedValue == .detailOnly ? .all : .detailOnly
                    }
                })
            }
            .navigationSplitViewStyle(.balanced)
            .sheet(item: $pickerSlot) { slot in
                PanePickerSheet(slot: slot, kind: pickerKind, layout: $layout, memory: openPaneMemory)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size.width, initial: true) { _, width in totalWidth = width }
                }
            }
            .onChange(of: splitNeedsListHidden, initial: true) { _, hidden in listHiddenForSplit = hidden }
        } else {
            NavigationStack(path: stackPath) {
                sidebar
                    .navigationDestination(for: PaneRef.self) { ref in
                        detail(ref)
                            .environment(\.openPaneMemory, OpenPaneSlot(memory: openPaneMemory, selection: ref.memoryKey))
                            .environment(\.closeDetail, CloseDetailAction(
                                layout: $layout, slot: layout.focused, ref: ref, popsCompactStack: true
                            ))
                            .environment(\.panePartner, compactPartner)
                    }
            }
        }
    }
}

/// The sibling pane open in each open item's detail. It is keyed by the
/// item's `PaneRef.memoryKey`, which survives a size-class change that
/// rebuilds the detail and follows the ref when the slots swap. Entries for
/// items that are no longer open are dropped with `retain`.
@Observable
final class OpenPaneMemory {
    private var paneIDs: [String: String] = [:]

    func remember(_ paneID: String, forSelection selection: String) {
        paneIDs[selection] = paneID
    }

    func paneID(forSelection selection: String) -> String? {
        paneIDs[selection]
    }

    /// Keeps only the entries for `selections`.
    func retain(_ selections: Set<String>) {
        paneIDs = paneIDs.filter { selections.contains($0.key) }
    }

    /// Resolves refs to the pane they show, for telling when two rows open the same pane.
    static func resolver(_ memory: OpenPaneMemory?) -> PaneLayout.Resolver {
        { memory?.shownPaneID(of: $0) ?? $0.paneID }
    }

    /// The pane an open ref shows: the sibling remembered for it, else the one it names.
    func shownPaneID(of ref: PaneRef) -> String? {
        paneIDs[ref.memoryKey] ?? ref.paneID
    }

    func forget() {
        paneIDs = [:]
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

/// The whole memory, for the list column, which marks the pane each slot shows.
private struct PaneMemoryStoreKey: EnvironmentKey {
    static let defaultValue: OpenPaneMemory? = nil
}

private struct OpenPaneMemoryKey: EnvironmentKey {
    static let defaultValue: OpenPaneSlot? = nil
}

extension EnvironmentValues {
    var paneMemoryStore: OpenPaneMemory? {
        get { self[PaneMemoryStoreKey.self] }
        set { self[PaneMemoryStoreKey.self] = newValue }
    }

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
