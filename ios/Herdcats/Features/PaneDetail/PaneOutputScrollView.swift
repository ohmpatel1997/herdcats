import SwiftUI
import UIKit

// MARK: - Pane output scroll view

struct PaneOutputScrollView: View, Equatable {
    let output: String
    let selectableText: AttributedString
    let outputRevision: UInt64
    let outputPointSize: CGFloat
    let paneScrollBehavior: PaneScrollBehaviorPreference
    /// True while either keyboard surface (Compose field or hidden Live
    /// capture) holds focus, driving the focus-change and keyboard-frame
    /// repin guards.
    let keyboardFocused: Bool
    let isOffline: Bool
    let isLoading: Bool
    /// True while the floating mark-as-read control is shown; only then
    /// does the output reserve room below its newest line.
    let reservesMarkAsReadSpace: Bool
    let topOverlayInset: CGFloat
    let bottomOverlayInset: CGFloat
    let paneId: String
    @Binding var shouldPinToBottom: Bool
    let onUserScroll: () -> Void
    let onTapOutput: () -> Void
    let onSelectionChange: (Bool) -> Void
    /// Deliberate downward-drag dismissal for the Live keyboard capture
    /// field — a UIKit `UITextField` outside this scroll view that neither
    /// SwiftUI's `.scrollDismissesKeyboard` nor scroll-phase callbacks can
    /// reliably reach. Fired from a content-level simultaneous drag.
    var onDismissKeyboardDrag: (() -> Void)?

    @State private var selectionActive = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var retainedKeyboardSpace: CGFloat = 0
    @State private var retainedDockSpace: CGFloat = 0
    @State private var pendingKeyboardSpace: CGFloat = 0
    @State private var hostWindow = HostingWindow()

    init(
        output: String,
        selectableText: AttributedString,
        outputRevision: UInt64,
        outputPointSize: CGFloat,
        paneScrollBehavior: PaneScrollBehaviorPreference,
        keyboardFocused: Bool,
        isOffline: Bool,
        isLoading: Bool,
        reservesMarkAsReadSpace: Bool,
        topOverlayInset: CGFloat,
        bottomOverlayInset: CGFloat,
        paneId: String,
        shouldPinToBottom: Binding<Bool>,
        onUserScroll: @escaping () -> Void,
        onTapOutput: @escaping () -> Void,
        onSelectionChange: @escaping (Bool) -> Void,
        onDismissKeyboardDrag: (() -> Void)? = nil
    ) {
        self.output = output
        self.selectableText = selectableText
        self.outputRevision = outputRevision
        self.outputPointSize = outputPointSize
        self.paneScrollBehavior = paneScrollBehavior
        self.keyboardFocused = keyboardFocused
        self.isOffline = isOffline
        self.isLoading = isLoading
        self.reservesMarkAsReadSpace = reservesMarkAsReadSpace
        self.topOverlayInset = topOverlayInset
        self.bottomOverlayInset = bottomOverlayInset
        self.paneId = paneId
        self._shouldPinToBottom = shouldPinToBottom
        self.onUserScroll = onUserScroll
        self.onTapOutput = onTapOutput
        self.onSelectionChange = onSelectionChange
        self.onDismissKeyboardDrag = onDismissKeyboardDrag
    }

