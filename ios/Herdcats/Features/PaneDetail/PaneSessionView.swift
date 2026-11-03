import AVFoundation
import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit

struct PaneSessionView: View {
    let pane: PaneEntry
    let connectionScope: ConnectionIdentity
    var topOutputInset: CGFloat = 0
    var showLiveDiagnostics: Binding<Bool>? = nil
    /// Called after Herdr successfully marks a Done agent as seen.
    var onMarkedSeen: (() -> Void)?
    /// Called when the user scrolls the output or focuses the composer.
    var onOutputInteraction: (() -> Void)?

    @Environment(AppModel.self) var appModel
    @Environment(SpacesModel.self) var spacesModel: SpacesModel?
    @Environment(\.colorScheme) var colorScheme
    /// False for the output-only slot of a split: no input surface, no Live
    /// session, no rapid reads, no implicit mark-as-seen.
    @Environment(\.paneIsFocused) var paneIsFocused
    @Environment(\.paneKeyboardHandoff) var keyboardHandoff
    @State var session: PaneSessionState
    /// Pane text is held in view state and synchronously persisted through the
    /// privacy policy so a cleared session cannot restore stale values.
    @State var draft: String
    @State var persistence = PaneContentPersistence.shared
    @State var persistenceRevision: UInt64
    let draftKey: String
    let historyKey: String
    @Binding var showsTimeline: Bool
    let bridgeUpgrade: TimelineBridgeUpgrade
    @State var timeline = AgentTimelineState()
    @State var isTimelineSending = false
    @State var shouldPinToBottom = true
    @State var bottomDockHeight: CGFloat = 58
    @State var outputTextSelectionActive = false
    @State var draftSaveTask: Task<Void, Never>?
    /// True while the Compose bubble's text field holds keyboard focus.
    @FocusState var composeFieldFocused: Bool
    @Environment(\.scenePhase) var scenePhase
    @State var dictation = PaneDictation()
    @State var dictationError: String?
    @State var photoItem: PhotosPickerItem?
    @State var isPhotoPickerPresented = false
    @State var isLoadingPhoto = false
    @State var attachment: PendingPaneAttachment?
    @State var attachmentUploadTask: Task<Void, Never>?
    @State var sessionError: String?
    @State var isMarkingSeen = false
    /// Optimistic hide of the mark-as-read control until the next peer refresh.
    @State var locallyClearedDone = false
    /// Pane ID for which implicit Done→Idle already ran this visit.
    @State var autoMarkedPaneID: String?

    /// Which input surface is shown: Live toolbar (default), Voice
    /// recording bar, or Compose bubble. Owned here; `PaneVoiceComposeBar`
    /// renders the visuals for the current surface.
    @State var surfaceModel = PaneInputSurfaceModel()
    /// Cursor-owned modifier/chord model: Ctrl arms for the next key and
    /// emits `ctrl+<token>` through the ordered Live queue; ⌘ fails closed.
    @State var liveModifierComposer = PaneLiveModifierComposer()
    /// Visual armed-modifier state for `PaneVoiceComposeBar`, driven strictly
    /// by `liveModifierComposer` outcomes so the bar never synthesizes keys.
    @State var armedLiveModifiers: Set<PaneLiveModifier> = []
    /// Live delivery queue and its generation-scoped session token, created
    /// lazily when Live input first becomes active for this pane.
    @State var liveQueue: PaneLiveInputQueue?
    @State var liveSession: PaneLiveInputSession?
    /// Monotonic seconds (`systemUptime`) of the last Live acknowledgement
    /// and last rapid read, driving `PaneLiveRefreshPolicy`.
    @State var lastLiveAckAt: TimeInterval?
    @State var lastLiveReadAt: TimeInterval?
    /// True while the Live keyboard capture holds focus (software keyboard
    /// up, or a hardware keyboard is actively typing).
    @State var liveInputFocused = false
    /// Identifies the in-flight dictation setup so a checkmark tapped during
    /// async authorization/microphone setup cannot leave a revived engine
    /// recording silently after the surface has moved on.
    @State var voiceSession: UUID?
    /// The draft as it was when recording began, restored by cancel.
    @State var draftBeforeVoice: String?
    /// Aggregate local diagnostics. Recording no-ops unless a deliberate
    /// test run enables it from the DEBUG-only navigation button.
    let liveMetrics = PaneLiveInputMetrics.shared

