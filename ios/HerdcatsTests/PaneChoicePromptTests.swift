import Foundation
import Testing
@testable import Herdcats

// Screens copied from compatibility/phase1 and phase2 fixtures, the bridge's
// live Claude notice and Agy approval, and `CodexQuestionInputTests`. The long
// wrapped path in the Claude permission dialog is shortened.

private let claudePermission = """
 Bash command
 Tip: auto mode handles these prompts for you — choose "switch to auto mode" below
 Write probe text to probe.txt
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 echo herdcats-probe > probe.txt
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and always allow access to /fixture/work/xxxxxxxxxxxxxxxx
      xxxxxxxxxxxxxxxx from this project
   3. Yes, and switch to auto mode · auto mode handles these prompts for you
   4. No

 Esc to cancel · Tab to amend
"""

private let claudeLiveNotice = """
❯ Use the Bash tool to run exactly: python3 -c "open('probe2.txt','w').write('two')"

  Writing "two" to probe2.txt
  ⎿  $ python3 -c "open('probe2.txt','w').write('two')"

────────────────────────────────────────────────────────────
 Bash command
 Tip: auto mode handles these prompts for you — choose "switch to auto mode" below
 Write "two" to probe2.txt
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 python3 -c "open('probe2.txt','w').write('two')"
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 This command requires approval

 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don’t ask again for: python3 *
   3. Yes, and switch to auto mode · auto mode handles these prompts for you
   4. No

 Esc to cancel · Tab to amend
"""

private let codexApproval = """
  Would you like to run the following command?
  Environment: local
  Reason: Allow the exact requested command to write probe2.txt?
  $ echo herdcats-probe > probe2.txt
› 1. Yes, proceed (y)
  2. Yes, and don't ask again for commands that start with `echo herdcats-probe > probe2.txt` (p)
  3. No, and tell Codex what to do differently (esc)
  Press enter to confirm or esc to cancel
"""

private let claudeQuestion = """
←  ☐ Color  ☐ Toppings  ✔ Submit  →

Pick a color

❯ 1. Red
     Choose red
  2. Blue
     Choose blue
  3. Type something.
────────────────────────────────────────────────────────────
  4. Chat about this

Enter to select · Tab/Arrow keys to navigate · Esc to cancel
"""

private let claudeMulti = """
←  ☒ Size  ☒ Toppings  ✔ Submit  →

Pick toppings

❯ 1. [✔] Cheese
         Add cheese
  2. [ ] Olives
         Add olives
  3. [✔] Basil
         Add basil
  4. [ ] Type something
     Submit
────────────────────────────────────────────────────────────
  5. Chat about this

Enter to select · Tab/Arrow keys to navigate · Esc to cancel
"""

private let codexQuestionList = """
  Question 1/1 (1 unanswered)
  Which color?

    1. Red                Choose Red.
    2. Blue               Choose Blue.
  › 3. None of the above  Optionally, add details in notes (tab).

  tab to add notes | enter to submit answer | esc to interrupt
"""

private let codexPicker = """
• Queued follow-up inputs
  Pick a color
  › 1. Red
    2. Blue
    3. Other
  enter submit   ⌃] skip   ⇧→ main prompt
"""

private let agyApproval = """
Command
Requesting permission for:
   printf SAFE

Run this command?
> 1. Yes, run command
  2. Yes, and always allow in this conversation for commands that start with 'printf'
  3. Yes, and always allow for commands that start with 'printf' (Persist to settings.json)
  4. No, cancel

↑/↓ Navigate · tab Amend · ctrl+g edit/expand command
"""

private func claudeEdit(file: String) -> String {
    """
    ────────────────────────────────────────────────────────────
     Edit file
     \(file)
    ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
       12 -    let retries = 3
       12 +    let retries = 5
    ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
     Do you want to make this edit?
     ❯ 1. Yes
       2. Yes, allow all edits during this session (shift+tab)
       3. No

     Esc to cancel · Tab to amend
    """
}

private func detect(_ text: String) -> PaneChoicePrompt? {
    PaneChoicePrompt.detect(rows: PaneChoicePrompt.rows(from: text))
}

