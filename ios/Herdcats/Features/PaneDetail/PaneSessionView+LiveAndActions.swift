import AVFoundation
import Foundation
import PhotosUI
import SwiftUI
import UIKit

// MARK: - Pane session live input, input bar, data, and attachment handling

struct LiveSessionTaskKey: Equatable {
    let paneId: String
    let isOffline: Bool
    let isSceneActive: Bool
    let liveInputEnabled: Bool
    let isFocused: Bool
}

struct LiveRefreshTaskKey: Equatable {
    let paneId: String
    let isActive: Bool
    let hasActiveAck: Bool
    let isFocused: Bool
}

extension PaneSessionView {
    // MARK: Live input

    func focusApprovalComposer() {
        if surfaceModel.surface == .voiceRecording {
            finishVoice()
            return
        }
        surfaceModel.requestComposeDraft()
        dismissLiveKeyboard()
        composeFieldFocused = true
    }

    func openCompose() {
        guard surfaceModel.requestComposeDraft() else { return }
        dismissLiveKeyboard()
        composeFieldFocused = true
    }

    /// Restarted per pane (and on reconnect), acquiring a session token
    /// after a successful pane read. The Voice/Compose detour keeps the
    /// session warm — it is the same pane and SSH generation.
    var liveSessionTaskKey: LiveSessionTaskKey {
        LiveSessionTaskKey(
            paneId: pane.paneId,
            isOffline: appModel.isOffline,
            isSceneActive: appModel.isSceneActive,
            liveInputEnabled: liveInputEnabled,
            isFocused: paneIsFocused
        )
    }

    /// Restarted when the scene is foregrounded; cancelled in the
    /// background so rapid reads never run there.
    var liveRefreshTaskKey: LiveRefreshTaskKey {
        LiveRefreshTaskKey(
            paneId: pane.paneId,
            isActive: appModel.isSceneActive,
            hasActiveAck: lastLiveAckAt != nil,
            isFocused: paneIsFocused
        )
    }

    /// Acquires a fresh Live session token and installs it only after a
    /// successful fresh pane read. `beginPaneLiveInput` runs FIRST so its
    /// input-lane barrier waits out any in-flight Compose mutation before
    /// Live can own the keyboard; the read then confirms the pane state
    /// before input is enabled. Used on Live entry and automatic recovery
    /// after an ambiguous delivery failure; discarded events are never
    /// replayed. Re-checks mode, pane identity, connection, and task
    /// lifetime after every await so a stale token can never be installed
    /// for a pane or mode the user has left.
    func resumeLiveInput() async {
        let targetPaneId = pane.paneId
        guard !appModel.isOffline else { return }
        PaneLiveSessionTeardown.retire(&liveSession, connection: appModel.connection)
        resetLiveModifiers()
        do {
            let token = try await appModel.connection.beginPaneLiveInput(paneId: targetPaneId)
            var installed = false
            defer {
                if !installed {
                    Task { await appModel.connection.endPaneLiveInput(token) }
                }
            }
            guard !Task.isCancelled,
                  pane.paneId == targetPaneId,
                  !appModel.isOffline else { return }
            await reload()
            updateSessionParsedOutput()
            guard !Task.isCancelled,
                  pane.paneId == targetPaneId,
                  !appModel.isOffline else { return }
            guard session.errorMessage == nil else {
                if session.errorMessage?.contains("Timed out") == true {
                    liveMetrics.noteTimeout()
                }
                return
            }
            let queue = liveQueue ?? PaneLiveInputQueue(sender: appModel.connection)
            if queue.state == .needsResync {
                queue.noteResynced()
            }
            liveQueue = queue
            liveSession = token
            installed = true
            liveModifierComposer.noteSession(token)
        } catch {
            // Keep later input disabled until the recovery loop acquires a
            // fresh token; never retry an uncertain key.
            PaneLiveSessionTeardown.retire(&liveSession, connection: appModel.connection)
        }
    }