    @AppStorage(PaneTextSizePreference.storageKey)
    private var paneTextSizeRaw = PaneTextSizePreference.default.rawValue
    @AppStorage(PaneScrollBehaviorPreference.storageKey)
    private var paneScrollBehaviorRaw = PaneScrollBehaviorPreference.default.rawValue
    @AppStorage(PaneComposePreference.storageKey)
    private var showComposeByDefault = PaneComposePreference.default
    @AppStorage(DoneClearPreference.storageKey)
    private var doneClearRaw = DoneClearPreference.default.rawValue

    var output: String { session.output }
    var isLoading: Bool { session.isLoading }
    var errorMessage: String? { session.errorMessage }
    var isSending: Bool { session.isSending || isTimelineSending }

    // Observable queue projections so SwiftUI tracks Live delivery state.
    private var liveQueueState: PaneLiveInputQueueState? { liveQueue?.state }
    private var livePendingCount: Int { liveQueue?.pendingCount ?? 0 }
    private var isLiveDraining: Bool { liveQueue?.isDraining ?? false }
    /// Monotonic count of delivered Live events; each increment is one
    /// per-event acknowledgement that drives rapid-refresh pacing and metrics.
    private var liveAcknowledgedCount: UInt64 { liveQueue?.acknowledgedCount ?? 0 }

    private var outputPointSize: CGFloat {
        (PaneTextSizePreference(rawValue: paneTextSizeRaw) ?? .default).pointSize
    }

    private var paneScrollBehavior: PaneScrollBehaviorPreference {
        PaneScrollBehaviorPreference(rawValue: paneScrollBehaviorRaw) ?? .default
    }

    var doneClearPreference: DoneClearPreference {
        DoneClearPreference(rawValue: doneClearRaw) ?? .default
    }

    private var showsMarkAsReadButton: Bool {
        doneClearPreference == .explicit
            && pane.status == .done
            && !locallyClearedDone
    }

    init(
        pane: PaneEntry,
        connectionScope: ConnectionIdentity,
        showsTimeline: Binding<Bool>,
        bridgeUpgrade: TimelineBridgeUpgrade = TimelineBridgeUpgrade(),
        topOutputInset: CGFloat = 0,
        showLiveDiagnostics: Binding<Bool>? = nil,
        onMarkedSeen: (() -> Void)? = nil,
        onOutputInteraction: (() -> Void)? = nil
    ) {
        self.pane = pane
        self.connectionScope = connectionScope
        self._showsTimeline = showsTimeline
        self.bridgeUpgrade = bridgeUpgrade
        self.topOutputInset = topOutputInset
        self.showLiveDiagnostics = showLiveDiagnostics
        self.onMarkedSeen = onMarkedSeen
        self.onOutputInteraction = onOutputInteraction
        let state = PaneSessionState(pane: pane, connectionScope: connectionScope)
        _session = State(initialValue: state)
        let policy = PaneContentPersistence.shared
        let draftKey = state.draftKey
        _draft = State(initialValue: policy.loadDraft(key: draftKey))
#if DEBUG && targetEnvironment(simulator)
        if ScreenshotFixtures.enabled {
            if ScreenshotFixtures.screen == "timeline-offline-transition" {
                _draft = State(initialValue: String(repeating: "A multiline draft stays editable while offline. ", count: 10))
            }
            if ProcessInfo.processInfo.arguments.contains("-hc.long-terminal-selection") {
                _draft = State(initialValue: ProcessInfo.processInfo.arguments.contains("-hc.selection-draft")
                    ? "Selection draft" : "")
            }
            let surface = PaneInputSurfaceModel()
            if ["compose", "timeline-helper-missing", "timeline-unavailable", "timeline-pending", "timeline-disconnected", "optional-upgrade-menu", "turn-interrupted", "timeline-codex-no-session"].contains(ScreenshotFixtures.screen) {
                surface.requestComposeDraft()
                _draft = State(initialValue: "Looks good. Add a test for reconnecting, then open a pull request.")
            } else if ScreenshotFixtures.screen == "voice" {
                surface.requestVoiceRecording()
                let recording = PaneDictation()
                recording.showScreenshotRecording()
                _dictation = State(initialValue: recording)
            }
            _surfaceModel = State(initialValue: surface)
        }
#endif
        _persistence = State(initialValue: policy)
        _persistenceRevision = State(initialValue: policy.revision)
        self.draftKey = draftKey
        self.historyKey = state.historyKey
    }