    private var selectionBottomInset: CGFloat {
        guard selectionActive else { return pendingKeyboardSpace }
        let dockSpace = bottomOverlayInset + (reservesMarkAsReadSpace ? 68 : 0)
        return retainedKeyboardSpace + max(0, retainedDockSpace - dockSpace)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.outputRevision == rhs.outputRevision
            && ((!lhs.output.isEmpty && !rhs.output.isEmpty) || lhs.isLoading == rhs.isLoading)
            && lhs.isOffline == rhs.isOffline
            && lhs.reservesMarkAsReadSpace == rhs.reservesMarkAsReadSpace
            && lhs.topOverlayInset == rhs.topOverlayInset
            && lhs.bottomOverlayInset == rhs.bottomOverlayInset
            && lhs.outputPointSize == rhs.outputPointSize
            && lhs.paneScrollBehavior == rhs.paneScrollBehavior
            && lhs.keyboardFocused == rhs.keyboardFocused
            && lhs.shouldPinToBottom == rhs.shouldPinToBottom
            && lhs.paneId == rhs.paneId
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if output.isEmpty && !isLoading && !isOffline {
                        Text("No output yet")
                            .font(.system(size: outputPointSize, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                            .padding(.bottom, 4)
                    }
                    SelectablePaneOutput(
                        text: selectableText, revision: outputRevision, pointSize: outputPointSize,
                        selectionActive: selectionActive
                    ) { active, safeAreaBottom in
                        if active {
                            let keyboardSpace = max(pendingKeyboardSpace, max(0, keyboardHeight - safeAreaBottom))
                            let dockSpace = bottomOverlayInset + (reservesMarkAsReadSpace ? 68 : 0)
                            retainedKeyboardSpace = selectionActive ? max(retainedKeyboardSpace, keyboardSpace) : keyboardSpace
                            retainedDockSpace = selectionActive ? max(retainedDockSpace, dockSpace) : dockSpace
                        }
                        if selectionActive != active {
                            selectionActive = active
                            onSelectionChange(active)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .padding(.top, topOverlayInset)
                #if DEBUG
                .paneScrollContentProbe()
                #endif
                // The scroll view spans behind the floating dock. Its bottom
                // marker stays above the dock at every keyboard and bar height.
                Color.clear
                    .frame(height: bottomOverlayInset + (reservesMarkAsReadSpace ? 68 : 0) + selectionBottomInset)
                    .id("pane-output-bottom")
            }
            // Content-level simultaneous drag: unlike gestures attached to
            // the ScrollView itself (never delivered beside the native pan
            // in the failing runs), a drag on the content VStack fires
            // reliably during scrolling, including over selectable text.
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    selectionActive = false
                    onSelectionChange(false)
                    onTapOutput()
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard value.translation.height > 20,
                              value.translation.height > abs(value.translation.width) else { return }
                        onDismissKeyboardDrag?()
                    }
            )
            #if DEBUG
            .paneScrollDiagnostics(tag: paneId)
            #endif
            // Dragging down through the output pulls the composer keyboard
            // away with the finger, as in Messages.
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("pane-output-scroll-view")
            // UIKit bridge: SwiftUI's `.scrollDismissesKeyboard` manages only
            // SwiftUI-focus text fields on this OS; force the underlying
            // UIScrollView into native interactive dismissal, which tracks
            // the finger and resigns ANY first responder — including the
            // Live capture UITextField living outside the scroll view.
            .background(ScrollViewKeyboardDismissBridge())
            .modifier(UserScrollObserver(action: onUserScroll))
            // Pin to the newest output when content first arrives and
            // again after the user sends input. During periodic background
            // refreshes the reader is only moved when they opted into
            // `.followOutput`; otherwise their position is held.
            .onChange(of: output) { _, newOutput in
                guard !selectionActive, pendingKeyboardSpace == 0, !newOutput.isEmpty else { return }
                guard shouldPinToBottom || paneScrollBehavior == .followOutput else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("pane-output-bottom", anchor: .bottom)
                }
                shouldPinToBottom = false
            }
            // Either keyboard surface (Compose bubble or the hidden Live
            // capture) shrinks the scroll viewport when it gains focus;
            // re-pin so the newest output stays visible above the keyboard
            // instead of hidden behind it.
            .onChange(of: keyboardFocused) { _, focused in
                if focused {
                    selectionActive = false
                    pendingKeyboardSpace = 0
                    onSelectionChange(false)
                }
                guard focused, !output.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("pane-output-bottom", anchor: .bottom)
                }
            }
            // A growing Compose field moves the dock upward. Keep the newest
            // line in the same place above its new edge.
            .onChange(of: bottomOverlayInset) { _, _ in
                guard !selectionActive, pendingKeyboardSpace == 0, !output.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("pane-output-bottom", anchor: .bottom)
                }
            }
            // Re-pin once the keyboard settles at its final frame while
            // typing (QuickType bar height changes, hardware keyboard
            // attach). Skips hide events so a reader who scrolled up with
            // the keyboard open keeps their position when it dismisses.
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillChangeFrameNotification
                )
            ) { note in
                guard let endFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                keyboardHeight = hostWindow.keyboardOverlap(screenFrame: endFrame)
                guard !selectionActive, pendingKeyboardSpace == 0, keyboardFocused, !output.isEmpty,
                      keyboardHeight > 0
                else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("pane-output-bottom", anchor: .bottom)
                }
            }
        }
        .background(HostingWindowReader(window: hostWindow))
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
            // An empty field can resign before the terminal's touch recognizer
            // fires. Reserve the old keyboard inset before UIKit clamps scroll.
            let begin = note.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect
            let space = max(keyboardHeight, begin.map { hostWindow.keyboardOverlap(screenFrame: $0) } ?? 0)
            pendingKeyboardSpace = max(pendingKeyboardSpace, space)
            if selectionActive { retainedKeyboardSpace = max(retainedKeyboardSpace, space) }
            onSelectionChange(true)
            keyboardHeight = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            if selectionActive {
                retainedKeyboardSpace = max(retainedKeyboardSpace, pendingKeyboardSpace)
            } else {
                onSelectionChange(false)
            }
            pendingKeyboardSpace = 0
        }
        .overlay {
            if output.isEmpty {
                if isOffline {
                    OfflineHerdView()
                        .padding(.top, topOverlayInset)
                        .padding(.bottom, bottomOverlayInset)
                } else if isLoading {
                    LazyCatLoadingView(message: "Reading pane…")
                        .padding(.top, topOverlayInset)
                        .padding(.bottom, bottomOverlayInset)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("pane-content-loading")
                }
            }
        }
    }
}

