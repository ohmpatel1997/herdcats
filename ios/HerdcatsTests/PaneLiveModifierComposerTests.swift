import Foundation
import Testing
@testable import Herdcats

@Suite("Pane Live modifier composer")
struct PaneLiveModifierComposerTests {
    @Test func controlToggleArmsAndDisarmsWithoutEnqueue() {
        var composer = PaneLiveModifierComposer()

        #expect(composer.toggle(.control) == .state(armed: [.control]))
        #expect(composer.armed == [.control])

        #expect(composer.toggle(.control) == .state(armed: []))
        #expect(composer.armed.isEmpty)
    }

    @Test func commandToggleFailsClosedWithoutArmingOrInventingToken() {
        var composer = PaneLiveModifierComposer()

        #expect(composer.toggle(.command) == .unsupportedCommand)
        #expect(composer.armed.isEmpty)
        #expect(!PaneLiveModifierComposer.isCommandMappingSupported)
    }

    @Test func controlPlusBaseKeyEmitsOneShotCtrlChordThenDisarms() {
        var composer = PaneLiveModifierComposer()
        _ = composer.toggle(.control)

        #expect(composer.applyBaseKey("c") == .enqueue(.keys(["ctrl+c"])))
        #expect(composer.armed.isEmpty)

        #expect(composer.applyBaseKey("esc") == .enqueue(.keys(["esc"])))
    }

    @Test func stackedModifiersWrapOneKeyInCanonicalOrder() {
        var composer = PaneLiveModifierComposer()
        #expect(composer.toggle(.shift) == .state(armed: [.shift]))
        #expect(composer.toggle(.control) == .state(armed: [.control, .shift]))
        #expect(composer.toggle(.alt) == .state(armed: [.control, .alt, .shift]))

        #expect(composer.applyBaseKey("f1") == .enqueue(.keys(["ctrl+alt+shift+f1"])))
        #expect(composer.armed.isEmpty)
        #expect(composer.applyBaseKey("tab") == .enqueue(.keys(["tab"])))
    }

    @Test func modifierTogglePreservesOtherArmedKeysAndExistingChordPrefixes() {
        var composer = PaneLiveModifierComposer()
        _ = composer.toggle(.control)
        _ = composer.toggle(.alt)
        #expect(composer.toggle(.control) == .state(armed: [.alt]))
        #expect(composer.applyBaseKey("shift+tab") == .enqueue(.keys(["alt+shift+tab"])))

        _ = composer.toggle(.control)
        #expect(composer.apply(.keys(["ctrl+c", "enter"])) == .enqueue(.keys(["ctrl+c", "enter"])))
    }

    @Test func altAndShiftApplyToCommittedKeyboardTextAndPasteDisarms() {
        var composer = PaneLiveModifierComposer()
        _ = composer.toggle(.alt)
        _ = composer.toggle(.shift)
        #expect(composer.apply(.text("A")) == .enqueue(.keys(["alt+shift+a"])))

        _ = composer.toggle(.alt)
        #expect(composer.apply(.text("pasted text")) == .enqueue(.text("pasted text")))
        #expect(composer.armed.isEmpty)
    }

    @Test func printablePunctuationKeepsArmedModifiers() {
        var composer = PaneLiveModifierComposer()

        _ = composer.toggle(.alt)
        #expect(composer.apply(.text(".")) == .enqueue(.keys(["alt+."])))

        _ = composer.toggle(.shift)
        #expect(composer.apply(.text("?")) == .enqueue(.keys(["shift+?"])))

        _ = composer.toggle(.control)
        _ = composer.toggle(.alt)
        #expect(composer.apply(.text("/")) == .enqueue(.keys(["ctrl+alt+/"])))

        _ = composer.toggle(.alt)
        #expect(composer.apply(.text("+")) == .enqueue(.keys(["alt+plus"])))

        _ = composer.toggle(.alt)
        #expect(composer.apply(.text(" ")) == .enqueue(.keys(["alt+space"])))
        #expect(composer.armed.isEmpty)
    }