    /// Routes every Live pane mutation through the ordered queue. Controls
    /// are disabled without a session token, and the token's pane is
    /// re-checked so a stale view can never type into another pane. Only the
    /// Live toolbar surface accepts live keys — the recording bar and
    /// Compose bubble never enqueue terminal input.
    func sendLiveEvent(_ event: PaneLiveInputEvent) {
        guard surfaceModel.isLiveKeyboardSurface,
              let queue = liveQueue,
              let session = liveSession,
              session.paneId == pane.paneId,
              !appModel.isOffline else { return }
        guard queue.enqueue(event, session: session) else {
            // Rejection means the queue is full or stopped. Discard the
            // rejected key and backlog; the recovery loop reacquires a
            // fresh session for later input. Nothing is replayed.
            liveMetrics.noteDiscardedEvents(1)
            liveMetrics.noteAbandoned()
            queue.abandonQueuedInput()
            PaneLiveSessionTeardown.retire(&liveSession, connection: appModel.connection)
            lastLiveAckAt = nil
            return
        }
        liveMetrics.noteEnqueued(depth: queue.pendingCount)
    }

    /// Drops queued Live events and the session token on pane switch,
    /// disconnect, or leaving the pane. Accepted-but-undelivered events are
    /// discarded — never replayed into another pane or SSH generation.
    func abandonLiveInput() {
        if let liveQueue {
            liveMetrics.noteAbandoned()
            liveQueue.abandonQueuedInput()
        }
        PaneLiveSessionTeardown.retire(&liveSession, connection: appModel.connection)
        lastLiveAckAt = nil
        lastLiveReadAt = nil
        resetLiveModifiers()
    }

    /// Toolbar / Live keyboard events flow through Cursor's modifier
    /// composer first; only its `.enqueue` outcomes reach the ordered queue.
    /// The visual armed state always mirrors the composer, so a one-shot
    /// modifier (or a multi-char paste that disarms without chord-wrapping)
    /// clears the highlight immediately.
    func applyLiveModifierOutcome(_ outcome: PaneLiveModifierComposer.Outcome) {
        switch outcome {
        case .state:
            break
        case let .enqueue(event):
            sendLiveEvent(event)
        case .unsupportedCommand:
            // ⌘ has no verified agent-TUI mapping; fail closed and say so.
            sessionError = "Command (⌘) chords aren’t supported with this agent yet. Nothing was sent."
        }
        armedLiveModifiers = Set(liveModifierComposer.armed.compactMap { modifier in
            switch modifier {
            case .control: return PaneLiveModifier.ctrl
            case .alt: return .alt
            case .shift: return .shift
            case .command: return nil
            }
        })
    }

    /// Clears the armed modifier and its visual state on pane switch,
    /// disconnect, or any session invalidation.
    func resetLiveModifiers() {
        liveModifierComposer.noteSession(nil)
        armedLiveModifiers = []
    }

    /// Voice entry from the Live toolbar or from inside the Compose bubble.
    /// Both live capture and compose focus yield to the microphone; the
    /// existing pane-scoped draft seeds the transcript so the new speech
    /// merges into (never replaces) unsent text.
    func startVoice() {
        surfaceModel.requestVoiceRecording()
        draftBeforeVoice = draft
        liveInputFocused = false
        composeFieldFocused = false
        let id = UUID()
        voiceSession = id
        let dictationRevision = persistenceRevision
        Task {
            await dictation.start { transcript in
                guard persistence.revision == dictationRevision else { return }
                draft = transcript
            } onError: { message in
                dictationError = message
                // Authorization/microphone failures cycle isBusy true→false
                // fast enough that the onChange transition can coalesce away;
                // the error callback opens the preserved Compose draft itself
                // so the recording surface can never get stuck.
                completeDictationSurface(failed: true)
            } initialText: { draft }
            guard !Task.isCancelled else { return }
            if voiceSession != id {
                // The user tapped the checkmark (or left) while setup was
                // still running. `PaneDictation.cancel()` already ran, but
                // the setup tail can revive the engine after it — force it
                // down and open the preserved draft.
                dictation.cancel()
                completeDictationSurface()
            } else if surfaceModel.surface == .voiceRecording, !dictation.isBusy {
                // Fast-fail that returned without an error callback.
                completeDictationSurface()
            }
        }
    }

    /// The recording bar's single action: stop capture. `finish()` returns
    /// at once (cancelling outright when no recognition request exists yet,
    /// e.g. mid-authorization) while final recognition drains — isBusy stays
    /// true up to ~15s. `completeDictationSurface()` — from the isBusy
    /// transition, the error callback, or the reconciliation above — is the
    /// only path that opens the Compose bubble, so a partial transcript is
    /// never shown or sent.
    /// Send only counts once capture is running: during setup `finish()`
    /// cancels outright, and that idle must not send the prior draft.
    func finishVoice(send: Bool = false) {
        let capturing = dictation.isBusy && !dictation.isPreparing
        guard surfaceModel.requestFinishDictation(sendWhenDone: send && capturing) else { return }
        voiceSession = nil
        dictation.finish()
    }

