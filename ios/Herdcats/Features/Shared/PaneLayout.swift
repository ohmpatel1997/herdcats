import CoreGraphics
import Foundation

/// A pane a split slot can show. `paneID == nil` means the space's default pane.
struct PaneRef: Codable, Hashable {
    let spaceID: String
    let paneID: String?

    /// Keys per-pane memory that must survive a rebuilt detail view.
    var memoryKey: String { "\(spaceID)|\(paneID ?? "")" }
}

/// Which panes the regular-width detail column shows, and which one has the input surface.
struct PaneLayout: Codable, Equatable {
    enum Slot: String, Codable {
        case left, right

        var other: Slot { self == .left ? .right : .left }
    }

    /// The slots a list row is open in, shown as L/R badges. Only while split.
    /// Both slots when two panes of one space are open side by side.
    func badgeSlots(spaceID: String) -> [Slot] {
        guard isSplit else { return [] }
        return [(Slot.left, left), (.right, right)].filter { $0.1?.spaceID == spaceID }.map(\.0)
    }

    /// The slot showing pane `paneID`, judged by the pane each ref ends up
    /// showing (`shown`), not by the ref alone.
    func badgeSlot(paneID: String, shown: Resolver = PaneLayout.namedPane) -> Slot? {
        guard isSplit else { return nil }
        if let left, shown(left) == paneID { return .left }
        if let right, shown(right) == paneID { return .right }
        return nil
    }

    /// The pane a ref shows, when that is known.
    typealias Resolver = (PaneRef) -> String?

    /// The pane a ref names, which is all that is known without the open pane's memory.
    static let namedPane: Resolver = { $0.paneID }

    /// Whether two refs show the same pane: equal, or the same space showing the same pane.
    static func isSamePane(_ a: PaneRef, _ b: PaneRef, shown: Resolver) -> Bool {
        if a == b { return true }
        guard a.spaceID == b.spaceID, let x = shown(a), let y = shown(b) else { return false }
        return x == y
    }

    var left: PaneRef?
    var right: PaneRef?
    var focused: Slot = .left
    var ratio: Double = 0.5
    /// Compact stack: is the focused pane pushed?
    var compactDetailVisible = false

    var isSplit: Bool { left != nil && right != nil }

    var focusedRef: PaneRef? {
        focused == .right ? (right ?? left) : left
    }

    func ref(in slot: Slot) -> PaneRef? {
        slot == .left ? left : right
    }

    mutating func open(_ ref: PaneRef, in slot: Slot, shown: Resolver = PaneLayout.namedPane) {
        // Normalise: the right slot is only used next to a left pane.
        let target: Slot = (slot == .right && left == nil) ? .left : slot
        func isOpen(in slot: Slot) -> Bool {
            self.ref(in: slot).map { PaneLayout.isSamePane($0, ref, shown: shown) } ?? false
        }
        if isOpen(in: target) {
            focused = target
        } else if isOpen(in: target.other) {
            if self.ref(in: target) == nil {
                // Nothing to swap with: the pane is already open, just keep it.
                focused = target.other
            } else {
                swap()
                focused = target
            }
        } else {
            set(ref, in: target)
            focused = target
        }
    }

    /// A list tap: the focused slot when split, otherwise the left slot.
    mutating func openInFocused(_ ref: PaneRef, shown: Resolver = PaneLayout.namedPane) {
        open(ref, in: isSplit ? focused : .left, shown: shown)
    }

    mutating func close(_ slot: Slot) {
        switch slot {
        case .left:
            left = right
            right = nil
        case .right:
            right = nil
        }
        focused = .left
        ratio = 0.5
        if left == nil { compactDetailVisible = false }
    }

    mutating func swap() {
        guard isSplit else { return }
        Swift.swap(&left, &right)
        focused = focused.other
    }

    mutating func fullWidth(_ slot: Slot) {
        guard let kept = ref(in: slot) else { return }
        left = kept
        right = nil
        focused = .left
        ratio = 0.5
    }

    mutating func focus(_ slot: Slot) {
        guard ref(in: slot) != nil else { return }
        focused = slot
    }

    /// Drops refs that no longer exist; a survivor moves to the left slot.
    func pruned(keeping: (PaneRef) -> Bool) -> PaneLayout {
        var result = self
        if let right = result.right, !keeping(right) { result.close(.right) }
        if let left = result.left, !keeping(left) { result.close(.left) }
        return result
    }

    // MARK: Compact stack

    /// The compact `NavigationStack` path: the focused pane while it is pushed.
    var compactPath: [PaneRef] {
        guard compactDetailVisible, let focusedRef else { return [] }
        return [focusedRef]
    }

    /// Applies a path change from the compact stack. Back empties the path
    /// and leaves the slots alone; a push opens the ref in the focused slot.
    mutating func setCompactPath(_ path: [PaneRef], shown: Resolver = PaneLayout.namedPane) {
        guard let ref = path.last else {
            compactDetailVisible = false
            return
        }
        if focusedRef != ref { openInFocused(ref, shown: shown) }
        compactDetailVisible = true
    }

    /// Folding to compact keeps the user in the pane they were reading.
    mutating func enteredCompact() {
        if left != nil { compactDetailVisible = true }
    }

    private mutating func set(_ ref: PaneRef, in slot: Slot) {
        if slot == .left { left = ref } else { right = ref }
    }

    // MARK: Ratio and width

    static func snappedRatio(_ raw: Double) -> Double {
        let clamped = min(max(raw, 0.25), 0.75)
        let snapPoints = [1.0 / 3.0, 0.5, 2.0 / 3.0]
        for point in snapPoints where abs(clamped - point) <= 0.04 {
            return point
        }
        return clamped
    }

    /// One accessibility step along ⅓, ½, ⅔.
    static func steppedRatio(_ ratio: Double, increment: Bool) -> Double {
        let steps = [1.0 / 3.0, 0.5, 2.0 / 3.0]
        let epsilon = 0.0001
        if increment { return steps.first { $0 > ratio + epsilon } ?? steps[2] }
        return steps.last { $0 < ratio - epsilon } ?? steps[0]
    }

    static func listFits(
        totalWidth: CGFloat,
        listWidth: CGFloat,
        isSplit: Bool,
        minPaneWidth: CGFloat = 260,
        dividerWidth: CGFloat = 12
    ) -> Bool {
        guard isSplit else { return true }
        return (totalWidth - listWidth - dividerWidth) / 2 >= minPaneWidth
    }

    // MARK: Scene storage

    var storageValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    init(left: PaneRef? = nil, right: PaneRef? = nil) {
        self.left = left
        self.right = right
    }

    init(storageValue: String) {
        self = (try? JSONDecoder().decode(PaneLayout.self, from: Data(storageValue.utf8))) ?? PaneLayout()
    }
}

extension PaneLayout.Slot: Identifiable {
    var id: String { rawValue }
}