private func route(queueState: PaneLiveInputQueueState?, isAnswering: Bool = false) -> PaneKeyRoute {
    PaneKeyRoute.resolve(
        isOffline: false, isReadyForTerminalInput: true, hasGeneration: true,
        isSceneActive: true, isFocused: true, isRecording: false,
        queueState: queueState, liveInputEnabled: queueState == .ready,
        hasFreshRead: true, isAnswering: isAnswering
    )
}

@Suite("Pane choice prompts")
struct PaneChoicePromptTests {
    // MARK: Detection and keys

    @Test func claudePermissionDetectsOptionsAndContext() throws {
        let prompt = try #require(detect(claudePermission))
        #expect(prompt.options.map(\.number) == [1, 2, 3, 4])
        #expect(prompt.highlighted == 1)
        #expect(prompt.options[1].detail == "xxxxxxxxxxxxxxxx from this project")
        #expect(prompt.hints == ["Esc to cancel · Tab to amend"])
        // The command between the dashed rules is part of what is answered.
        #expect(prompt.context.first == "Bash command")
        #expect(prompt.context.contains("echo herdcats-probe > probe.txt"))
        #expect(prompt.context.last == "Do you want to proceed?")
    }

    @Test func claudePermissionSendsTheDigit() throws {
        let prompt = try #require(detect(claudePermission))
        #expect(prompt.isAnswerable(agent: "claude"))
        #expect(prompt.options.map { prompt.answerKey(option: $0.number, agent: "claude") } == ["1", "2", "3", "4"])
        #expect(PaneChoicePrompt.plan(expected: prompt, current: prompt, option: 4, agent: "claude") == "4")
    }

    @Test func codexApprovalUsesLetterShortcutsAndCodexTitleContext() throws {
        let prompt = try #require(detect(codexApproval))
        #expect(prompt.context.first == "Would you like to run the following command?")
        #expect(prompt.context.last == "$ echo herdcats-probe > probe2.txt")
        #expect(prompt.options.map(\.shortcut) == ["y", "p", "esc"])
        #expect(prompt.options[0].label == "Yes, proceed")
        #expect(prompt.options.map { prompt.answerKey(option: $0.number, agent: "codex") } == ["y", "p", "esc"])
    }

    @Test func claudeQuestionCrossesTheRuleAndKeepsDescriptions() throws {
        let prompt = try #require(detect(claudeQuestion))
        #expect(prompt.options.map(\.number) == [1, 2, 3, 4])
        #expect(prompt.options.map(\.detail) == ["Choose red", "Choose blue", nil, nil])
        #expect(prompt.options[3].label == "Chat about this")
        #expect(prompt.context == ["←  ☐ Color  ☐ Toppings  ✔ Submit  →", "Pick a color"])
    }

    @Test func freeTextRowHasNoButtonAndShowsNote() throws {
        let prompt = try #require(detect(claudeQuestion))
        let match = prompt.options.first { $0.isFreeText }
        let freeText = try #require(match)
        #expect(freeText.number == 3)
        #expect(freeText.label == "Type something.")
        #expect(prompt.answerKey(option: 3, agent: "claude") == nil)
        #expect(prompt.answerKey(option: 1, agent: "claude") == "1")
        #expect(prompt.isAnswerable(agent: "claude"))
    }

