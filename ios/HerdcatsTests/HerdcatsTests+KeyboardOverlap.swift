import CoreGraphics
import Testing
@testable import Herdcats

@Suite("Keyboard overlap")
struct KeyboardOverlapTests {
    private let phone = CGRect(x: 0, y: 0, width: 393, height: 852)

    @Test func dockedKeyboardCoversItsHeight() {
        let keyboard = CGRect(x: 0, y: 852 - 336, width: 393, height: 336)
        #expect(keyboardOverlap(keyboardFrameInWindow: keyboard, windowBounds: phone, isDocked: true) == 336)
    }

    @Test func hiddenKeyboardCoversNothing() {
        let keyboard = CGRect(x: 0, y: 852, width: 393, height: 336)
        #expect(keyboardOverlap(keyboardFrameInWindow: keyboard, windowBounds: phone, isDocked: true) == 0)
    }

    @Test func floatingKeyboardCoversNothing() {
        let keyboard = CGRect(x: 120, y: 300, width: 320, height: 260)
        #expect(keyboardOverlap(keyboardFrameInWindow: keyboard, windowBounds: phone, isDocked: false) == 0)
    }

    @Test func floatingKeyboardOverAShortWindowCoversNothing() {
        // The floating keyboard ends below the 600pt window's bottom edge,
        // but it is not docked, so it must not count.
        let window = CGRect(x: 0, y: 0, width: 700, height: 600)
        let keyboard = CGRect(x: 120, y: 400, width: 320, height: 260)
        #expect(keyboardOverlap(keyboardFrameInWindow: keyboard, windowBounds: window, isDocked: false) == 0)
    }

    @Test func dockingComesFromTheScreenNotTheWindow() {
        let screen = CGRect(x: 0, y: 0, width: 1024, height: 1366)
        #expect(isDockedKeyboard(screenFrame: CGRect(x: 0, y: 1046, width: 1024, height: 320), screenBounds: screen))
        #expect(!isDockedKeyboard(screenFrame: CGRect(x: 300, y: 700, width: 320, height: 260), screenBounds: screen))
    }

    @Test func overlapNeverExceedsTheWindowHeight() {
        let window = CGRect(x: 0, y: 0, width: 700, height: 300)
        let keyboard = CGRect(x: 0, y: -50, width: 700, height: 420)
        #expect(keyboardOverlap(keyboardFrameInWindow: keyboard, windowBounds: window, isDocked: true) == 300)
    }

    @Test func windowShorterThanScreenIsCoveredFromKeyboardTop() {
        // Stage Manager window 600pt tall; the docked keyboard's top sits at
        // y=400 in window coordinates and runs past the window's bottom.
        let window = CGRect(x: 0, y: 0, width: 700, height: 600)
        let keyboard = CGRect(x: 0, y: 400, width: 700, height: 420)
        #expect(keyboardOverlap(keyboardFrameInWindow: keyboard, windowBounds: window, isDocked: true) == 200)
    }

    @Test func keyboardBelowAShortWindowCoversNothing() {
        let window = CGRect(x: 0, y: 0, width: 700, height: 600)
        let keyboard = CGRect(x: 0, y: 650, width: 700, height: 420)
        #expect(keyboardOverlap(keyboardFrameInWindow: keyboard, windowBounds: window, isDocked: true) == 0)
    }

    @Test func keyboardBesideTheWindowCoversNothing() {
        let window = CGRect(x: 0, y: 0, width: 400, height: 800)
        let keyboard = CGRect(x: 400, y: 500, width: 400, height: 300)
        #expect(keyboardOverlap(keyboardFrameInWindow: keyboard, windowBounds: window, isDocked: true) == 0)
    }
}