    private var terminalPalette: TerminalPalette {
        TerminalPalette(palette: AppThemePreferences.shared.dark, dark: true)
    }

    func updateSessionParsedOutput() {
        session.updateParsedOutput(palette: terminalPalette)
    }

    /// External send gate — the Compose bubble only *hides* Send for a blank
    /// draft; actual enablement still honors upload, dictation, and
    /// in-flight-send guards owned here. Per the accepted rule, non-whitespace
    /// text is required before either the Send button or Return can send — an
    /// attached image alone is never sent (Return would otherwise leak an
    /// image-only message past the hidden button).
    var canSend: Bool {
        !trimmedDraft.isEmpty && appModel.isSceneActive
            && (!appModel.isCoreMode || appModel.isReadyForTerminalInput)
            && (!showsTimeline || (timeline.phase != .suspended && timeline.matchesLivePane(paneId: pane.paneId, agent: pane.agent, connection: AgentTimelineConnectionState(phase: appModel.phase, generation: appModel.ownership.transportGeneration))))
            && !isSending && !isTimelineSending
            && (!showsTimeline || !timeline.modelControl.isChanging)
            && (!showsTimeline || pane.agent != "pi" || timeline.canSubmitPiPrompt)
            && (!showsTimeline || TimelineComposePolicy.canCompose(identity:timeline.identity,paneId:pane.paneId,status:timeline.agentStatus,connected:AgentTimelineConnectionState(phase:appModel.phase,generation:appModel.ownership.transportGeneration).isReady))
            && !dictation.isBusy
            && !(attachment?.isUploading ?? false)
    }

    private func handleSend() {
        Task { await send() }
    }

    private func handlePaneChange(_ newPane: PaneEntry) {
        session.updatePane(newPane)
        updateSessionParsedOutput()
        if newPane.status != .done {
            locallyClearedDone = false
        }
        Task { await considerImplicitMarkSeen() }
    }