    @Test func controlWrapsFirstKeyOfMultiKeyEventAndPreservesOrder() {
        var composer = PaneLiveModifierComposer()
        _ = composer.toggle(.control)

        let outcome = composer.apply(.keys(["x", "e", "enter"]))
        #expect(outcome == .enqueue(.keys(["ctrl+x", "e", "enter"])))
        #expect(composer.armed.isEmpty)
    }

    @Test func controlWrapsSingleCharacterTextAsCtrlChord() {
        var composer = PaneLiveModifierComposer()
        _ = composer.toggle(.control)

        #expect(composer.apply(.text("c")) == .enqueue(.keys(["ctrl+c"])))
        #expect(composer.armed.isEmpty)
    }

    @Test func sessionChangeClearsStaleArmedModifier() {
        var composer = PaneLiveModifierComposer()
        let first = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 1)
        )
        let second = PaneLiveInputSession(
            paneId: "w1:p2",
            generation: ConnectionGeneration(rawValue: 1)
        )

        composer.noteSession(first)
        _ = composer.toggle(.control)
        #expect(composer.armed == [.control])

        composer.noteSession(second)
        #expect(composer.armed.isEmpty)
    }

    @Test func generationBumpClearsStaleArmedModifier() {
        var composer = PaneLiveModifierComposer()
        let first = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 1)
        )
        let bumped = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 2)
        )

        composer.noteSession(first)
        _ = composer.toggle(.control)
        composer.noteSession(bumped)
        #expect(composer.armed.isEmpty)
    }

    @Test func sameSessionDoesNotClearArmedModifier() {
        var composer = PaneLiveModifierComposer()
        let session = PaneLiveInputSession(
            paneId: "w1:p1",
            generation: ConnectionGeneration(rawValue: 4)
        )

        composer.noteSession(session)
        _ = composer.toggle(.control)
        composer.noteSession(session)
        #expect(composer.armed == [.control])
    }

    @Test func sameSessionRetryKeepsCtrlArmed() {
        // Ctrl armed while Live typing was still starting (a one-shot token),
        // then Live starts, then a retry installs another Live token: every
        // token is for the same pane and generation, so Ctrl stays armed.
        var composer = PaneLiveModifierComposer()
        let generation = ConnectionGeneration(rawValue: 4)
        composer.noteSession(PaneLiveInputSession(paneId: "w1:p1", generation: generation, kind: .oneShot))
        _ = composer.toggle(.control)

        composer.noteSession(PaneLiveInputSession(paneId: "w1:p1", generation: generation))
        composer.noteSession(PaneLiveInputSession(paneId: "w1:p1", generation: generation))
        #expect(composer.armed == [.control])
        #expect(composer.applyBaseKey("esc") == .enqueue(.keys(["ctrl+esc"])))
    }

    @Test func newGenerationStillClearsCtrl() {
        var composer = PaneLiveModifierComposer()
        composer.noteSession(PaneLiveInputSession(
            paneId: "w1:p1", generation: ConnectionGeneration(rawValue: 4), kind: .oneShot
        ))
        _ = composer.toggle(.control)

        composer.noteSession(PaneLiveInputSession(paneId: "w1:p1", generation: ConnectionGeneration(rawValue: 5)))
        #expect(composer.armed.isEmpty)
    }

    @Test func resetClearsArmedModifier() {
        var composer = PaneLiveModifierComposer()
        _ = composer.toggle(.control)
        composer.reset()
        #expect(composer.armed.isEmpty)
    }

    @Test func orderedKeysEventPreservesTokenOrderAndRejectsCommandMapping() {
        #expect(
            PaneLiveModifierComposer.orderedKeysEvent(["ctrl+x", "ctrl+c"])
                == .success(.keys(["ctrl+x", "ctrl+c"]))
        )
        #expect(
            PaneLiveModifierComposer.orderedKeysEvent(["cmd+c"])
                == .failure(.unsupportedCommandMapping)
        )
        #expect(
            PaneLiveModifierComposer.orderedKeysEvent(["super+a"])
                == .failure(.unsupportedCommandMapping)
        )
        #expect(
            PaneLiveModifierComposer.orderedKeysEvent(["meta+x"])
                == .failure(.unsupportedCommandMapping)
        )
        #expect(
            PaneLiveModifierComposer.orderedKeysEvent(["command+c"])
                == .failure(.unsupportedCommandMapping)
        )
    }

    @Test func applyRejectsCommandPrefixedBaseWhileArmed() {
        var composer = PaneLiveModifierComposer()
        _ = composer.toggle(.control)

        #expect(composer.applyBaseKey("cmd+c") == .unsupportedCommand)
        #expect(composer.armed.isEmpty)
    }

    @Test func applyRejectsUnsupportedCommandTokenWhenUnarmed() {
        var composer = PaneLiveModifierComposer()

        #expect(composer.apply(.keys(["cmd+c"])) == .unsupportedCommand)
        #expect(composer.apply(.keys(["super+a"])) == .unsupportedCommand)
        #expect(composer.apply(.keys(["meta+x"])) == .unsupportedCommand)
        #expect(composer.applyBaseKey("command+c") == .unsupportedCommand)
        #expect(composer.armed.isEmpty)
    }

    @Test func applyRejectsUnsupportedCommandTokenInAnyMultiKeyPosition() {
        var composer = PaneLiveModifierComposer()

        #expect(composer.apply(.keys(["x", "cmd+c"])) == .unsupportedCommand)
        #expect(composer.apply(.keys(["ctrl+x", "e", "super+c"])) == .unsupportedCommand)

        _ = composer.toggle(.control)
        #expect(composer.apply(.keys(["x", "meta+c"])) == .unsupportedCommand)
        #expect(composer.armed.isEmpty)
    }

    @Test func armedControlDisarmsAndForwardsMultiCharacterPasteUnchanged() {
        var composer = PaneLiveModifierComposer()
        _ = composer.toggle(.control)

        let paste = "hello"
        #expect(composer.apply(.text(paste)) == .enqueue(.text(paste)))
        #expect(composer.armed.isEmpty)

        // Later unrelated key must not inherit the cancelled Ctrl arm.
        #expect(composer.applyBaseKey("c") == .enqueue(.keys(["c"])))
        #expect(composer.armed.isEmpty)
    }

    @Test func armedControlDisarmsAndForwardsEmojiAndNonASCIITextUnchanged() {
        var composer = PaneLiveModifierComposer()
        _ = composer.toggle(.control)
        #expect(composer.apply(.text("😀")) == .enqueue(.text("😀")))
        #expect(composer.armed.isEmpty)

        _ = composer.toggle(.control)
        #expect(composer.apply(.text("線")) == .enqueue(.text("線")))
        #expect(composer.armed.isEmpty)

        _ = composer.toggle(.control)
        #expect(composer.apply(.text("é")) == .enqueue(.text("é")))
        #expect(composer.armed.isEmpty)

        // Verified ASCII bases still chord.
        _ = composer.toggle(.control)
        #expect(composer.apply(.text("C")) == .enqueue(.keys(["ctrl+c"])))
        _ = composer.toggle(.control)
        #expect(composer.apply(.text("]")) == .enqueue(.keys(["ctrl+]"])))
        #expect(composer.armed.isEmpty)
    }

    @Test func orderedKeysEventRejectsUnsupportedTokenInAnyPosition() {
        #expect(
            PaneLiveModifierComposer.orderedKeysEvent(["ctrl+x", "cmd+c"])
                == .failure(.unsupportedCommandMapping)
        )
        #expect(
            PaneLiveModifierComposer.orderedKeysEvent(["a", "super+b", "c"])
                == .failure(.unsupportedCommandMapping)
        )
    }
}