    /// The recording bar's cancel: drop capture and any speech from this
    /// recording, restore the draft as it was, and return to where Voice began.
    func cancelVoice() {
        guard surfaceModel.cancelVoiceRecording() else { return }
        voiceSession = nil
        dictation.cancel()
        if let draftBeforeVoice { draft = draftBeforeVoice }
        draftBeforeVoice = nil
        if surfaceModel.isComposeSurface { composeFieldFocused = true }
    }

    /// Lifecycle cancellation (audio interruption, backgrounding) mid-recording
    /// or mid-drain. Completes the surface as failed before the isBusy
    /// transition can report it as a successful drain, so a pending Send never
    /// sends an incomplete transcript; the captured text stays in Compose.
    func interruptDictation() {
        let wasRecording = surfaceModel.surface == .voiceRecording
        voiceSession = nil
        dictation.cancel()
        if wasRecording { completeDictationSurface(failed: true) }
    }

    /// Single idempotent funnel off the recording surface onto the Compose
    /// bubble; repeat calls no-op inside the surface state machine. The
    /// final `onText` (full merged transcript, prior draft included) always
    /// precedes `isBusy` clearing on the main actor, so the bubble opens
    /// with a complete transcript — on success, error, timeout, or
    /// interruption alike, preserving the captured draft.
    func completeDictationSurface(failed: Bool = false) {
        let wasRecording = surfaceModel.surface == .voiceRecording
        let sends = surfaceModel.noteDictationIdle(failed: failed)
        guard wasRecording else { return }
        draftBeforeVoice = nil
        if sends, canSend {
            Task { await send() }
        } else if surfaceModel.isComposeSurface {
            composeFieldFocused = true
        }
    }

    /// This slot gained focus while the other had its keyboard up: once that
    /// keyboard has slid down, bring this slot's up, so it reads as a handoff.
    func takeOverKeyboard() async {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled, paneIsFocused,
              PaneFocusPolicy.takesOverKeyboard(
                  handoffAt: keyboardHandoff?.stampedAt,
                  now: ProcessInfo.processInfo.systemUptime
              ) else { return }
        if surfaceModel.isLiveKeyboardSurface, !liveInputEnabled {
            // Live input is still starting. Keep the stamp: `onChange(of: liveInputEnabled)`
            // calls this again once it is ready, while the handoff window lasts.
            return
        }
        keyboardHandoff?.stampedAt = nil
        if surfaceModel.isComposeSurface {
            composeFieldFocused = true
        } else if surfaceModel.isLiveKeyboardSurface {
            liveInputFocused = true
        }
    }

    /// A slot lost focus: put the keyboard away, end the Live session, and
    /// stop dictation the way leaving the pane does. The draft and composer
    /// state stay, and return when the pane is focused again.
    func releaseInputFocus() {
        // The other slot raises its keyboard once this one is down.
        keyboardHandoff?.stampedAt = (composeFieldFocused || liveInputFocused)
            ? ProcessInfo.processInfo.systemUptime : nil
        dismissLiveKeyboard()
        composeFieldFocused = false
        switch PaneFocusPolicy.dictationTeardown(
            isRecording: surfaceModel.surface == .voiceRecording,
            isBusy: dictation.isBusy
        ) {
        case .cancelRecording: cancelVoice()
        case .interrupt: interruptDictation()
        case .none: break
        }
        // Cancelling a recording refocuses Compose; this pane no longer types.
        composeFieldFocused = false
        flushDraftSave()
        abandonLiveInput()
        // Gaining focus decides again whether Done should be marked seen.
        autoMarkedPaneID = nil
    }

