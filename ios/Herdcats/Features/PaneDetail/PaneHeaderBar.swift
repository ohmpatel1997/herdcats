import SwiftUI

/// The title row of a pane in a split. The detail column has a single system
/// navigation bar, so each split pane draws its own header in its content.
/// The focused pane's header carries the focus underline.
struct PaneHeaderBar<Trailing: View>: View {
    let title: String
    let status: AgentStatus
    var subtitle: String?
    var agent: String?
    let slot: PaneLayout.Slot
    let isFocused: Bool
    /// Set on the leftmost pane, whose header holds the list column's button.
    var toggleSidebar: SidebarToggleAction?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let toggleSidebar {
                Button(action: toggleSidebar.callAsFunction) {
                    Image(systemName: "sidebar.left")
                        .font(.jost(16, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Toggle sidebar")
                .accessibilityIdentifier("pane-sidebar-toggle")
            }
            Text(slot == .left ? "L" : "R")
                .font(.jost(10, weight: .bold))
                .foregroundStyle(isFocused ? Theme.onPrimary : Theme.accent)
                .frame(width: 18, height: 18)
                .background(isFocused ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.accent, lineWidth: 1))
                .accessibilityLabel(slot == .left ? "Left pane" : "Right pane")
            StatusNavigationTitle(title: title, status: status, subtitle: subtitle, agent: agent)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 14) { trailing() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            // Sits on the header's bottom edge: accent when focused, a hairline otherwise.
            (isFocused ? Theme.accent : Theme.border)
                .frame(height: isFocused ? 2 : 0.5)
                .allowsHitTesting(false)
        }
        .accessibilityIdentifier("pane-header-\(slot.rawValue)")
    }
}
