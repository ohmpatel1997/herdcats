import SwiftUI

// MARK: - Open actions (row menus)

/// "Open on Left", "Open on Right" and "Replace Focused Pane" for one row.
struct PaneOpenAction: Identifiable {
    let title: LocalizedStringKey
    let systemImage: String
    let identifier: String
    let perform: () -> Void

    var id: String { identifier }

    static func actions(for ref: PaneRef, layout: Binding<PaneLayout>, memory: OpenPaneMemory? = nil) -> [PaneOpenAction] {
        let shown = OpenPaneMemory.resolver(memory)
        return [
            PaneOpenAction(title: "Open on Left", systemImage: "rectangle.lefthalf.filled", identifier: "open-left") {
                layout.wrappedValue.open(ref, in: .left, shown: shown)
            },
            PaneOpenAction(title: "Open on Right", systemImage: "rectangle.righthalf.filled", identifier: "open-right") {
                layout.wrappedValue.open(ref, in: .right, shown: shown)
            },
            PaneOpenAction(title: "Replace Focused Pane", systemImage: "arrow.left.arrow.right", identifier: "open-replace") {
                layout.wrappedValue.openInFocused(ref, shown: shown)
            },
        ]
    }
}

// MARK: - L / R badge

extension View {
    /// Marks a list row that is open in a slot while split. The focused
    /// slot's badge is filled.
    func paneSlotBadge(_ slots: [PaneLayout.Slot], focused: PaneLayout.Slot) -> some View {
        modifier(PaneSlotBadgeModifier(slots: slots, focused: focused))
    }

    func paneSlotBadge(_ slot: PaneLayout.Slot?, focused: PaneLayout.Slot) -> some View {
        paneSlotBadge(slot.map { [$0] } ?? [], focused: focused)
    }
}

/// The slot a row is open in, for the row to draw left of its timestamp.
struct PaneRowBadge: Equatable {
    let slot: PaneLayout.Slot
    let isFocused: Bool
}

private struct PaneRowBadgeKey: EnvironmentKey {
    static let defaultValue: [PaneRowBadge] = []
}

extension EnvironmentValues {
    var paneRowBadges: [PaneRowBadge] {
        get { self[PaneRowBadgeKey.self] }
        set { self[PaneRowBadgeKey.self] = newValue }
    }
}

/// The small L or R tag. The focused slot's tag is filled.
struct PaneSlotTag: View {
    let badge: PaneRowBadge

    var body: some View {
        Text(badge.slot == .left ? "L" : "R")
            .font(.jost(10, weight: .bold))
            .foregroundStyle(badge.isFocused ? Theme.onPrimary : Theme.accent)
            .frame(width: 16, height: 16)
            .background(badge.isFocused ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.accent, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

private struct PaneSlotBadgeModifier: ViewModifier {
    let slots: [PaneLayout.Slot]
    let focused: PaneLayout.Slot

    func body(content: Content) -> some View {
        if slots.isEmpty {
            content
        } else {
            content
                .environment(\.paneRowBadges, slots.map { PaneRowBadge(slot: $0, isFocused: $0 == focused) })
                .accessibilityValue(slots.count == 2 ? "Open on left and right" : slots[0] == .left ? "Open on left" : "Open on right")
        }
    }
}