    /// Foreground-only rapid pane reads after acknowledged Live input.
    /// Coalesces reads per `PaneLiveRefreshPolicy`, then idles once typing
    /// stops; the five-second lifecycle-aware poll remains the fallback.
    func runLiveForegroundRefresh() async {
        while !Task.isCancelled {
            guard paneIsFocused, appModel.isSceneActive, let ackAt = lastLiveAckAt else { return }
            if ProcessInfo.processInfo.systemUptime - ackAt > PaneLiveRefreshPolicy.activityWindow {
                lastLiveAckAt = nil
                return
            }
            do {
                try await Task.sleep(for: .seconds(PaneLiveRefreshPolicy.tickInterval))
            } catch { return }
            guard appModel.isSceneActive, !session.isReading else { continue }
            let now = ProcessInfo.processInfo.systemUptime
            guard PaneLiveRefreshPolicy.shouldRead(
                now: now,
                lastReadAt: lastLiveReadAt,
                lastAcknowledgedAt: lastLiveAckAt,
                isFocused: paneIsFocused
            ) else { continue }
            lastLiveReadAt = now
            let before = session.output
            await reload()
            updateSessionParsedOutput()
            if session.output != before {
                // Changed read is only a proxy for visible echo.
                liveMetrics.noteOutputChangedRead()
            }
        }
    }

    // MARK: Input bar

    var markAsReadButton: some View {
        Button {
            Task { await markSeen(triggeredByUser: true) }
        } label: {
            Group {
                if isMarkingSeen {
                    CircularArcSpinner(size: 18)
                } else {
                    Image(systemName: "checkmark")
                        .font(.jost(17, weight: .semibold))
                        .foregroundStyle(Theme.onPrimary)
                }
            }
            .frame(width: 44, height: 44)
            .background(AgentStatus.done.color, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isMarkingSeen)
        .accessibilityLabel("Mark as read")
        .accessibilityHint("Clears Done and marks this agent Idle")
        .accessibilityIdentifier("pane-mark-as-read-button")
    }

    func scheduleDraftSave(_ text: String) {
        draftSaveTask?.cancel()
        let key = draftKey
        let revision = persistenceRevision
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            persistence.saveDraft(text, key: key, revision: revision)
        }
    }

    func flushDraftSave() {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        persistence.saveDraft(draft, key: draftKey, revision: persistenceRevision)
    }

    var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var composerPlaceholder: String {
        if let agent = pane.agent { return "Message \(TimelineAgentAvailability.displayName(for: agent))…" }
        return "Type to send to this pane…"
    }

    // MARK: Data

    func reload() async {
        await session.reload(appModel.connection)
    }

    /// Focuses the agent/tab on the Mac so Herdr clears Done → Idle.
    func markSeen(triggeredByUser: Bool) async {
        guard pane.status == .done, !isMarkingSeen else { return }
        isMarkingSeen = true
        defer { isMarkingSeen = false }
        do {
            try await appModel.connection.markAgentSeen(
                paneId: pane.paneId,
                tabId: pane.tabId,
                hasAgent: pane.agent != nil
            )
            locallyClearedDone = true
            if triggeredByUser {
                HapticFeedback.selection()
            }
            onMarkedSeen?()
        } catch {
            if triggeredByUser {
                setSessionError(error)
            }
        }
    }

    func setSessionError(_ error: Error) {
        let message = HerdrConnection.friendlyMessage(for: error)
        if !HerdrConnection.isDisconnectionOrTransitionMessage(message) {
            sessionError = message
        }
    }

    func considerImplicitMarkSeen() async {
        guard PaneFocusPolicy.shouldImplicitlyMarkSeen(
            isImplicitPreference: doneClearPreference == .implicit,
            isDone: pane.status == .done,
            isFocused: paneIsFocused,
            alreadyMarked: autoMarkedPaneID == pane.paneId
        ) else { return }
        autoMarkedPaneID = pane.paneId
        await markSeen(triggeredByUser: false)
    }

