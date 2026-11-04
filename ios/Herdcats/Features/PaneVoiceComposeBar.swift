import PhotosUI
import SwiftUI
import UIKit

// MARK: - Bar Mode & Modifier Enums

/// Visual and interaction modes of `PaneVoiceComposeBar`.
enum PaneVoiceComposeBarMode: String, CaseIterable, Identifiable, Sendable {
    case live
    case recording
    case compose

    var id: String { rawValue }
}

/// One-shot modifier keys available in Live input.
enum PaneLiveModifier: String, CaseIterable, Identifiable, Hashable, Sendable {
    case ctrl
    case alt
    case shift

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .ctrl: return "Ctrl"
        case .alt: return "Alt"
        case .shift: return "Shift"
        }
    }
}

/// Shared surface for pane input and offline recovery. Input controls keep
/// their plain style so the Live row does not turn into separate pills.
/// Uses the theme surface and border, with optional translucency.
struct PaneInputGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    var backgroundOpacity: Double = 1
    var usesGlassBorder = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle.continuous(cornerRadius)
        let opacity = reduceTransparency ? 1 : backgroundOpacity
        content
            .background {
                if usesGlassBorder && !reduceTransparency {
                    shape.fill(
                        Theme.cardBackground.opacity(opacity)
                            .shadow(.inner(
                                color: .black.opacity(colorScheme == .dark ? 0.16 : 0.035),
                                radius: 10, x: 0, y: 4
                            ))
                    )
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.16 : 0.05),
                            radius: 12, x: 0, y: 6)
                } else {
                    shape.fill(Theme.cardBackground.opacity(opacity))
                }
            }
            .overlay {
                if usesGlassBorder && !reduceTransparency {
                    // A fine outer rim and inset highlight give the edge depth
                    // while preserving the nearly opaque field background.
                    shape.strokeBorder(
                        .black.opacity(colorScheme == .dark ? 0.45 : 0.18),
                        lineWidth: 0.5
                    )
                    .allowsHitTesting(false)
                } else {
                    shape.strokeBorder(Theme.hairline, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if usesGlassBorder && !reduceTransparency {
                    shape.inset(by: 0.75).strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(colorScheme == .dark ? 0.4 : 0.95), location: 0),
                                .init(color: .clear, location: 0.15),
                                .init(color: .clear, location: 0.85),
                                .init(color: .white.opacity(colorScheme == .dark ? 0.35 : 0.85), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
                }
            }
    }
}

/// Gives the arrow button one outcome per touch: a tap sends Up, while a
/// completed long press opens the direction row. The gestures are exclusive,
/// so releasing after a long hold cannot trigger the tap action.
private struct PaneTapOrLongPressStyle: PrimitiveButtonStyle {
    let isEnabled: Bool
    let onLongPress: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.45)
                    .exclusively(before: TapGesture())
                    .onEnded { result in
                        guard isEnabled else { return }
                        switch result {
                        case .first(true): onLongPress()
                        case .second: configuration.trigger()
                        default: break
                        }
                    }
            )
    }
}

// MARK: - Attachment Info

/// Image attachment metadata for the Compose bar.
struct PaneAttachmentInfo: Identifiable, Sendable {
    var id: UUID
    var preview: UIImage
    var remotePath: String?
    var uploadError: String?
    var isUploading: Bool

    init(
        id: UUID = UUID(),
        preview: UIImage,
        remotePath: String? = nil,
        uploadError: String? = nil,
        isUploading: Bool = false
    ) {
        self.id = id
        self.preview = preview
        self.remotePath = remotePath
        self.uploadError = uploadError
        self.isUploading = isUploading
    }
}

// MARK: - PaneVoiceComposeBar