    @Test func codexQuestionListSendsTheDigit() throws {
        let prompt = try #require(detect(codexQuestionList))
        #expect(prompt.highlighted == 3)
        #expect(prompt.answerKey(option: 2, agent: "codex") == "2")
        #expect(prompt.answerKey(option: 3, agent: "codex") == "3")
        // The last question ("enter to submit all") may need Enter after the
        // digit, so it is left to the arrows-and-Enter follow-up.
        let last = try #require(detect(codexQuestionList.replacingOccurrences(
            of: "enter to submit answer", with: "enter to submit all")))
        #expect(!last.isAnswerable(agent: "codex"))
    }

    @Test func multiSelectDigitTogglesAndReportsCheckedState() throws {
        let prompt = try #require(detect(claudeMulti))
        #expect(prompt.options.map(\.checked) == [true, false, true, false, nil])
        #expect(prompt.options.map(\.label) == ["Cheese", "Olives", "Basil", "Type something", "Chat about this"])
        #expect(prompt.answerKey(option: 2, agent: "claude") == "2")
        #expect(prompt.answerKey(option: 4, agent: "claude") == nil)
        // A toggle changes the identity, so the card shows the new state.
        let toggled = try #require(detect(claudeMulti.replacingOccurrences(of: "2. [ ] Olives", with: "2. [✔] Olives")))
        #expect(toggled.options[1].checked == true)
        #expect(toggled.identity != prompt.identity)
    }

    // MARK: Not answered in v1

    @Test func codexPickerShowsNoCardInV1() throws {
        let prompt = try #require(detect(codexPicker))
        #expect(!prompt.isAnswerable(agent: "codex"))
    }

    @Test func agyAndUnknownAgentsShowNoCard() throws {
        let agy = try #require(detect(agyApproval))
        for agent in ["agy", "antigravity_cli", "gemini", "cursor", nil] as [String?] {
            #expect(!agy.isAnswerable(agent: agent))
        }
        let claude = try #require(detect(claudePermission))
        #expect(!claude.isAnswerable(agent: nil))
        #expect(!claude.isAnswerable(agent: "pi"))
        let codex = try #require(detect(codexApproval))
        #expect(!codex.isAnswerable(agent: "cursor"))
    }

    // MARK: Identity

    @Test func sameOptionsDifferentCommandIsChanged() throws {
        let expected = try #require(detect(claudePermission))
        let current = try #require(detect(claudePermission.replacingOccurrences(
            of: "echo herdcats-probe > probe.txt", with: "rm -rf build")))
        #expect(current.options == expected.options)
        #expect(PaneChoicePrompt.plan(expected: expected, current: current, option: 1, agent: "claude") == nil)
    }

    @Test func sameOptionsDifferentFileIsChanged() throws {
        let expected = try #require(detect(claudeEdit(file: "Sources/App/Login.swift")))
        let current = try #require(detect(claudeEdit(file: "Sources/App/Billing.swift")))
        #expect(expected.context.contains("Sources/App/Login.swift"))
        #expect(PaneChoicePrompt.plan(expected: expected, current: current, option: 1, agent: "claude") == nil)
        #expect(PaneChoicePrompt.plan(expected: expected, current: expected, option: 1, agent: "claude") == "1")
    }

    @Test func contextStopsAtSolidRuleButNotDashedRule() throws {
        let prompt = try #require(detect(claudeLiveNotice))
        #expect(prompt.context.first == "Bash command")
        #expect(prompt.context.contains("python3 -c \"open('probe2.txt','w').write('two')\""))
        #expect(prompt.context.contains("This command requires approval"))
        #expect(!prompt.context.contains { $0.contains("Writing \"two\"") })
    }

    @Test func contextSkipsWorkingStatusRow() throws {
        let ticking = "• Working (12s • esc to interrupt)\n" + codexQuestionList
        let prompt = try #require(detect(ticking))
        #expect(prompt.context == ["Question 1/1 (1 unanswered)", "Which color?"])
        // The timer ticking above the question changes nothing being answered.
        let later = try #require(detect(ticking.replacingOccurrences(of: "12s", with: "13s")))
        #expect(PaneChoicePrompt.plan(expected: prompt, current: later, option: 1, agent: "codex") == "1")
    }

    @Test func identityIgnoresSoftWrapAndHighlight() throws {
        let expected = try #require(detect(claudePermission))
        let rewrapped = try #require(detect(claudePermission.replacingOccurrences(
            of: "/fixture/work/xxxxxxxxxxxxxxxx\n      xxxxxxxxxxxxxxxx from this project",
            with: "/fixture/work/xxxxxxxxxxxxxxxxxxxxxxxx\n      xxxxxxxx from this project")))
        #expect(rewrapped.identity == expected.identity)
        let moved = try #require(detect(claudePermission
            .replacingOccurrences(of: " ❯ 1. Yes", with: "   1. Yes")
            .replacingOccurrences(of: "   4. No", with: " ❯ 4. No")))
        #expect(moved.highlighted == 4)
        #expect(PaneChoicePrompt.plan(expected: expected, current: moved, option: 1, agent: "claude") == "1")
    }

    @Test func ansiPollAndTextCheckGiveTheSameIdentity() throws {
        let coloured = claudePermission
            .replacingOccurrences(of: " ❯ 1. Yes", with: " \u{1B}[36m❯\u{1B}[0m 1. \u{1B}[1mYes\u{1B}[0m")
            .replacingOccurrences(of: " echo herdcats-probe > probe.txt",
                                  with: " \u{1B}[38;5;208mecho herdcats-probe > probe.txt\u{1B}[0m")
            .replacingOccurrences(of: "   4. No", with: "   4. \u{1B}[2mNo\u{1B}[0m   ")
        let poll = try #require(detect(coloured))
        let check = try #require(detect(claudePermission))
        #expect(poll.identity == check.identity)
        #expect(PaneChoicePrompt.plan(expected: poll, current: check, option: 1, agent: "claude") == "1")
    }

    @Test func contextDifferenceAtWindowTopFailsSafe() throws {
        // The question's context runs to the top of the read. If a reflowed
        // soft wrap changes the top row between the two reads, nothing is sent.
        let first = try #require(detect(claudeQuestion))
        let reflowed = try #require(detect(claudeQuestion.replacingOccurrences(
            of: "←  ☐ Color  ☐ Toppings  ✔ Submit  →", with: "☐ Toppings  ✔ Submit  →")))
        #expect(reflowed.options == first.options)
        #expect(PaneChoicePrompt.plan(expected: first, current: reflowed, option: 1, agent: "claude") == nil)
    }

    // MARK: False positives

    @Test func ignoresEchoedNumberedUserPrompt() {
        let echo = """
        > 1. Fix the login bug
          2. Add a regression test

        ⏺ I'll start with the login bug.

        ✻ Working… (esc to interrupt)

        ╭──────────────────────────────╮
        │ >                            │
        ╰──────────────────────────────╯
          ? for shortcuts
        """
        #expect(detect(echo) == nil)
        #expect(detect(echo.replacingOccurrences(of: "  ? for shortcuts", with: "  esc to interrupt")) == nil)
    }

    @Test func ignoresCodexEchoFollowedByWorkingRowAndComposer() {
        // "esc to interrupt" makes the Working row look like a hint row; the
        // composer under it is what keeps this from being a prompt.
        let echo = """
        › 1. Fix the login bug
          2. Add a regression test

        • Working (4s • esc to interrupt)

        › Ask Codex to do anything

          100% context left · ? for shortcuts
        """
        #expect(detect(echo) == nil)
        #expect(detect(echo.replacingOccurrences(of: "\n\n  100% context left · ? for shortcuts", with: "")) == nil)
    }

    @Test func ignoresIdlePromptAndCodexComposer() {
        #expect(detect("╭────────╮\n│ >      │\n╰────────╯\n  ? for shortcuts") == nil)
        #expect(detect("› Ask Codex to do anything\n\n  100% context left") == nil)
        #expect(detect("") == nil)
    }

    @Test func ignoresNumberedListsInReplies() {
        // No selection marker, so not a prompt, even with a hint-like row under it.
        let reply = """
        ⏺ Here's the plan:
          1. Read the login screen
          2. Fix the retry logic
          3. Add a test

          Press enter to continue or esc to stop.
        """
        #expect(detect(reply) == nil)
    }

    @Test func requiresAHintRow() {
        #expect(detect(claudePermission.replacingOccurrences(of: "\n\n Esc to cancel · Tab to amend", with: "")) == nil)
    }

    @Test func requiresExactlyOneHighlight() {
        #expect(detect(claudePermission.replacingOccurrences(of: " ❯ 1. Yes", with: "   1. Yes")) == nil)
        #expect(detect(claudePermission.replacingOccurrences(
            of: "   3. Yes, and switch", with: " ❯ 3. Yes, and switch")) == nil)
    }

    @Test func rejectsGapsDuplicatesAndMoreThanSixteen() {
        #expect(detect(claudePermission.replacingOccurrences(of: "   3. Yes, and switch", with: "   5. Yes, and switch")) == nil)
        #expect(detect(claudePermission.replacingOccurrences(of: "   3. Yes, and switch", with: "   2. Yes, and switch")) == nil)
        func list(_ count: Int) -> String {
            (1...count).map { ($0 == 1 ? "❯ " : "  ") + "\($0). Option \($0)" }.joined(separator: "\n")
                + "\n\nEnter to select · Esc to cancel"
        }
        #expect(detect(list(16))?.options.count == 16)
        #expect(detect(list(17)) == nil)
        #expect(detect(list(1)) == nil)
    }

    @Test func rejectsMisalignedNumberColumns() {
        #expect(detect(claudePermission.replacingOccurrences(of: "   3. Yes, and switch", with: "    3. Yes, and switch")) == nil)
    }

    @Test func ignoresClaudeComposerHoldingANumberedDraft() {
        // A draft between the composer's rules, above a footer with an arrow
        // in it: a rule under the last option means it isn't a dialog.
        let composer = """
        ⏺ Done. Anything else?

        ────────────────────────────────────────
        ❯ 1. Fix the login bug
          2. Add a regression test
        ────────────────────────────────────────
          ↑ to edit queued messages
        """
        #expect(detect(composer) == nil)
    }

    @Test func findsThePromptAboveManyBlankRows() throws {
        // A tall terminal after /clear: the dialog sits above many blank rows.
        let tall = claudePermission + String(repeating: "\n", count: 61)
        let expected = try #require(detect(claudePermission))
        let prompt = try #require(detect(tall))
        #expect(prompt.identity == expected.identity)
        #expect(PaneChoicePrompt.answerKey(screen: tall, expected: expected, option: 1, agent: "claude") == "1")
    }

    // MARK: Plumbing

    @Test func detectionUsesTheLastSixtyParsedRows() {
        func rows(detailRows: Int) -> [String] {
            ["❯ 1. Yes", "  2. No"] + Array(repeating: "     detail", count: detailRows) + ["", "Esc to cancel"]
        }
        #expect(rows(detailRows: 56).count == PaneChoicePrompt.window)
        #expect(PaneChoicePrompt.detect(rows: rows(detailRows: 56)) != nil)
        // One more row pushes option 1 above the window, so it isn't a prompt.
        #expect(PaneChoicePrompt.detect(rows: rows(detailRows: 57)) == nil)
    }

    @Test func rowsFromStripsAnsiAndTrailingSpacesLikeTrimmedLines() {
        let coloured = " \u{1B}[36m❯\u{1B}[0m 1. \u{1B}[1mYes\u{1B}[0m   \n   2. No\t\n\n Esc to cancel"
        let palette = TerminalPalette(palette: .moonlit, dark: true)
        let rows = PaneChoicePrompt.rows(from: coloured)
        #expect(rows == PaneOutputPresentation.trimmedLines(from: coloured, palette: palette).map(\.plain))
        #expect(rows.first == " ❯ 1. Yes")
        #expect(PaneChoicePrompt.rows(from: "").isEmpty)
    }

    @Test func answerChoiceWithStaleGenerationSendsNothing() async throws {
        let prompt = try #require(detect(claudePermission))
        let connection = HerdrConnection()
        let result = try await connection.paneAnswerChoice(
            paneId: "w1:p1", expected: prompt, option: 1, agent: "claude",
            owned: ConnectionGeneration(rawValue: 999)
        )
        // Refused before the lane, so nothing was read or sent.
        #expect(result == .notSent)
        #expect(await connection.paneInput.isBusy("w1:p1") == false)
    }

    @Test func answerReadsChecksAndSendsOnlyAnUnchangedPrompt() async throws {
        let expected = try #require(detect(claudePermission))
        let keys = SentKeys()
        func answer(
            _ screen: @escaping () throws -> String,
            send: @escaping (String) async throws -> Void
        ) async throws -> PaneChoiceSendResult {
            try await PaneChoicePrompt.answer(expected: expected, option: 2, agent: "claude",
                                              read: { try screen() }, send: send)
        }
        let record: (String) async throws -> Void = { await keys.add($0) }
        // The screen still shows the prompt: the digit goes out once.
        let unchanged = try await answer({ claudePermission }, send: record)
        #expect(unchanged == .sent)
        #expect(await keys.sent == ["2"])
        // A different command, or no prompt at all: nothing is sent.
        let otherCommand = claudePermission.replacingOccurrences(of: "echo herdcats-probe > probe.txt", with: "rm -rf build")
        let changed = try await answer({ otherCommand }, send: record)
        let gone = try await answer({ "All done." }, send: record)
        #expect(changed == .changed)
        #expect(gone == .changed)
        // The read fails: nothing was sent.
        let unread = try await answer({ throw HerdrError.timeout("pane read") }, send: record)
        #expect(unread == .notSent)
        #expect(await keys.sent == ["2"])
        // Herdr Core refuses the key after checking it: nothing was pressed.
        let refused = CoreRPCError.remote(code: -32602, kind: "invalid_params", message: "unknown key \"2\"", hint: nil)
        let refusedResult = try await answer({ claudePermission }, send: { _ in throw refused })
        #expect(refusedResult == .notSent)
        // A send that times out may have arrived, so the error goes up.
        do {
            _ = try await answer({ claudePermission }, send: { _ in throw HerdrError.timeout("pane send-keys") })
            Issue.record("An uncertain send must be reported")
        } catch {
            #expect(error as? HerdrError == .timeout("pane send-keys"))
        }
    }

    @Test @MainActor func tapChecksTheDrawnPromptNotTheCurrentOne() throws {
        let drawn = try #require(detect(claudePermission))
        let current = try #require(detect(claudePermission.replacingOccurrences(
            of: "echo herdcats-probe > probe.txt", with: "rm -rf build")))
        let state = PaneChoiceAnswerState()
        state.sync(drawn, now: 100)
        // A poll brought a new dialog with the same labels before the card
        // redrew: the tap was aimed at the old one, so nothing is sent.
        #expect(state.begin(option: 1, drawn: drawn, current: current, now: 101) == nil)
        #expect(!state.isSending)
        #expect(state.statusText == PaneChoiceAnswerState.changedText)
        #expect(state.begin(option: 1, drawn: drawn, current: nil, now: 101) == nil)
        // Once the card shows the new dialog, a tap right away is ignored and
        // a tap a moment later goes ahead.
        state.sync(current, now: 200)
        #expect(state.begin(option: 1, drawn: current, current: current, now: 200.2) == nil)
        #expect(state.begin(option: 1, drawn: current, current: current, now: 200.6) != nil)
        #expect(state.statusText == PaneChoiceAnswerState.sendingText)
    }

    @Test @MainActor func liveKeyboardInputDuringAnAnswerArrivesAsTyped() async throws {
        let answering = route(queueState: .ready, isAnswering: true)
        // `tesst` ⌫ ⌫ `ts` ⏎, as the Live keyboard sends it.
        let typed: [PaneLiveInputEvent] = [
            .text("tesst"), .keys(["backspace"]), .keys(["backspace"]), .text("ts"), .keys(["enter"]),
        ]
        for event in typed {
            #expect(PaneKeyRoute.token(for: event, route: answering, liveInputEnabled: true) == .live)
        }
        #expect(PaneKeyRoute.token(for: .keys(["ctrl+c"]), route: answering, liveInputEnabled: true) == .live)
        #expect(PaneKeyRoute.token(for: .keys(["enter"]), route: answering, liveInputEnabled: false) == nil)

        // The answer holds the pane's lane; everything typed queues behind it.
        let lane = ExternallyReleasedWait<Void>()
        let sender = RecordingLiveSender(firstSendGate: lane)
        let queue = PaneLiveInputQueue(sender: sender, maxPending: 8)
        let live = PaneLiveInputSession(paneId: "w1:p1", generation: ConnectionGeneration(rawValue: 2))
        for event in typed {
            #expect(queue.enqueue(event, session: live))
        }
        await sender.note("answer:1")
        lane.release(())
        try await waitUntilLiveIdle(queue)
        #expect(await sender.wire == ["answer:1", "text:tesst", "keys:backspace,backspace", "text:ts", "keys:enter"])
        #expect(queue.acknowledgedCount == 5)
    }

    @Test @MainActor func answerStateIgnoresStaleTokens() throws {
        let prompt = try #require(detect(claudePermission))
        let state = PaneChoiceAnswerState()
        state.sync(prompt, now: 0)
        let token = try #require(state.begin(option: 1, drawn: prompt, current: prompt, now: 1))
        // One answer at a time.
        #expect(state.begin(option: 2, drawn: prompt, current: prompt, now: 1) == nil)
        // Results for other tokens are ignored.
        state.finish(token: UUID(), result: .sent, identity: prompt.identity)
        state.fail(token: UUID(), message: "late")
        #expect(state.isSending)
        state.finish(token: token, result: .changed, identity: prompt.identity)
        #expect(!state.isSending)
        #expect(state.statusText == PaneChoiceAnswerState.changedText)
        // The same token can't finish twice.
        state.finish(token: token, result: .sent, identity: prompt.identity)
        #expect(!state.isHidden(for: prompt))
    }

    @Test @MainActor func answerStateShowsANewDialogWithTheSameLabels() throws {
        let first = try #require(detect(claudePermission))
        let next = try #require(detect(claudePermission.replacingOccurrences(
            of: "echo herdcats-probe > probe.txt", with: "echo second > probe.txt")))
        let state = PaneChoiceAnswerState()
        state.sync(first, now: 0)
        let token = try #require(state.begin(option: 1, drawn: first, current: first, now: 1))
        state.finish(token: token, result: .sent, identity: first.identity)
        #expect(state.isHidden(for: first))
        state.sync(next)
        #expect(!state.isHidden(for: next))
        #expect(state.phase == .idle)
    }

    @Test @MainActor func answerStateShowsSendingTextWhileSending() throws {
        let prompt = try #require(detect(claudePermission))
        let state = PaneChoiceAnswerState()
        state.sync(prompt, now: 0)
        #expect(state.statusText == nil)
        let token = try #require(state.begin(option: 2, drawn: prompt, current: prompt, now: 1))
        #expect(state.phase == .sending(option: 2))
        #expect(state.statusText == "Sending your answer…")
        state.fail(token: token, message: PaneChoiceAnswerState.uncertainText)
        #expect(!state.isSending)
        #expect(state.statusText == PaneChoiceAnswerState.uncertainText)
        // A failure before the send says plainly that nothing was sent.
        let again = try #require(state.begin(option: 2, drawn: prompt, current: prompt, now: 2))
        state.finish(token: again, result: .notSent, identity: prompt.identity)
        #expect(state.statusText == "Nothing was sent. Check the screen and try again.")
    }

    @Test func accessibilityHintNamesTheKey() {
        #expect(PaneChoicePrompt.accessibilityHint(forKey: "2") == "Sends 2")
        #expect(PaneChoicePrompt.accessibilityHint(forKey: "y") == "Sends y")
        #expect(PaneChoicePrompt.accessibilityHint(forKey: "esc") == "Sends Escape")
    }

    @Test func reloadsOnceWhenStatusBecomesBlocked() {
        #expect(PaneFocusPolicy.reloadsOnBlocked(from: .working, to: .blocked))
        #expect(PaneFocusPolicy.reloadsOnBlocked(from: .idle, to: .blocked))
        #expect(!PaneFocusPolicy.reloadsOnBlocked(from: .blocked, to: .blocked))
        #expect(!PaneFocusPolicy.reloadsOnBlocked(from: .blocked, to: .idle))
        #expect(!PaneFocusPolicy.reloadsOnBlocked(from: .idle, to: .working))
    }

    @Test func answeringRouteTurnsRailKeysOff() {
        let answering = route(queueState: .ready, isAnswering: true)
        #expect(answering == .unavailable(.answering))
        #expect(!answering.sendsKeys)
        // The card says "Sending your answer…", so the key row stays quiet.
        #expect(PaneKeyNotice.resolve(route: answering, pauseReason: nil, transient: "A notice", sessionError: "An error",
                                      resyncReadFailures: 0, backoffAtCap: false, showsTimeline: false) == nil)
    }

    @Test @MainActor func pausedQueueShowsTheAnswerReasonFirst() throws {
        // After an answer that may have arrived, the view stops the queue
        // (creating it first if needed); the key row then says why.
        let queue = PaneLiveInputQueue(sender: RecordingLiveSender())
        queue.stopForResync()
        let paused = route(queueState: queue.state)
        #expect(paused == .unavailable(.resyncing))
        let notice = try #require(PaneKeyNotice.resolve(
            route: paused, pauseReason: PaneKeyNotice.answerMayHaveArrived, transient: nil, sessionError: nil,
            resyncReadFailures: 0, backoffAtCap: false, showsTimeline: false))
        #expect(notice.text.hasPrefix("Your answer may have reached the pane."))
    }
}

private actor SentKeys {
    private(set) var sent: [String] = []

    func add(_ key: String) {
        sent.append(key)
    }
}
