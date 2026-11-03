import Foundation
import Testing
import UIKit
@testable import Herdcats

/// Live keyboard translation, IME deduplication, delivery metrics, and
/// rapid-read pacing for the pane's Live input path. (The Compose/Live
/// segmented preference was removed with the accepted Live toolbar; its
/// successor surface state machine lives in `PaneInputSurfaceTests`.)
@Suite("Live input translation and pacing")
struct PaneLiveInputTests {
    @Test func committedKeyboardEventsKeepTerminalSemantics() {
        #expect(PaneLiveInputTranslator.translateInsertedText("a") == [.text("a")])
        #expect(PaneLiveInputTranslator.translatePaste("a\nb") == [.text("a\nb")])
        #expect(PaneLiveInputTranslator.translateInsertedText("\u{200B}").isEmpty)
        #expect(PaneLiveInputTranslator.translateBackspace(hasMarkedText: false) == [.keys(["backspace"])])
        #expect(PaneLiveInputTranslator.translateBackspace(hasMarkedText: true).isEmpty)
        #expect(PaneLiveInputTranslator.translateReturn() == [.keys(["enter"])])
        #expect(PaneLiveInputTranslator.translateReturn(hasMarkedText: true).isEmpty)
        #expect(PaneLiveInputTranslator.translateReturn(didJustConfirmComposition: true).isEmpty)
        #expect(PaneLiveInputTranslator.translateKeyCommand(input: "\t", modifierFlags: .shift) == [.keys(["shift+tab"])])
        #expect(PaneLiveInputTranslator.translateKeyCommand(input: UIKeyCommand.inputLeftArrow) == [.keys(["left"])])
    }

    @Test func duplicateIMECommitCallbackIsSuppressed() {
        #expect(PaneLiveInputTranslator.shouldSuppressDuplicateInsert(
            insertedText: "漢", pendingDeduplication: "漢"
        ))
        #expect(!PaneLiveInputTranslator.shouldSuppressDuplicateInsert(
            insertedText: "字", pendingDeduplication: "漢"
        ))
    }

    @Test @MainActor func textFieldEditingFallbackSendsAndClearsCommittedText() {
        let field = LiveInputTextField()
        var events: [PaneLiveInputEvent] = []
        field.onEvent = { events.append($0) }
        field.text = LiveInputTextField.sentinel + "ab"
        field.sendActions(for: .editingChanged)

        #expect(events == [.text("ab")])
        #expect(field.text == LiveInputTextField.sentinel)
    }

    @Test @MainActor func diagnosticsAreOptInAndClearedWhenDisabled() {
        let metrics = PaneLiveInputMetrics(clock: { 100 })
        metrics.noteEnqueued(depth: 3)
        metrics.noteAcknowledged()
        #expect(metrics.summary.isEmpty)

        metrics.setEnabled(true)
        metrics.noteEnqueued(depth: 3)
        metrics.noteAcknowledged()
        metrics.noteOutputChangedRead()
        #expect(metrics.summary.enqueueToAck.sampleCount == 1)
        #expect(metrics.summary.ackToOutputChange.sampleCount == 1)
        #expect(metrics.summary.maxQueueDepth == 3)
        metrics.setEnabled(false)
        #expect(metrics.summary.isEmpty)
    }

    @Test @MainActor func coalescedAcknowledgementsIgnoreCounterReset() {
        #expect(PaneLiveInputMetrics.acknowledgedDelta(from: 4, to: 7) == 3)
        #expect(PaneLiveInputMetrics.acknowledgedDelta(from: 7, to: 0) == 0)
        #expect(PaneLiveInputMetrics.acknowledgedDelta(from: 0, to: 300) == 256)
    }

    @Test func rapidReadsCoalesceAndStopAfterTyping() {
        #expect(PaneLiveRefreshPolicy.shouldRead(now: 1, lastReadAt: nil, lastAcknowledgedAt: 1, isFocused: true))
        #expect(!PaneLiveRefreshPolicy.shouldRead(now: 1.1, lastReadAt: 1, lastAcknowledgedAt: 1, isFocused: true))
        #expect(PaneLiveRefreshPolicy.shouldRead(now: 1.2, lastReadAt: 1, lastAcknowledgedAt: 1, isFocused: true))
        #expect(!PaneLiveRefreshPolicy.shouldRead(now: 2, lastReadAt: 1, lastAcknowledgedAt: 1, isFocused: true))
    }
}