/// A unified SwiftUI input bar for Herdr terminal panes supporting:
/// 1. Default Live mode: fixed rail (Esc, Tab, Up, Ctrl, Alt, Keys, Voice, Keyboard).
/// 2. Recording mode: cancel, a scrolling level waveform, Stop (edit in Compose), and Send.
/// 3. Compose mode: message bubble with editable 1-to-6-row field, external image picker,
///    Voice immediately left of Send, and Send hidden for blank/whitespace text.
struct PaneVoiceComposeBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsModelConfiguration = false
    var modelControl: AgentModelControlState? = nil
    @State private var isKeysDrawerOpen = false
    @State private var isArrowRowOpen = false

    private struct ExtraKey: Identifiable {
        let label: String
        let token: String
        var id: String { token }
    }

    private let arrowKeys = [
        ExtraKey(label: "←", token: "left"), ExtraKey(label: "↑", token: "up"),
        ExtraKey(label: "↓", token: "down"), ExtraKey(label: "→", token: "right")
    ]
    private let navigationKeys = [
        ExtraKey(label: "Home", token: "home"), ExtraKey(label: "End", token: "end"),
        ExtraKey(label: "Pg↑", token: "pageup"), ExtraKey(label: "Pg↓", token: "pagedown")
    ]
    private let editingKeys = [
        ExtraKey(label: "Del", token: "delete"), ExtraKey(label: "Ins", token: "insert"),
        ExtraKey(label: "Bksp", token: "backspace"), ExtraKey(label: "↵", token: "enter")
    ]

    // Mode & Draft
    @Binding var mode: PaneVoiceComposeBarMode
    @Binding var draft: String

    // Focus state (open-only for keyboard icon; dismissal via gestures/hooks)
    @Binding var isLiveKeyboardFocused: Bool
    @FocusState.Binding var isComposeFieldFocused: Bool

    // Live row state & modifier routing to Pi/Cursor's PaneLiveModifierComposer
    /// Gates only the hidden Live keyboard capture, which types text.
    var isLiveEnabled: Bool
    /// Gates the key row and Keys drawer. Keys work before Live typing is
    /// ready, so this can be true while `isLiveEnabled` is false.
    var keysEnabled = true
    /// The line above the key row: why keys are off, or the last key problem.
    var keyNotice: PaneKeyNotice?
    /// Shows the key row above Compose too. False in the Timeline, which keeps
    /// Compose only (and draws its own error text).
    var showsKeyRow = false
    var onRetryKeys: () -> Void = {}
    var onDismissKeyNotice: () -> Void = {}
    @Binding var armedModifiers: Set<PaneLiveModifier>
    var composeFieldIdentifier = "pane-compose-field"
    var composeSendIdentifier = "pane-compose-send-button"
    var onLiveKey: (String) -> Void
    var onLiveModifier: ((PaneLiveModifier) -> Void)?
    var onLiveEvent: (PaneLiveInputEvent) -> Void

    // Voice & Dictation (Pi owns dictation lifecycle and mode transitions)
    var dictation: PaneDictation?
    var isVoiceDraining: Bool
    @Binding var dictationError: String?
    var onStartVoice: () -> Void
    var onFinishVoice: () -> Void
    var onSendVoice: () -> Void
    var onCancelVoice: () -> Void
    var onOpenCompose: () -> Void

    // Photo & Attachment
    var photoItem: Binding<PhotosPickerItem?>?
    @Binding var isPhotoPickerPresented: Bool
    var attachment: PaneAttachmentInfo?
    var onRemoveAttachment: (() -> Void)?

    // Compose actions (visibility = hasDraftText || isSending; disabled = !canSend || isSending)
    var placeholder: String
    var canSend: Bool
    var isSending: Bool
    var onSend: () -> Void

    // Keyboard dismissal hook
    var onDismissKeyboard: (() -> Void)?

    init(
        mode: Binding<PaneVoiceComposeBarMode>,
        draft: Binding<String>,
        isLiveKeyboardFocused: Binding<Bool>,
        isComposeFieldFocused: FocusState<Bool>.Binding,
        isLiveEnabled: Bool = true,
        armedModifiers: Binding<Set<PaneLiveModifier>>,
        onLiveKey: @escaping (String) -> Void,
        onLiveModifier: ((PaneLiveModifier) -> Void)? = nil,
        onLiveEvent: @escaping (PaneLiveInputEvent) -> Void,
        dictation: PaneDictation? = nil,
        isVoiceDraining: Bool = false,
        dictationError: Binding<String?> = .constant(nil),
        onStartVoice: @escaping () -> Void,
        onFinishVoice: @escaping () -> Void,
        onSendVoice: @escaping () -> Void = {},
        onCancelVoice: @escaping () -> Void = {},
        onOpenCompose: @escaping () -> Void,
        photoItem: Binding<PhotosPickerItem?>? = nil,
        isPhotoPickerPresented: Binding<Bool>,
        attachment: PaneAttachmentInfo? = nil,
        onRemoveAttachment: (() -> Void)? = nil,
        placeholder: String = "Message the agent…",
        canSend: Bool = true,
        isSending: Bool = false,
        onSend: @escaping () -> Void,
        onDismissKeyboard: (() -> Void)? = nil
    ) {
#if DEBUG && targetEnvironment(simulator)
        if ScreenshotFixtures.enabled && ScreenshotFixtures.screen == "keys" {
            _isKeysDrawerOpen = State(initialValue: true)
        }
#endif
        self._mode = mode
        self._draft = draft
        self._isLiveKeyboardFocused = isLiveKeyboardFocused
        self._isComposeFieldFocused = isComposeFieldFocused
        self.isLiveEnabled = isLiveEnabled
        self._armedModifiers = armedModifiers
        self.onLiveKey = onLiveKey
        self.onLiveModifier = onLiveModifier
        self.onLiveEvent = onLiveEvent
        self.dictation = dictation
        self.isVoiceDraining = isVoiceDraining
        self._dictationError = dictationError
        self.onStartVoice = onStartVoice
        self.onFinishVoice = onFinishVoice
        self.onSendVoice = onSendVoice
        self.onCancelVoice = onCancelVoice
        self.onOpenCompose = onOpenCompose
        self.photoItem = photoItem
        self._isPhotoPickerPresented = isPhotoPickerPresented
        self.attachment = attachment
        self.onRemoveAttachment = onRemoveAttachment
        self.placeholder = placeholder
        self.canSend = canSend
        self.isSending = isSending
        self.onSend = onSend
        self.onDismissKeyboard = onDismissKeyboard
    }

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .live:
                liveBar
                    .transition(.opacity)
            case .recording:
                recordingBar
                    .transition(.opacity)
            case .compose:
                VStack(spacing: 8) {
                    // Same keys as the Live toolbar, so Esc, Tab and arrows
                    // work without leaving Compose. The draft is untouched.
                    if showsKeyRow { keyStack(trailing: false) }
                    composeBar
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            // Invisible Live keyboard capture surface wired to live events
            PaneLiveKeyboardCaptureView(
                isEnabled: isLiveEnabled && mode == .live,
                isFocused: $isLiveKeyboardFocused,
                onCompositionChanged: nil,
                onEvent: { event in
                    closeLiveMenus()
                    onLiveEvent(event)
                }
            )
        }
        .animation(.snappy(duration: 0.22), value: mode)
        .onChange(of: showsKeyStack) { _, shown in
            // Menus stay open between Live and Compose, which both show the
            // key row; they close when the row goes away (recording, Timeline).
            if !shown { closeLiveMenus() }
        }
        .onChange(of: keysEnabled) { _, enabled in
            if !enabled { closeLiveMenus() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane-voice-compose-bar")
        .sheet(isPresented: $showsModelConfiguration) {
            if let modelControl { AgentModelConfigurationSheet(state: modelControl) }
        }
        .onChange(of: modelControl?.isVisible) { _, visible in
            if visible != true { showsModelConfiguration = false }
        }
    }

    // MARK: - 1. Live Mode Bar

    /// Fixed rail; extra keys expand above it without shifting rail positions.
    private var liveBar: some View {
        keyStack(trailing: true)
    }

    /// True while the key row is on screen: always in Live, and above Compose
    /// outside the Timeline.
    private var showsKeyStack: Bool {
        mode == .live || (mode == .compose && showsKeyRow)
    }

    /// The Keys drawer or arrow row, the notice line, then the rail. Live
    /// adds Voice and Compose at the trailing end; above Compose the rail is
    /// shorter and has keys only.
    private func keyStack(trailing: Bool) -> some View {
        VStack(spacing: 8) {
            if isKeysDrawerOpen { keysDrawer }
            if isArrowRowOpen {
                extraKeyRow(arrowKeys)
                    .frame(maxWidth: 240)
                    .padding(7)
                    .modifier(PaneInputGlassSurface(cornerRadius: DesignSystem.CornerRadius.lg))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            noticeLine
            keyRail(trailing: trailing)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Why keys are off, or the last key or send problem. Tapping it clears a
    /// passing message; Retry appears once automatic retries have slowed down.
    @ViewBuilder
    private var noticeLine: some View {
        if let keyNotice {
            HStack(spacing: 8) {
                Text(keyNotice.text)
                    .font(.jost(.caption))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if keyNotice.offersRetry {
                    Button("Retry", action: onRetryKeys)
                        .buttonStyle(.herdrSecondary(fullWidth: false))
                        .accessibilityIdentifier("pane-key-retry")
                }
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture { onDismissKeyNotice() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pane-key-notice")
        }
    }

    /// Text that explains a disabled key to VoiceOver.
    private var disabledKeyHint: String {
        keysEnabled ? "" : (keyNotice?.text ?? "")
    }

    private func keyRail(trailing: Bool) -> some View {
        let height: CGFloat = trailing ? 42 : 36
        return HStack(spacing: 0) {
            liveKeyButton("Esc", style: .destructive, height: height) {
                sendLiveKey("esc")
            }
            .accessibilityLabel("Send Escape")
            .accessibilityIdentifier("pane-live-key-esc")

            liveKeyButton("Tab", height: height) {
                sendLiveKey("tab")
            }
            .accessibilityLabel("Send Tab")
            .accessibilityIdentifier("pane-live-key-tab")

            arrowButton(height: height)

            liveModifierButton("Ctrl", modifier: .ctrl, height: height)
                .accessibilityLabel("Control modifier")
                .accessibilityIdentifier("pane-live-key-ctrl")

            liveModifierButton("Alt", modifier: .alt, height: height)
                .accessibilityLabel("Alt modifier, Option on Mac")
                .accessibilityIdentifier("pane-live-key-alt")

            liveKeyButton("Keys", isSelected: isKeysDrawerOpen, height: height) {
                isKeysDrawerOpen.toggle()
                isArrowRowOpen = false
            }
            .overlay(alignment: .topTrailing) {
                if armedModifiers.contains(.shift) {
                    Text("⇧")
                        .font(.jost(10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 15, height: 15)
                        .background(Theme.accent.opacity(0.16), in: Circle())
                        .padding(2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Extra keyboard keys")
            .accessibilityValue(armedModifiers.contains(.shift) ? "Shift armed for next key" : (isKeysDrawerOpen ? "Open" : "Closed"))
            .accessibilityAddTraits(isKeysDrawerOpen ? .isSelected : [])
            .accessibilityIdentifier("pane-live-key-extra")

            if trailing {
                liveDivider

                Button {
                    HapticFeedback.impact(.light)
                    onStartVoice()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.jost(16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start voice recording")
                .accessibilityIdentifier("pane-live-voice-button")

                // The keyboard icon opens an editable Compose draft. A tap on pane
                // output is the separate gesture for direct terminal typing.
                Button {
                    HapticFeedback.impact(.light)
                    onOpenCompose()
                } label: {
                    Image(systemName: "keyboard")
                        .font(.jost(16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Compose message")
                .accessibilityIdentifier("pane-live-keyboard-button")
            }
        }
        .frame(height: height)
        // Each key is about 30 pt wide, so keep labels readable at large text
        // sizes; the large content viewer shows a key's label on long press.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .modifier(PaneInputGlassSurface(cornerRadius: DesignSystem.CornerRadius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane-live-bar")
    }

    private func arrowButton(height: CGFloat) -> some View {
        Button {
            HapticFeedback.impact(.light)
            sendLiveKey("up")
        } label: {
            Text("↑")
                .font(.jost(.caption, weight: .semibold).monospaced())
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
        .buttonStyle(
            PaneTapOrLongPressStyle(isEnabled: keysEnabled) {
                HapticFeedback.impact(.light)
                isArrowRowOpen = true
            isKeysDrawerOpen = false
        })
        .disabled(!keysEnabled)
        .opacity(keysEnabled ? 1 : 0.45)
        .accessibilityLabel("Up arrow")
        .accessibilityHint(keysEnabled ? "Long press for all arrow keys" : disabledKeyHint)
        .accessibilityIdentifier("pane-live-key-up")
    }

    private var keysDrawer: some View {
        VStack(spacing: 4) {
            extraKeyRow(arrowKeys)
            extraKeyRow(navigationKeys)
            extraKeyRow(editingKeys)
            HStack(spacing: 4) {
                liveModifierButton("Shift", modifier: .shift)
                    .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Shift modifier")
                    .accessibilityIdentifier("pane-live-key-shift")
                ForEach(0..<3, id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
            .frame(height: 42)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(1...12, id: \.self) { number in
                        extraKeyButton(ExtraKey(label: "F\(number)", token: "f\(number)"))
                            .frame(width: 54)
                    }
                }
            }
            .frame(height: 38)
            .accessibilityLabel("Function keys")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(7)
        .modifier(PaneInputGlassSurface(cornerRadius: DesignSystem.CornerRadius.lg))
        .accessibilityIdentifier("pane-live-keys-drawer")
    }

    private func extraKeyRow(_ keys: [ExtraKey]) -> some View {
        HStack(spacing: 4) {
            ForEach(keys) { key in
                extraKeyButton(key)
            }
        }
    }

    private func extraKeyButton(_ key: ExtraKey) -> some View {
        Button {
            HapticFeedback.impact(.light)
            sendLiveKey(key.token)
        } label: {
            Text(key.label)
                .font(.jost(.caption, weight: .semibold).monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!keysEnabled)
        .accessibilityLabel("Send \(key.label)")
        .accessibilityHint(disabledKeyHint)
        .accessibilityIdentifier("pane-live-extra-key-\(key.token)")
    }

    private func sendLiveKey(_ token: String) {
        closeLiveMenus()
        onLiveKey(token)
    }

    private func closeLiveMenus() {
        isKeysDrawerOpen = false
        isArrowRowOpen = false
    }

    private var liveDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.22))
            .frame(width: 1, height: 24)
            .accessibilityHidden(true)
    }

    private enum LiveKeyStyle {
        case plain
        case destructive
    }

    private func liveKeyButton(
        _ title: String,
        style: LiveKeyStyle = .plain,
        isSelected: Bool = false,
        height: CGFloat = 42,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            Text(title)
                .font(.jost(.caption, weight: .semibold).monospaced())
                .foregroundStyle(isSelected ? Theme.accent : (style == .destructive ? Theme.destructive : Color.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(isSelected ? Theme.accent.opacity(0.16) : Color.clear)
        }
        .buttonStyle(.plain)
        .disabled(!keysEnabled)
        .opacity(keysEnabled ? 1 : 0.45)
        .accessibilityShowsLargeContentViewer()
        .accessibilityHint(disabledKeyHint)
    }

    private func liveModifierButton(
        _ title: String,
        modifier: PaneLiveModifier,
        isEnabled: Bool = true,
        height: CGFloat = 42,
        accessibilityHint: String? = nil
    ) -> some View {
        let isArmed = armedModifiers.contains(modifier)
        let effectiveEnabled = keysEnabled && isEnabled
        return Button {
            HapticFeedback.impact(.light)
            if let onLiveModifier {
                onLiveModifier(modifier)
            } else {
                if isArmed {
                    armedModifiers.remove(modifier)
                } else {
                    armedModifiers.insert(modifier)
                }
            }
        } label: {
            Text(title)
                .font(.jost(.caption, weight: .semibold).monospaced())
                .foregroundStyle(isArmed ? Theme.accent : (isEnabled ? Color.primary : Color.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(isArmed ? Theme.accent.opacity(0.16) : Color.clear)
        }
        .buttonStyle(.plain)
        .disabled(!effectiveEnabled)
        .opacity(effectiveEnabled ? 1 : 0.45)
        .accessibilityShowsLargeContentViewer()
        .accessibilityAddTraits(isArmed ? .isSelected : [])
        .accessibilityValue(isArmed ? "Armed for next key" : "Off")
        .accessibilityHint(keysEnabled ? (accessibilityHint ?? "") : disabledKeyHint)
    }

    // MARK: - 2. Recording Mode Bar

    /// One row: cancel, live waveform, Stop, Send. Stop and Send both drain
    /// final recognition first; Pi owns finalization and the mode transition,
    /// opening Compose after Stop or sending the transcript after Send.
    private var recordingBar: some View {
        HStack(spacing: 10) {
            recordingCircleButton(systemName: "xmark", label: "Cancel recording",
                                  identifier: "pane-recording-cancel-button", action: onCancelVoice)
                .disabled(isVoiceDraining)

            VoiceWaveform(level: dictation?.audioLevel ?? 0, isActive: isRecordingActive)
                .frame(height: 36)
                .accessibilityElement()
                .accessibilityLabel(recordingAccessibilityLabel)
                .accessibilityIdentifier("pane-recording-waveform")

            if isVoiceDraining {
                ProgressView()
                    .frame(width: 34, height: 34)
                    .accessibilityLabel("Finishing dictation")
            } else {
                recordingCircleButton(systemName: "stop.fill", label: "Stop recording",
                                      identifier: "pane-recording-finish-button", action: onFinishVoice)
            }

            Button {
                HapticFeedback.impact(.light)
                onSendVoice()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.jost(34))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isVoiceDraining)
            .opacity(isVoiceDraining ? 0.45 : 1)
            .accessibilityLabel("Send recording")
            .accessibilityIdentifier("pane-recording-send-button")
        }
        .padding(.horizontal, 8)
        .frame(height: 50)
        .modifier(PaneInputGlassSurface(cornerRadius: 25))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane-recording-bar")
    }

    private func recordingCircleButton(systemName: String, label: String, identifier: String,
                                       action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.subtleFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var isRecordingActive: Bool {
        dictation?.isBusy == true && dictation?.isPreparing == false && !isVoiceDraining
    }

    private var recordingAccessibilityLabel: String {
        if isVoiceDraining { return "Finishing dictation" }
        if dictation?.isPreparing == true { return "Starting recording" }
        let text = dictation?.liveText ?? ""
        return text.isEmpty ? "Recording, listening" : "Recording, \(text)"
    }

    // MARK: - 3. Compose Mode Bar

    /// One glass card containing the attachment preview, image picker, and
    /// editable message row. Voice stays immediately left of Send.
    private var composeBar: some View {
        VStack(spacing: 0) {
            if let attachment {
                attachmentChip(attachment)
            }

            // Conversation panes put the field on its own full-width row and
            // the photo, model and voice controls on the row under it. The
            // choice depends only on the surface, so the field keeps its
            // identity (and focus) when the model control appears.
            if modelControl != nil {
                VStack(alignment: .leading, spacing: 0) {
                    messageField
                    HStack(alignment: .center, spacing: 4) {
                        photoPickerButton
                        Spacer(minLength: 0)
                        messageActions
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    photoPickerButton
                    messageBubble
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .modifier(PaneInputGlassSurface(
            cornerRadius: modelControl != nil ? 24 : DesignSystem.CornerRadius.lg,
            backgroundOpacity: modelControl != nil ? 0.98 : 1,
            usesGlassBorder: true
        ))
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    guard isComposeFieldFocused || isLiveKeyboardFocused,
                          value.translation.height > 5,
                          value.translation.height > abs(value.translation.width)
                    else { return }
                    isComposeFieldFocused = false
                    isLiveKeyboardFocused = false
                    onDismissKeyboard?()
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane-compose-bar")
    }

    @ViewBuilder
    private var photoPickerButton: some View {
        if let photoItem {
            Button {
                isPhotoPickerPresented = true
            } label: {
                Image(systemName: "photo")
                    .font(.jost(20))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: photoItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .disabled(isSending)
            .accessibilityLabel("Attach Image")
            .accessibilityIdentifier("pane-compose-attach-button")
        }
    }

    /// Send is visible if the draft has non-whitespace text OR a send is currently in progress.
    /// With the model control showing it stays visible (disabled while blank) so
    /// the action row keeps its shape; otherwise it hides for blank idle drafts.
    private var showsSendButton: Bool {
        isSending || modelControl?.isVisible == true
            || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var messageBubble: some View {
        HStack(alignment: .bottom, spacing: 4) {
            messageField
            messageActions
        }
        .padding(.trailing, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane-compose-bubble")
    }

    private var messageField: some View {
        // Editable 1-to-6-row field
        TextField(placeholder, text: $draft, axis: .vertical)
            // Conversation composers match the timeline's body text size.
            .font(.jost(modelControl != nil ? .body : .subheadline))
            .lineLimit(1...6)
            .focused($isComposeFieldFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(false)
            .background(ComposeTextInputMarker())
            .disabled(isSending)
            .submitLabel(.send)
            .onSubmit {
                guard canSend && !isSending else { return }
                onSend()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .accessibilityLabel("Message text")
            .accessibilityIdentifier(composeFieldIdentifier)
    }

    @ViewBuilder private var messageActions: some View {
        if let modelControl, modelControl.isVisible {
            Button { showsModelConfiguration = true } label: {
                (Text(modelControl.modelName).bold()
                    + Text(modelControl.effortText.map { " " + $0 } ?? ""))
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.jost(.subheadline))
                .foregroundStyle(Color.secondary)
                // Hug the text: the mic glyph sits ~10pt inside its 32pt frame and
                // Send's circle ~4pt inside its 34pt frame, so 3pt here makes the
                // label-to-mic gap match the mic-to-Send gap (measured ~18pt each).
                .padding(.trailing, 3)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(-1)
            .accessibilityLabel(modelControl.accessibilityLabel)
            .accessibilityHint("Configure model and effort")
            .accessibilityIdentifier("timeline-model-control")
        }

        // Voice button inside bubble, immediately left of Send
        Button {
            HapticFeedback.impact(.light)
            onStartVoice()
        } label: {
            Image(systemName: "mic.fill")
                .font(.jost(18))
                .foregroundStyle(Color.secondary)
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSending)
        .accessibilityLabel("Dictate message")
        .accessibilityIdentifier("pane-compose-voice-button")
        .fixedSize()

        // Send button: visible when text is present or when sending; shows spinner during send
        if showsSendButton {
            Button {
                HapticFeedback.impact(.light)
                onSend()
            } label: {
                Group {
                    if isSending {
                        CircularArcSpinner(size: 18)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.jost(26))
                            .foregroundStyle(canSend ? Theme.accent : Color.secondary)
                    }
                }
                .frame(width: 34, height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend || isSending)
            .accessibilityLabel("Send Message")
            .accessibilityIdentifier(composeSendIdentifier)
            .fixedSize()
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }

    private func attachmentChip(_ attachment: PaneAttachmentInfo) -> some View {
        HStack(spacing: 10) {
            Image(uiImage: attachment.preview)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle.continuous(DesignSystem.CornerRadius.sm))

            VStack(alignment: .leading, spacing: 2) {
                if attachment.isUploading {
                    Text("Uploading…")
                        .font(.jost(.caption, weight: .medium))
                    CircularArcSpinner(size: 12)
                } else if let error = attachment.uploadError {
                    Text(error)
                        .font(.jost(.caption))
                        .foregroundStyle(Theme.destructive)
                        .lineLimit(2)
                } else if let path = attachment.remotePath {
                    Text("Image ready")
                        .font(.jost(.caption, weight: .medium))
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.jost(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Image attached")
                        .font(.jost(.caption, weight: .medium))
                }
            }
            Spacer(minLength: 0)
            Button {
                onRemoveAttachment?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.jost(18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove Attached Image")
            .accessibilityIdentifier("pane-attachment-remove-button")
        }
        .padding(8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane-attachment-chip")
    }
}


private struct AgentModelConfigurationSheet: View {
    let state: AgentModelControlState
    @State private var path: [String] = []
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    NavigationLink(value: "Model") {
                        row("Model", value: state.pair.model == nil ? "Unknown" : state.modelName)
                    }
                    .accessibilityIdentifier("model-configuration-model")
                    if !state.efforts.isEmpty {
                        NavigationLink(value: "Effort") {
                            row("Effort", value: state.effortLabel)
                        }
                        .accessibilityIdentifier("model-configuration-effort")
                    }
                }
                .listRowBackground(Theme.cardBackground)
                .disabled(state.isChanging)
                catalogStatus
                if state.persistsAcrossSessions {
                    Section {} footer: {
                        Text("Cursor saves this choice to its own settings, so it also applies to new Cursor sessions on this computer.")
                            .accessibilityIdentifier("model-persists-note")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
            .background(Theme.background)
            .navigationTitle("Configure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The app's spinner sits in front of the title while a change applies.
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        if state.isChanging { CircularArcSpinner(size: 14) }
                        Text("Configure").font(.jost(.headline))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
            }
            .navigationDestination(for: String.self) { destination in
                List {
                    if destination == "Model" {
                        catalogStatus
                        ForEach(state.models) { model in
                            option(model.label, selected: state.selectedModelID == model.id) {
                                Task { await state.change(model: model.id) }
                            }
                        }
                    } else {
                        ForEach(state.efforts) { effort in
                            option(effort.label, selected: state.pair.effort == effort.id) {
                                Task { await state.change(effort: effort.id) }
                            }
                        }
                    }
                }
                .disabled(state.isChanging || state.isLoadingModels)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .navigationTitle(destination)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .font(.jost(.body))
        .tint(Theme.accent)
        .presentationDetents(path.isEmpty && !typeSize.isAccessibilitySize ? [.height(300)] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await state.refresh() }
    }

    @ViewBuilder private var catalogStatus: some View {
        if state.isLoadingModels {
            HStack(spacing: 10) {
                ProgressView().accessibilityLabel("Loading model choices")
                Text("Loading model choices…")
            }
            .listRowBackground(Theme.cardBackground)
        } else if let error = state.errorMessage {
            Text(error)
                .foregroundStyle(Theme.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .listRowBackground(Theme.cardBackground)
                .accessibilityIdentifier("model-choices-error")
            retryCatalog
        } else if state.models.isEmpty {
            Text("Model choices haven't loaded yet.")
                .foregroundStyle(Theme.textMuted)
                .listRowBackground(Theme.cardBackground)
            retryCatalog
        } else if let note = state.catalogInfo?.note {
            Text(note)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .listRowBackground(Theme.cardBackground)
                .accessibilityIdentifier("model-choices-catalog-note")
            retryCatalog
        }
    }
    private var retryCatalog: some View {
        Button("Retry") { Task { await state.refresh() } }
            .disabled(state.isChanging || state.isLoadingModels)
            .listRowBackground(Theme.cardBackground)
            .accessibilityIdentifier("model-choices-retry")
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.text)
            Spacer()
            Text(value).foregroundStyle(Theme.textMuted).multilineTextAlignment(.trailing)
        }
    }
    private func option(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            path = []
            action()
        } label: {
            HStack {
                Text(label).foregroundStyle(Theme.text)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
        }
        .listRowBackground(Theme.cardBackground)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
