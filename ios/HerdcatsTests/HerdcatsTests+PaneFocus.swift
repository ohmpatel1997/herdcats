import Testing
@testable import Herdcats

@Suite("Pane focus")
struct PaneFocusTests {
    @Test func unfocusedPaneNeverReadsRapidly() {
        #expect(!PaneLiveRefreshPolicy.shouldRead(now: 1, lastReadAt: nil, lastAcknowledgedAt: 1, isFocused: false))
        #expect(!PaneLiveRefreshPolicy.shouldRead(now: 1.2, lastReadAt: 1, lastAcknowledgedAt: 1, isFocused: false))
        #expect(PaneLiveRefreshPolicy.shouldRead(now: 1.2, lastReadAt: 1, lastAcknowledgedAt: 1, isFocused: true))
    }

    @Test func losingFocusReleasesInputAndGainingItMarksSeen() {
        #expect(PaneFocusPolicy.effects(wasFocused: true, isFocused: false) == .init(releasesInput: true, marksSeen: false))
        #expect(PaneFocusPolicy.effects(wasFocused: false, isFocused: true) == .init(releasesInput: false, marksSeen: true))
    }

    @Test func theKeyboardPassesToTheNewlyFocusedPaneOnlyJustAfterTheHandoff() {
        #expect(PaneFocusPolicy.takesOverKeyboard(handoffAt: 10, now: 10.4))
        #expect(!PaneFocusPolicy.takesOverKeyboard(handoffAt: nil, now: 10.4))
        // A handoff nobody collected goes stale rather than raising a keyboard later.
        #expect(!PaneFocusPolicy.takesOverKeyboard(handoffAt: 10, now: 12))
    }

    @Test func unchangedFocusDoesNothing() {
        #expect(PaneFocusPolicy.effects(wasFocused: true, isFocused: true) == .init(releasesInput: false, marksSeen: false))
        #expect(PaneFocusPolicy.effects(wasFocused: false, isFocused: false) == .init(releasesInput: false, marksSeen: false))
    }

    @Test func recordingIsCancelledAndDrainingIsInterruptedOnFocusLoss() {
        #expect(PaneFocusPolicy.dictationTeardown(isRecording: true, isBusy: true) == .cancelRecording)
        #expect(PaneFocusPolicy.dictationTeardown(isRecording: false, isBusy: true) == .interrupt)
        #expect(PaneFocusPolicy.dictationTeardown(isRecording: false, isBusy: false) == .none)
    }

    @Test func implicitMarkSeenNeedsFocusDoneAndNoEarlierMark() {
        func should(implicit: Bool = true, done: Bool = true, focused: Bool = true, already: Bool = false) -> Bool {
            PaneFocusPolicy.shouldImplicitlyMarkSeen(
                isImplicitPreference: implicit, isDone: done, isFocused: focused, alreadyMarked: already
            )
        }
        #expect(should())
        #expect(!should(implicit: false))
        #expect(!should(done: false))
        #expect(!should(focused: false))
        #expect(!should(already: true))
    }
}