/// Whether a keyboard frame, in screen coordinates, is docked: a docked
/// keyboard reaches the bottom of the screen, a floating one ends above it.
func isDockedKeyboard(screenFrame: CGRect, screenBounds: CGRect) -> Bool {
    screenFrame.maxY >= screenBounds.maxY - 1
}

/// How far a keyboard covers the bottom of a window. The frame and bounds
/// are in the window's coordinate space; `isDocked` comes from the screen,
/// since a short window's bottom edge says nothing about docking. An undocked
/// or hidden keyboard, or one beside the window, covers nothing; a window
/// shorter than the screen is covered only from the keyboard's top edge down.
func keyboardOverlap(keyboardFrameInWindow frame: CGRect, windowBounds: CGRect, isDocked: Bool) -> CGFloat {
    guard isDocked, frame.maxX > windowBounds.minX, frame.minX < windowBounds.maxX else { return 0 }
    return min(windowBounds.height, max(0, windowBounds.maxY - frame.minY))
}

/// Weak handle to the window hosting a SwiftUI view, so keyboard frames
/// (reported in screen coordinates) can be measured against that window
/// rather than the device screen. Correct for iPad windows, Stage Manager
/// and the iPhone Duo's two screens.
final class HostingWindow {
    weak var window: UIWindow?

    /// Overlap of a screen-space keyboard frame with the hosting window,
    /// or 0 until the view is in a window.
    func keyboardOverlap(screenFrame: CGRect) -> CGFloat {
        guard let window else { return 0 }
        let frame = window.convert(screenFrame, from: window.screen.coordinateSpace)
        return Herdcats.keyboardOverlap(
            keyboardFrameInWindow: frame,
            windowBounds: window.bounds,
            isDocked: isDockedKeyboard(screenFrame: screenFrame, screenBounds: window.screen.bounds)
        )
    }
}

/// Zero-size background that records its window into a `HostingWindow`.
struct HostingWindowReader: UIViewRepresentable {
    let window: HostingWindow