    @ViewBuilder
    private var outputScrollView: some View {
        PaneOutputScrollView(
            output: output,
            selectableText: session.selectableOutput,
            outputRevision: session.outputRevision,
            outputPointSize: outputPointSize,
            paneScrollBehavior: paneScrollBehavior,
            // Combined keyboard-focus signal: the Compose bubble's field or
            // the hidden Live capture field — either keyboard shrinking the
            // viewport must repin the newest output above it.
            keyboardFocused: composeFieldFocused || liveInputFocused,
            isOffline: appModel.isOffline,
            isLoading: isLoading,
            reservesMarkAsReadSpace: showsMarkAsReadButton,
            topOverlayInset: topOutputInset,
            bottomOverlayInset: bottomDockHeight,
            paneId: pane.paneId,
            shouldPinToBottom: $shouldPinToBottom,
            onUserScroll: {
                if liveInputFocused {
                    // The hidden Live capture field is a UIKit `UITextField`
                    // outside the scroll view, so `.interactively` and drag
                    // gestures cannot reliably reach it. Any deliberate
                    // output scroll while the Live keyboard is up drops it:
                    // the user is shifting attention to the TUI, and Keyboard
                    // re-opens with one tap. Belt-and-braces: clear the focus
                    // binding and force UIKit first-responder resignation.
                    // Compose keeps its own dismissal paths untouched.
                    liveInputFocused = false
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
                onOutputInteraction?()
            },
            onTapOutput: {
                guard surfaceModel.surface != .voiceRecording, liveInputEnabled else { return }
                // Output is the direct terminal input surface. Preserve the
                // pane-scoped Compose draft while moving keyboard focus.
                let wasComposing = surfaceModel.isComposeSurface
                surfaceModel.collapseToLiveToolbar()
                composeFieldFocused = false
                if wasComposing {
                    // Let Compose relinquish first responder after its field
                    // leaves the hierarchy, then focus the Live capture.
                    DispatchQueue.main.async {
                        guard surfaceModel.isLiveKeyboardSurface, liveInputEnabled else { return }
                        liveInputFocused = true
                    }
                } else {
                    liveInputFocused = true
                }
            },
            onSelectionChange: { selecting in
                if outputTextSelectionActive != selecting { outputTextSelectionActive = selecting }
                if selecting {
                    // UIKit selection owns focus; keep SwiftUI from restoring
                    // the old input field during the keyboard handoff.
                    if composeFieldFocused { composeFieldFocused = false }
                    if liveInputFocused { liveInputFocused = false }
                }
            },
            onDismissKeyboardDrag: dismissLiveKeyboard
        )
        .equatable()
        // Keep the mark-as-read control above the floating input dock.
        .overlay(alignment: .bottomTrailing) {
            if showsMarkAsReadButton {
                markAsReadButton
                    .padding(.trailing, 20)
                    .padding(.bottom, bottomDockHeight + 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsMarkAsReadButton)
    }

    /// A small, slow indicator at the bottom right while Live input is queued
    /// or recovering. Diagnostics appear only when opened from the DEBUG
    /// navigation button.
    @ViewBuilder
    private var liveStatusRow: some View {
        if surfaceModel.isLiveKeyboardSurface {
            VStack(spacing: 4) {
                if !appModel.isOffline && (!liveInputEnabled || livePendingCount > 0 || isLiveDraining) {
                    HStack {
                        Spacer(minLength: 0)
                        CircularArcSpinner(size: 15)
                            .accessibilityLabel("Live input working")
                            .accessibilityIdentifier("pane-live-activity-spinner")
                    }
                    .padding(.trailing, 18)
                }
                #if DEBUG
                if showLiveDiagnostics?.wrappedValue == true {
                    liveDiagnosticsFooter
                }
                #endif
            }
            .padding(.top, 6)
        }
    }

    #if DEBUG
    /// Local diagnostics are enabled by the DEBUG navigation button; nothing
    /// is persisted or uploaded, and hiding this bar clears its samples.
    private var liveDiagnosticsFooter: some View {
        let metrics = PaneLiveInputMetrics.shared
        return VStack(spacing: 4) {
            Text(PaneLiveDiagnostics.summaryLine(for: metrics.summary))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("pane-live-metrics-summary")
            if let error = sessionError ?? errorMessage {
                Text(error)
                    .font(.jost(.caption2))
                    .foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
    }
    #endif

    /// The Live toolbar with Keys drawer / recording bar / Compose bubble.
    /// Visuals are `PaneVoiceComposeBar` (Agy-owned); every transition and
    /// remote effect is owned by this view through `PaneInputSurfaceModel`,
    /// `PaneLiveModifierComposer`, and the ordered Live queue.
    private var voiceComposeBar: some View {
        var bar = PaneVoiceComposeBar(
            mode: Binding(
                get: {
                    showsTimeline
                        ? (surfaceModel.isLiveKeyboardSurface ? .compose : surfaceModel.surface.barMode)
                        : surfaceModel.surface.barMode
                },
                set: { _ in }
            ),
            draft: $draft,
            isLiveKeyboardFocused: $liveInputFocused,
            isComposeFieldFocused: $composeFieldFocused,
            isLiveEnabled: liveInputEnabled,
            armedModifiers: $armedLiveModifiers,
            onLiveKey: { token in
                applyLiveModifierOutcome(liveModifierComposer.applyBaseKey(token))
            },
            onLiveModifier: { modifier in
                applyLiveModifierOutcome(
                    liveModifierComposer.toggle(
                        {
                            switch modifier {
                            case .ctrl: return .control
                            case .alt: return .alt
                            case .shift: return .shift
                            }
                        }())
                )
            },
            onLiveEvent: { event in
                if appModel.isCoreMode, case let .text(text) = event,
                   HerdrConnection.coreTypedKeys(text) == nil {
                    sessionError = HerdrConnection.coreUntypeableMessage
                    // Disarm like the composer does for text it can't wrap, so a
                    // later key never inherits a stale Ctrl/Alt arm.
                    liveModifierComposer.reset()
                    applyLiveModifierOutcome(.state(armed: []))
                    return
                }
                applyLiveModifierOutcome(liveModifierComposer.apply(event))
            },
            dictation: dictation,
            isVoiceDraining: surfaceModel.isDrainingDictation,
            dictationError: $dictationError,
            onStartVoice: startVoice,
            onFinishVoice: { finishVoice() },
            onSendVoice: { finishVoice(send: true) },
            onCancelVoice: cancelVoice,
            onOpenCompose: openCompose,
            photoItem: $photoItem,
            isPhotoPickerPresented: $isPhotoPickerPresented,
            attachment: attachment.map(PaneAttachmentInfo.init),
            onRemoveAttachment: { clearAttachment() },
            placeholder: composerPlaceholder,
            canSend: canSend,
            isSending: isSending,
            onSend: handleSend
        )
        bar.modelControl = showsTimeline && timeline.matchesLivePane(paneId: pane.paneId, agent: pane.agent, connection: AgentTimelineConnectionState(phase: appModel.phase, generation: appModel.ownership.transportGeneration)) ? timeline.modelControl : nil
        bar.composeFieldIdentifier = showsTimeline ? "timeline-compose-field" : "pane-compose-field"
        bar.composeSendIdentifier = showsTimeline ? "timeline-compose-send" : "pane-compose-send-button"
        return bar
    }

    var liveInputEnabled: Bool {
        liveSession != nil && liveQueueState != .needsResync && !appModel.isOffline
    }

    /// Hard dismissal for the hidden Live capture field: clear the focus
    /// binding (so the bar's Keyboard icon unlights) and force UIKit-level
    /// first-responder resignation in one action.
    func dismissLiveKeyboard() {
        guard liveInputFocused else { return }
        liveInputFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private var outputWithInputDock: some View {
        VStack(spacing: 0) {
            Group {
                if showsTimeline {
                    AgentTimelineView(
                        paneId: pane.paneId, agent: pane.agent, connection: appModel.connection, timeline: timeline,
                        bridgeUpgrade: bridgeUpgrade,
                        topOverlayInset: topOutputInset, bottomOverlayInset: bottomDockHeight,
                        onOutputInteraction: { onOutputInteraction?() }, setupTarget: connectionScope,
                        onUseTerminal: {
                            UserDefaults.standard.set(true, forKey: TimelineSetupPreference.key(scope: connectionScope))
                            showsTimeline = false
                        },
                        onSetupComplete: {
                            let key = TimelineSetupPreference.key(scope: connectionScope)
                            if UserDefaults.standard.bool(forKey: key) { UserDefaults.standard.removeObject(forKey: key) }
                        },
                        onFocusComposer: focusApprovalComposer
                    )
                } else {
                    outputScrollView
                        .environment(\.colorScheme, .dark)
                        .background(
                            Color(uiColor: UIColor(hex: terminalPalette.background)),
                            ignoresSafeAreaEdges: .bottom
                        )
                }
            }
            // Extend only the output surface behind the keyboard and home
            // indicator; the navigation bar keeps the app theme.
            .background {
                (showsTimeline ? Theme.background : Color(uiColor: UIColor(hex: terminalPalette.background)))
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .transformPreference(ConnectionRecoveryLayoutKey.self) { layout in
            // Preserve the empty state's own Retry marker while supplying the
            // measured usable area for recovery over retained output.
            layout.topInset = max(layout.topInset, topOutputInset)
            layout.bottomInset = max(layout.bottomInset, bottomDockHeight)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if paneIsFocused {
                    if showsTimeline {
                        if let sessionError {
                            Text(sessionError).font(.jost(.caption)).foregroundStyle(Theme.destructive)
                                .padding(.horizontal, 16)
                        }
                    } else {
                        liveStatusRow
                    }
                    voiceComposeBar
                        .environment(\.colorScheme, showsTimeline ? colorScheme : .dark)
                }
            }
            // Track the rendered dock directly, including multiline drafts,
            // attachments and keyboard-driven layout changes. Scroll controls
            // and transcript padding must use the same current height.
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                // An unfocused slot shows no dock, so its height is really zero.
                if height > 0 || !paneIsFocused { bottomDockHeight = height }
            }
        }
        .onChange(of: showsTimeline) { _, _ in
            dismissLiveKeyboard(); composeFieldFocused = false; dictation.cancel()
            surfaceModel.resetToDefaultSurface()
            updateSessionParsedOutput()
        }
    }

    private var outputWithLiveTasks: some View {
        outputWithInputDock
            .task(id: pane.id) {
                locallyClearedDone = false
                autoMarkedPaneID = nil
                await reload()
                updateSessionParsedOutput()
                await considerImplicitMarkSeen()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    let auto = spacesModel?.autoRefreshEnabled ?? true
                    guard
                        PaneRefreshPolicy.shouldAutoPoll(
                            autoRefreshEnabled: auto,
                            isSceneActive: appModel.isSceneActive
                        )
                    else { continue }
                    await reload()
                    updateSessionParsedOutput()
                }
            }
        .task(id: liveSessionTaskKey) {
            var retryDelay = 2.0
            while !Task.isCancelled && paneIsFocused && !appModel.isOffline && appModel.isSceneActive {
                guard !liveInputEnabled else { return }
                if liveSession == nil || liveQueueState == .needsResync {
                    await resumeLiveInput()
                    retryDelay = liveInputEnabled ? 2 : min(retryDelay * 2, 10)
                }
                do {
                    try await Task.sleep(for: .seconds(liveInputEnabled ? 1 : retryDelay))
                } catch { return }
            }
        }
        .task(id: liveRefreshTaskKey) {
            await runLiveForegroundRefresh()
        }
        .onChange(of: appModel.isOffline) { _, offline in
            // A disconnect invalidates the Live session generation; queued
            // input is discarded rather than replayed after reconnect, and a
            // half-armed modifier must not leak across SSH generations.
            guard offline else { return }
            abandonLiveInput()
            resetLiveModifiers()
        }
        .onChange(of: liveAcknowledgedCount) { oldCount, newCount in
            // Per-event acknowledgement: refresh pacing restarts and metrics
            // consume one FIFO enqueue timestamp per delivered event — even
            // while later events are still in flight. SwiftUI may coalesce
            // several increments into one observation, so apply the old→new
            // delta once per newly acknowledged event; a replaced queue
            // (count resets to 0) yields a negative delta and is skipped —
            // its timestamps were already abandoned.
            let delta = PaneLiveInputMetrics.acknowledgedDelta(from: oldCount, to: newCount)
            guard delta > 0 else { return }
            for _ in 0..<delta {
                liveMetrics.noteAcknowledged()
            }
            lastLiveAckAt = ProcessInfo.processInfo.systemUptime
        }
        .onChange(of: isLiveDraining) { _, draining in
            // An ambiguous send is discarded. The session task acquires a
            // fresh token for future input without replaying uncertain keys.
            guard !draining, liveQueue != nil, liveQueueState == .needsResync else { return }
            liveMetrics.noteDeliveryFailure()
            lastLiveAckAt = nil
            PaneLiveSessionTeardown.retire(&liveSession, connection: appModel.connection)
            resetLiveModifiers()
        }
    }

    private var outputWithLifecycle: some View {
        outputWithLiveTasks
        .task(id: showComposeByDefault) {
            surfaceModel.setComposeVisibleByDefault(showComposeByDefault)
            guard showComposeByDefault else { return }
            // Let SwiftUI mount the Compose field before requesting focus.
            await Task.yield()
            guard !Task.isCancelled, surfaceModel.isComposeSurface else { return }
            dismissLiveKeyboard()
            composeFieldFocused = true
        }
        .onChange(of: showComposeByDefault) { _, visible in
            surfaceModel.setComposeVisibleByDefault(visible)
            if !visible, trimmedDraft.isEmpty, attachment == nil {
                surfaceModel.collapseToLiveToolbar()
            }
        }
        .onDisappear {
            flushDraftSave()
            dictation.cancel()
            attachmentUploadTask?.cancel()
            abandonLiveInput()
            surfaceModel.resetToDefaultSurface()
            resetLiveModifiers()
        }
        .onChange(of: pane) { _, newPane in
            handlePaneChange(newPane)
        }
        .onChange(of: paneIsFocused) { wasFocused, isFocused in
            let effects = PaneFocusPolicy.effects(wasFocused: wasFocused, isFocused: isFocused)
            if effects.releasesInput { releaseInputFocus() }
            if effects.marksSeen {
                Task { await considerImplicitMarkSeen() }
                Task { await takeOverKeyboard() }
            }
        }
        .onChange(of: liveInputEnabled) { _, enabled in
            // A slot that gained focus before its Live session was ready finishes the keyboard handoff now.
            if enabled, paneIsFocused { Task { await takeOverKeyboard() } }
        }
        // Only the focused pane makes room for the software keyboard.
        .ignoresSafeArea(.keyboard, edges: paneIsFocused ? [] : .bottom)
        .onChange(of: session.output) { _, _ in
            updateSessionParsedOutput()
        }
        .onChange(of: terminalPalette) { _, _ in
            updateSessionParsedOutput()
        }
        .onChange(of: doneClearRaw) { _, _ in
            Task { await considerImplicitMarkSeen() }
        }
        .onChange(of: draft) { _, newDraft in
            scheduleDraftSave(newDraft)
        }
        .onChange(of: persistence.revision) { _, revision in
            draftSaveTask?.cancel()
            draftSaveTask = nil
            persistenceRevision = revision
            draft = ""
        }
        .onChange(of: pane.id) { _, _ in
            // A different pane must never receive queued Live events, a
            // stale session token, an armed modifier, or another pane's
            // input surface.
            abandonLiveInput()
            surfaceModel.resetToDefaultSurface()
            resetLiveModifiers()
        }
        .onChange(of: scenePhase) { _, phase in
            appModel.isSceneActive = phase == .active
            if phase == .background {
                abandonLiveInput()
                flushDraftSave()
                interruptDictation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            interruptDictation()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            isLoadingPhoto = true
            surfaceModel.notePhotoSelected()
            Task { await attachPhoto(item) }
        }
        .onChange(of: isPhotoPickerPresented) { _, isPresented in
            if !isPresented && attachment != nil {
                composeFieldFocused = true
            }
        }
        .alert("Dictation unavailable", isPresented: Binding<Bool>(
            get: { dictationError != nil },
            set: { if !$0 { dictationError = nil } }
        )) {
            Button("OK", role: .cancel) { dictationError = nil }
        } message: {
            Text(dictationError ?? "")
        }
    }

    var body: some View {
        outputWithLifecycle
        .animation(.easeInOut(duration: 0.2), value: surfaceModel.surface)
        .onChange(of: composeFieldFocused) { _, focused in
            if focused {
                onOutputInteraction?()
            } else {
                collapseEmptyComposerIfUnfocused()
            }
        }
        .onChange(of: outputTextSelectionActive) { _, selecting in
            if !selecting { collapseEmptyComposerIfUnfocused() }
        }
        .onChange(of: liveInputFocused) { _, focused in
            if focused {
                onOutputInteraction?()
            }
        }
        .onChange(of: dictation.isBusy) { _, busy in
            guard !busy else { return }
            completeDictationSurface()
        }
    }

    private func collapseEmptyComposerIfUnfocused() {
        guard !composeFieldFocused, !outputTextSelectionActive,
              surfaceModel.isComposeSurface, !showComposeByDefault,
              trimmedDraft.isEmpty, !isPhotoPickerPresented,
              !isLoadingPhoto, attachment == nil else { return }
        surfaceModel.collapseToLiveToolbar()
    }

}