    func send() async {
        guard canSend else { return }
        draftSaveTask?.cancel()
        draftSaveTask = nil
        HapticFeedback.impact(.medium)
        let attachedPath = attachment?.remotePath
        // Bind to the pane that owns this session view so a mid-flight switch
        // cannot misroute the upload prompt.
        guard attachedPath == nil || attachment?.paneId == pane.paneId else {
            sessionError = "Image belongs to a different pane — remove it and reattach."
            return
        }
        let text = attachedPath.map {
            HerdrConnection.imagePrompt(remotePath: $0, userMessage: trimmedDraft)
        } ?? trimmedDraft
        guard !text.isEmpty else { return }

        // Cursor runs a leading "/" as its own command; refuse before anything is sent.
        if !appModel.isCoreMode, CursorPromptPolicy.refusesSlashCommand(agent: pane.agent, text: trimmedDraft) {
            sessionError = CursorPromptPolicy.slashMessage
            return
        }
        let sendRevision = persistenceRevision
        let sentDraft = trimmedDraft
        let originalDraft = draft
        do {
            if showsTimeline, let identity = timeline.identity {
                guard let owned=appModel.ownership.transportGeneration else {throw HerdrError.notConnected}
                isTimelineSending=true
                defer {isTimelineSending=false}
                if identity.agent == "pi" {
                    try await timeline.submitPiPrompt(text)
                } else if identity.agent == "cursor" {
                    do { try await timeline.submitCursorPrompt(text) }
                    catch { throw HerdrError.invalidConfiguration(CursorPromptPolicy.message(forCode: (error as? AgentBridgeError)?.code)) }
                } else {
                    try await appModel.connection.submitTimelinePrompt(text:text,identity:identity,owned:owned)
                }
            } else if pane.agent == "cursor", showsTimeline, timeline.canSendFirstCursorPrompt {
                // A brand-new chat: no transcript, so no identity yet. Same bridge guard.
                isTimelineSending=true
                defer {isTimelineSending=false}
                do { try await timeline.submitFirstCursorPrompt(text, paneId: pane.paneId) }
                catch { throw HerdrError.invalidConfiguration(CursorPromptPolicy.message(forCode: (error as? AgentBridgeError)?.code)) }
            } else {
                try await session.send(text:text,connection:appModel.connection)
            }
            sessionError = nil
            guard persistence.revision == sendRevision else { return }
            // Remember what the user typed (not image-path wrappers) for reuse.
            persistence.record(sentDraft, key: historyKey, revision: sendRevision)
            if TimelineComposePolicy.shouldClearDraft(current:draft,sent:originalDraft) { draft = "" }
            clearAttachment()
            shouldPinToBottom = true
            // Return to the preferred idle surface only after a successful send,
            // dismissing the keyboard while keeping Compose visible if enabled.
            surfaceModel.noteSendSucceeded()
            composeFieldFocused = false
            liveInputFocused = false
            // Give the remote terminal a beat to echo the input before re-reading.
            try? await Task.sleep(for: .milliseconds(800))
            await reload()
            updateSessionParsedOutput()
        } catch {
            // Keep draft + attachment so the user can retry; the Compose
            // bubble stays up and the existing error banner reports why.
            setSessionError(error)
        }
    }

    // MARK: Attachment

    func attachPhoto(_ item: PhotosPickerItem) async {
        attachmentUploadTask?.cancel()
        photoItem = nil
        defer { isLoadingPhoto = false }
        do {
            guard let rawData = try await item.loadTransferable(type: Data.self) else {
                sessionError = "Could not load that image."
                return
            }
            let prefersPNG = item.supportedContentTypes.contains { $0.identifier == "public.png" }
            guard let encoded = await Task.detached(priority: .userInitiated, operation: { () -> PaneImageEncoder.EncodedImage? in
                guard let image = UIImage(data: rawData) else { return nil }
                return PaneImageEncoder.encode(image, prefersPNG: prefersPNG)
            }).value else {
                sessionError = "Could not encode that image."
                return
            }
            let pending = PendingPaneAttachment(
                id: UUID(),
                paneId: pane.paneId,
                preview: encoded.preview,
                imageData: encoded.data,
                fileExtension: encoded.fileExtension,
                remotePath: nil,
                uploadError: nil,
                isUploading: true
            )
            attachment = pending
            surfaceModel.notePhotoSelected()
            if !isPhotoPickerPresented {
                composeFieldFocused = true
            }
            attachmentUploadTask = Task {
                await uploadAttachment(pending)
            }
        } catch {
            setSessionError(error)
        }
    }

    func uploadAttachment(_ pending: PendingPaneAttachment) async {
        do {
            let path = try await appModel.connection.uploadAttachment(
                data: pending.imageData,
                fileExtension: pending.fileExtension,
                paneId: pending.paneId
            )
            guard !Task.isCancelled else { return }
            guard attachment?.id == pending.id else { return }
            attachment = pending.with(remotePath: path, uploadError: nil, isUploading: false)
        } catch {
            guard !Task.isCancelled else { return }
            guard attachment?.id == pending.id else { return }
            attachment = pending.with(
                remotePath: nil,
                uploadError: HerdrConnection.friendlyMessage(for: error),
                isUploading: false
            )
        }
    }

    func clearAttachment() {
        attachmentUploadTask?.cancel()
        attachmentUploadTask = nil
        attachment = nil
        photoItem = nil
    }
}