    private final class ProbeView: UIView {
        var onWindow: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindow?(window)
        }
    }

    func makeUIView(context: Context) -> UIView {
        let view = ProbeView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.onWindow = { [weak window] in window?.window = $0 }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// A single, read-only native text surface provides draggable selection handles
/// across lines without introducing a second scrolling region or a keyboard.
struct SelectablePaneOutput: UIViewRepresentable {
    final class Coordinator {
        var lastRevision: UInt64?
        var lastFont: UIFont?

        static func shouldRender(
            lastRevision: UInt64?,
            lastFont: UIFont?,
            revision: UInt64,
            font: UIFont
        ) -> Bool {
            lastRevision != revision || lastFont != font
        }
    }

    let text: AttributedString
    let revision: UInt64
    let pointSize: CGFloat
    let selectionActive: Bool
    var onSelectionFocusChange: (Bool, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PaneOutputTextView {
        let view: PaneOutputTextView
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-hc.long-terminal-selection")
            || ProcessInfo.processInfo.arguments.contains("-hc.terminal-geometry") {
            view = PaneSelectionProbeTextView()
        } else {
            view = PaneOutputTextView()
        }
        #else
        view = PaneOutputTextView()
        #endif
        view.onSelectionFocusChange = onSelectionFocusChange
        view.observeSelectionTouches()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityIdentifier = "pane-output-text"
        return view
    }

    func updateUIView(_ view: PaneOutputTextView, context: Context) {
        view.onSelectionFocusChange = onSelectionFocusChange
        let font = UIFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        guard Coordinator.shouldRender(
            lastRevision: context.coordinator.lastRevision,
            lastFont: context.coordinator.lastFont,
            revision: revision,
            font: font
        ) else { return }
        // Keep the selected snapshot stable until the reader leaves selection.
        guard !selectionActive || view.selectedRange.length == 0 else { return }
        context.coordinator.lastRevision = revision
        context.coordinator.lastFont = font
        let boldFont = UIFont.monospacedSystemFont(ofSize: pointSize, weight: .bold)
        let rendered = NSMutableAttributedString(string: "")
        for run in text.runs {
            let bold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            var attributes: [NSAttributedString.Key: Any] = [
                .font: bold ? boldFont : font,
                .foregroundColor: UIColor(run.foregroundColor ?? Theme.text)
            ]
            if let background = run.backgroundColor {
                attributes[.backgroundColor] = UIColor(background)
            }
            rendered.append(NSAttributedString(
                string: String(text[run.range].characters), attributes: attributes
            ))
        }
        // Assigning attributedText clears UIKit's selection, even for equal text.
        guard !view.attributedText.isEqual(to: rendered) else { return }
        let selection = view.selectedRange
        let preservesSelection = rendered.string.hasPrefix(view.text ?? "")
        view.attributedText = rendered
        // Retain a range only when its text has not shifted or been replaced.
        if preservesSelection, selection.location != NSNotFound,
           NSMaxRange(selection) <= rendered.length {
            view.selectedRange = selection
        }
    }

    static func dismantleUIView(_ uiView: PaneOutputTextView, coordinator: Coordinator) {
        uiView.onSelectionFocusChange = nil
        uiView.stopObservingSelection()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PaneOutputTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

/// Capture the viewport at touch-down, before read-only selection dismisses
/// another field's keyboard and changes the outer scroll view's bottom inset.
class PaneOutputTextView: UITextView, UIGestureRecognizerDelegate {
    var onSelectionFocusChange: ((Bool, CGFloat) -> Void)?
    private weak var anchorScrollView: UIScrollView?
    private weak var anchorTouch: UITouch?
    private var anchorOffset: CGPoint?
    private var keyboardObserver: NSObjectProtocol?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if bounds.contains(point),
           let touch = event?.allTouches?.first(where: { $0.phase == .began }),
           touch !== anchorTouch {
            anchorTouch = touch
            anchorOffset = nil
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    if scroll.adjustedContentInset.bottom > (window?.safeAreaInsets.bottom ?? 0) + 1 {
                        anchorScrollView?.panGestureRecognizer.removeTarget(self, action: #selector(selectionScroll(_:)))
                        anchorScrollView = scroll
                        scroll.panGestureRecognizer.addTarget(self, action: #selector(selectionScroll(_:)))
                        anchorOffset = scroll.contentOffset
                    }
                    break
                }
                ancestor = view.superview
            }
        }
        return super.hitTest(point, with: event)
    }

    func observeSelectionTouches() {
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreSelectionScrollPosition() }
        }

        let observer = UILongPressGestureRecognizer(target: self, action: #selector(selectionTouch(_:)))
        observer.minimumPressDuration = 0
        observer.cancelsTouchesInView = false
        observer.delegate = self
        addGestureRecognizer(observer)
    }

    @objc private func selectionScroll(_ gesture: UIPanGestureRecognizer) {
        // Remember a pan even after it ends, before keyboardDidHide arrives.
        if gesture.state == .began || gesture.state == .changed { anchorOffset = nil }
    }

    func stopObservingSelection() {
        anchorScrollView?.panGestureRecognizer.removeTarget(self, action: #selector(selectionScroll(_:)))
        if let keyboardObserver { NotificationCenter.default.removeObserver(keyboardObserver) }
        keyboardObserver = nil
    }

    private func restoreSelectionScrollPosition() {
        defer { anchorOffset = nil }
        guard let scroll = anchorScrollView, let offset = anchorOffset, !scroll.isDecelerating,
              scroll.panGestureRecognizer.state != .began,
              scroll.panGestureRecognizer.state != .changed else { return }
        // SwiftUI has now reserved the dismissed keyboard's space, so restoring
        // the pre-touch offset cannot be clamped back to the old content end.
        scroll.layoutIfNeeded()
        scroll.setContentOffset(offset, animated: false)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func selectionTouch(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            onSelectionFocusChange?(true, window?.safeAreaInsets.bottom ?? 0)
        } else if gesture.state == .ended || gesture.state == .cancelled {
            // UIKit may finish establishing its selection on touch-up.
            DispatchQueue.main.async { [weak self] in
                guard let self, !isFirstResponder, selectedRange.length == 0 else { return }
                onSelectionFocusChange?(false, 0)
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        onSelectionFocusChange?(true, window?.safeAreaInsets.bottom ?? 0)
        return super.becomeFirstResponder()
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Fixture-only geometry and selection for exact touch-position UI tests.
/// UITextView's accessibility frame can be clipped to its visible viewport.
final class PaneSelectionProbeTextView: PaneOutputTextView {
    override var accessibilityValue: String? {
        get {
            let origin = convert(CGPoint.zero, to: nil)
            let selected = selectedTextRange.flatMap { text(in: $0) } ?? ""
            let bottom = convert(caretRect(for: endOfDocument), to: nil)
            var ancestor = superview
            while ancestor != nil && !(ancestor is UIScrollView) { ancestor = ancestor?.superview }
            let values: [String: Any] = [
                "x": origin.x, "y": origin.y, "width": bounds.width, "height": bounds.height,
                "selected": selected, "text": text ?? "",
                "bottomMinY": bottom.minY, "bottomMaxY": bottom.maxY,
                "scrollOffsetY": (ancestor as? UIScrollView)?.contentOffset.y ?? 0
            ]
            return (try? JSONSerialization.data(withJSONObject: values))
                .flatMap { String(data: $0, encoding: .utf8) }
        }
        set { super.accessibilityValue = newValue }
    }
}
#endif

/// UIKit bridge that forces the terminal output's underlying `UIScrollView`
/// into native interactive keyboard dismissal. SwiftUI's
/// `.scrollDismissesKeyboard` manages only SwiftUI-focus text fields on this
/// OS; UIKit's `keyboardDismissMode` tracks the finger and resigns ANY first
/// responder — including the Live capture `UITextField` living outside the
/// scroll view. Re-asserted on every SwiftUI update in case SwiftUI resets
/// the property it also manages.
struct ScrollViewKeyboardDismissBridge: UIViewRepresentable {
    final class Coordinator {
        weak var scrollView: UIScrollView?

        func apply(to view: UIView) {
            if let scrollView, scrollView.window != nil {
                scrollView.keyboardDismissMode = .interactive
                return
            }
            var current: UIView? = view.superview
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView {
                    self.scrollView = scrollView
                    scrollView.keyboardDismissMode = .interactive
                    return
                }
                current = candidate.superview
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.apply(to: uiView)
    }
}

/// Reports finger-driven scrolling, ignoring programmatic pins to the bottom.
struct UserScrollObserver: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .interacting { action() }
            }
        } else {
            // iOS 17 has no scroll-phase API; a simultaneous drag observes
            // the finger without taking the scroll away from the view.
            content.simultaneousGesture(
                DragGesture(minimumDistance: 20).onChanged { _ in action() }
            )
        }
    }
}
