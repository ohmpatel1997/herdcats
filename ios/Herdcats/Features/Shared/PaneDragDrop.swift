import SwiftUI

// MARK: - Payload

/// A dragged list row. A prefixed string keeps this to the built-in `String`
/// transfer type, so no new UTType or Info.plist entry is needed.
enum PaneDragPayload {
    static let prefix = "herdcats-pane:"

    static func encode(_ ref: PaneRef) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(ref) else { return prefix }
        return prefix + String(decoding: data, as: UTF8.self)
    }

    static func decode(_ string: String) -> PaneRef? {
        guard string.hasPrefix(prefix) else { return nil }
        return try? JSONDecoder().decode(PaneRef.self, from: Data(string.dropFirst(prefix.count).utf8))
    }
}

// MARK: - Drop zones

enum PaneDropZone {
    /// The half of the detail column a drop landed in.
    static func slot(atX x: CGFloat, width: CGFloat) -> PaneLayout.Slot {
        guard width > 0 else { return .left }
        return x < width / 2 ? .left : .right
    }
}

extension PaneLayout {
    /// Opens a dropped row in `half`. With one pane, either half splits: the
    /// dropped pane takes that side and the open pane moves to the other. With
    /// a split, the half's pane is replaced. Returns false for a payload that
    /// isn't a row.
    @discardableResult
    mutating func drop(_ payload: String, onHalf half: Slot, shown: Resolver = PaneLayout.namedPane) -> Bool {
        guard let ref = PaneDragPayload.decode(payload) else { return false }
        if half == .left, !isSplit, let existing = left, !PaneLayout.isSamePane(existing, ref, shown: shown) {
            // Splitting on the left: the open pane moves right, then the drop takes the left.
            right = existing
            left = ref
            focused = .left
        } else {
            open(ref, in: half, shown: shown)
        }
        return true
    }
}

extension PaneRef {
    /// The agent's title when the ref names one, else the space's name.
    func displayTitle(in spaces: [Space]) -> String {
        guard let space = spaces.first(where: { $0.id == spaceID }) else { return spaceID }
        if let paneID, let agent = space.agents.first(where: { $0.paneId == paneID }) {
            return agent.displayTitle
        }
        return space.label
    }
}

// MARK: - Drop target

extension View {
    /// Accepts dragged rows on the detail column, with a zone per half.
    func paneDropTarget(layout: Binding<PaneLayout>, memory: OpenPaneMemory? = nil) -> some View {
        modifier(PaneDropTargetModifier(layout: layout, memory: memory))
    }

    /// A row's drag handle on regular width.
    @ViewBuilder
    func paneDraggable(_ ref: PaneRef, title: String, enabled: Bool) -> some View {
        if enabled {
            draggable(PaneDragPayload.encode(ref)) { PaneDragPreview(title: title) }
        } else {
            self
        }
    }
}

private struct PaneDragPreview: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.jost(14, weight: .semibold))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.cardBackground, in: RoundedRectangle.continuous(DesignSystem.CornerRadius.md))
            .overlay(
                RoundedRectangle.continuous(DesignSystem.CornerRadius.md)
                    .strokeBorder(Theme.accent, lineWidth: 1)
            )
    }
}

private struct PaneDropTargetModifier: ViewModifier {
    @Binding var layout: PaneLayout
    let memory: OpenPaneMemory?
    @State private var isTargeted = false
    @State private var width: CGFloat = 0
    /// When the drag last moved over the column. A drag that is cancelled
    /// (released outside, or off every zone) can leave `isTargeted` stuck, so
    /// the zones also go away once the drag has been quiet for a moment.
    @State private var lastActivity = Date()

    private static let quietTimeout: TimeInterval = 1.2

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onDrop(of: [.plainText], delegate: PaneDropDelegate(
                width: width,
                setTargeted: { isTargeted = $0 },
                noteActivity: { lastActivity = Date() },
                accept: { payload, half in layout.drop(payload, onHalf: half, shown: OpenPaneMemory.resolver(memory)) }
            ))
            .task(id: isTargeted) {
                guard isTargeted else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(300))
                    if Date().timeIntervalSince(lastActivity) > Self.quietTimeout {
                        isTargeted = false
                        return
                    }
                }
            }
            .overlay {
                if isTargeted {
                    HStack(spacing: 12) {
                        zone("Left")
                        zone("Right")
                    }
                    .padding(12)
                    .allowsHitTesting(false)
                }
            }
    }

    private func zone(_ title: LocalizedStringKey) -> some View {
        let shape = RoundedRectangle.continuous(DesignSystem.CornerRadius.lg)
        return Text(title)
            .font(.jost(.subheadline, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.accent.opacity(0.08), in: shape)
            .overlay(shape.strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }
}

private struct PaneDropDelegate: DropDelegate {
    let width: CGFloat
    let setTargeted: (Bool) -> Void
    let noteActivity: () -> Void
    let accept: (String, PaneLayout.Slot) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        noteActivity()
        setTargeted(true)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        noteActivity()
        setTargeted(true)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        setTargeted(false)
    }

    func performDrop(info: DropInfo) -> Bool {
        setTargeted(false)
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let half = PaneDropZone.slot(atX: info.location.x, width: width)
        _ = provider.loadObject(ofClass: String.self) { payload, _ in
            guard let payload else { return }
            DispatchQueue.main.async { _ = accept(payload, half) }
        }
        return true
    }
}
