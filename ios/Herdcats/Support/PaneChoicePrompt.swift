import Foundation

/// What came of a tap on a choice card's option.
enum PaneChoiceSendResult: Equatable, Sendable {
    case sent
    /// A fresh read showed a different prompt (or none), so nothing was sent.
    case changed
    /// The pane couldn't be checked, or Herdr Core refused the key, so
    /// nothing was sent.
    case notSent
}

/// A numbered choice an agent shows at the bottom of a terminal pane, such as
/// Claude's "Do you want to proceed?" or a Codex approval, read from the
/// pane's plain text so it can be answered with a tap.
///
/// Detection is strict on purpose. The options must be the last thing on the
/// screen apart from hint rows (such as "Esc to cancel"), numbered 1, 2, 3… in
/// one column, with exactly one selection marker. A numbered list in an
/// agent's reply has no marker and no hint row under it, so it never matches.
///
/// Detection and the check before sending both read the same rows: the
/// pane's text parsed by `ANSIText` into plain rows, the last `window` of
/// them. So the two can only disagree if the screen itself changed.
struct PaneChoicePrompt: Equatable, Sendable {
    struct Option: Equatable, Sendable {
        let number: Int
        let label: String
        /// Rows under the option, joined: a wrapped label or a description.
        let detail: String?
        /// `y`, `p` or `esc`, only when every option ends with one, as Codex
        /// approvals do ("Yes, proceed (y)").
        let shortcut: String?
        /// Multi-select state: `[ ] ` is false, `[✔] ` is true.
        let checked: Bool?
        /// "Type something", "Type something." or "Other": answering needs
        /// typed text, which v1 doesn't send.
        let isFreeText: Bool
    }

    /// The rows above the first option: the question, command, file or
    /// reason rows that say what is being answered.
    let context: [String]
    let options: [Option]
    /// The number of the option with the selection marker.
    let highlighted: Int
    let hints: [String]

    /// Parsed rows read from the bottom of the pane, the same for detection
    /// and for the check before sending.
    static let window = 60
    static let maxOptions = 16
    static let maxContextRows = 20

    /// What must be unchanged before an answer is sent: the context rows,
    /// then each option's number, text, checkbox and shortcut, with all
    /// whitespace removed so a different soft wrap reads the same. The
    /// selection marker is left out, because moving it changes nothing that
    /// is being answered.
    var identity: [String] {
        var parts = [Self.squash(context.joined())]
        for option in options {
            parts.append([
                String(option.number),
                Self.squash(option.label + (option.detail ?? "")),
                option.checked.map { $0 ? "[✔]" : "[ ]" } ?? "",
                option.shortcut ?? "",
            ].joined(separator: "\u{1F}"))
        }
        return parts
    }

    var hasShortcuts: Bool { options.allSatisfy { $0.shortcut != nil } }

    /// True when at least one option can be answered with a tap.
    func isAnswerable(agent: String?) -> Bool {
        options.contains { answerKey(option: $0.number, agent: agent) != nil }
    }

    /// The single key that answers one option, or nil when v1 doesn't answer
    /// that row. v1 sends only a digit or a letter, the keys the Herdcats
    /// Bridge uses for the same prompts:
    /// - Claude: the option's digit (it selects and advances; in a
    ///   multi-select question it toggles the box).
    /// - Codex approval: the row's letter shortcut, or `esc`.
    /// - Codex question with "enter to submit answer": the digit, which
    ///   answers and moves to the next question.
    /// Everything else needs arrows and Enter, which v1 doesn't send.
    func answerKey(option number: Int, agent: String?) -> String? {
        guard let option = options.first(where: { $0.number == number }), !option.isFreeText else { return nil }
        switch agent {
        case "claude":
            return number <= 9 ? String(number) : nil
        case "codex":
            if hasShortcuts { return option.shortcut }
            let submitsAnswer = hints.contains { $0.lowercased().contains("enter to submit answer") }
            return submitsAnswer && number <= 9 ? String(number) : nil
        default:
            return nil
        }
    }

    /// The key to send for `option`, or nil, which means send nothing: the
    /// fresh prompt differs from the one the user tapped (question, command,
    /// file or options), or the row has no v1 key.
    static func plan(expected: PaneChoicePrompt, current: PaneChoicePrompt, option: Int, agent: String?) -> String? {
        guard expected.identity == current.identity else { return nil }
        return current.answerKey(option: option, agent: agent)
    }

    /// The key to send for `option` given a fresh read of the pane, or nil
    /// when that read doesn't show the expected prompt (or none at all).
    static func answerKey(screen: String, expected: PaneChoicePrompt, option: Int, agent: String?) -> String? {
        guard let current = detect(rows: rows(from: screen)) else { return nil }
        return plan(expected: expected, current: current, option: option, agent: agent)
    }

    /// Reads the pane, checks the prompt, and sends the key only if it is
    /// unchanged. The connection supplies the read and the send, inside the
    /// pane's input lane. A failure before the send means nothing was sent;
    /// a failure during the send may or may not have delivered the key and is
    /// rethrown, except a Herdr Core refusal, which presses nothing.
    static func answer(
        expected: PaneChoicePrompt,
        option: Int,
        agent: String?,
        read: () async throws -> String,
        send: (String) async throws -> Void
    ) async throws -> PaneChoiceSendResult {
        let screen: String
        do {
            screen = try await read()
        } catch {
            return .notSent
        }
        guard let key = answerKey(screen: screen, expected: expected, option: option, agent: agent) else {
            return .changed
        }
        do {
            try await send(key)
        } catch {
            if PaneLiveInputFailure.classify(error, event: .keys([key])).pressedNothing { return .notSent }
            throw error
        }
        return .sent
    }

    /// VoiceOver hint for an option's button.
    static func accessibilityHint(forKey key: String) -> String {
        key == "esc" ? "Sends Escape" : "Sends \(key)"
    }

    // MARK: - Rows

    /// The one row function both detection and the check use: ANSI parsed
    /// into plain text, trailing spaces and tabs trimmed. It matches the rows
    /// `PaneOutputPresentation.trimmedLines` builds for the terminal view.
    static func rows(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return ANSIText.lines(from: text).map { PaneOutputPresentation.trimTrailingSpacesAndTabs($0.plain) }
    }

    // MARK: - Detection

    static func detect(rows input: [String]) -> PaneChoicePrompt? {
        // Blank rows under the dialog (a tall, mostly empty screen) don't
        // count toward the window.
        var end = input.count
        while end > 0, isBlank(input[end - 1]) { end -= 1 }
        let rows = Array(input[..<end].suffix(window))
        var index = rows.count - 1

        // Hint rows at the very bottom: at least one, at most three.
        var hints: [String] = []
        while index >= 0 {
            let row = rows[index]
            if isBlank(row) {
                index -= 1
                continue
            }
            guard hints.count < 3, optionRow(row) == nil, isHint(row) else { break }
            hints.insert(row.trimmingCharacters(in: .whitespaces), at: 0)
            index -= 1
        }
        guard !hints.isEmpty else { return nil }

        // The options, read upward until option 1. Rows below an option and
        // indented deeper than its number belong to it.
        var found: [(row: OptionRow, below: [String])] = []
        var below: [String] = []
        var blankRun = 0
        while index >= 0 {
            let row = rows[index]
            index -= 1
            if let option = optionRow(row) {
                if let previous = found.last {
                    guard option.number == previous.row.number - 1 else { return nil }
                } else {
                    guard (2...maxOptions).contains(option.number) else { return nil }
                }
                guard below.allSatisfy({ indent(of: $0) > option.column }) else { return nil }
                found.append((option, below.reversed()))
                below = []
                blankRun = 0
                if option.number == 1 { break }
                continue
            }
            if isBlank(row) {
                blankRun += 1
                guard blankRun < 2 else { return nil }
                continue
            }
            blankRun = 0
            if isRule(row) {
                // Rules may separate options, but not the last option from the
                // hints: that shape is a composer between rules holding a
                // numbered draft, not a dialog.
                guard !found.isEmpty else { return nil }
                continue
            }
            below.append(row)
        }
        guard let first = found.last?.row, first.number == 1 else { return nil }
        let column = first.column
        guard found.allSatisfy({ $0.row.column == column }) else { return nil }
        let marked = found.filter { $0.row.marked }
        guard marked.count == 1, let highlighted = marked.first?.row.number else { return nil }

        let parsed = found.reversed().map { entry in
            Parsed(number: entry.row.number, label: entry.row.label,
                   detailRows: entry.below.map { $0.trimmingCharacters(in: .whitespaces) })
        }
        return PaneChoicePrompt(
            context: context(rows: rows, above: index),
            options: options(from: parsed),
            highlighted: highlighted,
            hints: hints
        )
    }

    // MARK: - Parsing helpers

    private struct OptionRow {
        let number: Int
        let label: String
        let marked: Bool
        /// Where the number starts, counting the marker.
        let column: Int
    }

    private struct Parsed {
        let number: Int
        let label: String
        let detailRows: [String]
    }

    private static let optionPattern = try! NSRegularExpression(
        pattern: #"^(\s*)(?:([❯›>→])\s)?(\d{1,2})[.)]\s+(\S.*)$"#
    )
    private static let hintWordPattern = try! NSRegularExpression(
        pattern: #"\b(enter|esc)\b"#, options: [.caseInsensitive]
    )
    private static let shortcutPattern = try! NSRegularExpression(
        pattern: #"^(.*?)\s*\((esc|[A-Za-z])\)$"#
    )
    private static let freeTextLabels: Set<String> = ["Type something", "Type something.", "Other"]

    private static func optionRow(_ row: String) -> OptionRow? {
        let range = NSRange(row.startIndex..., in: row)
        guard let match = optionPattern.firstMatch(in: row, range: range),
              let leading = Range(match.range(at: 1), in: row),
              let digits = Range(match.range(at: 3), in: row),
              let label = Range(match.range(at: 4), in: row),
              let number = Int(row[digits]) else { return nil }
        let marked = match.range(at: 2).location != NSNotFound
        return OptionRow(
            number: number,
            label: String(row[label]),
            marked: marked,
            column: row[leading].count + (marked ? 2 : 0)
        )
    }

    private static func options(from parsed: [Parsed]) -> [Option] {
        // A shortcut ends the option's last row; it counts only if every
        // option has one.
        let shortcuts: [(text: String, key: String)?] = parsed.map { entry in
            let last = entry.detailRows.last ?? entry.label
            let range = NSRange(last.startIndex..., in: last)
            guard let match = shortcutPattern.firstMatch(in: last, range: range),
                  let text = Range(match.range(at: 1), in: last),
                  let key = Range(match.range(at: 2), in: last) else { return nil }
            return (String(last[text]), String(last[key]).lowercased())
        }
        let usesShortcuts = shortcuts.allSatisfy { $0 != nil }
        return zip(parsed, shortcuts).map { entry, shortcut in
            var label = entry.label
            var detailRows = entry.detailRows
            var key: String?
            if usesShortcuts, let shortcut {
                key = shortcut.key
                if detailRows.isEmpty {
                    label = shortcut.text
                } else {
                    detailRows[detailRows.count - 1] = shortcut.text
                    if detailRows[detailRows.count - 1].isEmpty { detailRows.removeLast() }
                }
            }
            var checked: Bool?
            if label.hasPrefix("[ ] ") {
                checked = false
                label.removeFirst(4)
            } else if label.hasPrefix("[✔] ") {
                checked = true
                label.removeFirst(4)
            }
            let detail = detailRows.isEmpty ? nil : detailRows.joined(separator: " ")
            return Option(number: entry.number, label: label, detail: detail, shortcut: key,
                          checked: checked, isFreeText: freeTextLabels.contains(label))
        }
    }

    /// Walks upward from the row above option 1, collecting what the prompt
    /// is about. Stops at a Codex title (kept), a solid rule, an agent status
    /// row, two blank rows, the top of the window, or 20 rows. Dashed rules
    /// inside a Claude dialog don't stop it, so the command between them is
    /// kept.
    private static func context(rows: [String], above start: Int) -> [String] {
        var context: [String] = []
        var blankRun = 0
        var index = start
        while index >= 0, context.count < maxContextRows {
            let text = rows[index].trimmingCharacters(in: .whitespaces)
            index -= 1
            if text.isEmpty {
                blankRun += 1
                if blankRun >= 2 { break }
                continue
            }
            blankRun = 0
            if text.hasPrefix("Would you like to") {
                context.insert(text, at: 0)
                break
            }
            if isSolidRule(text) || text.lowercased().contains("esc to interrupt") { break }
            context.insert(text, at: 0)
        }
        return context
    }

    private static func isBlank(_ row: String) -> Bool {
        row.allSatisfy(\.isWhitespace)
    }

    private static func isHint(_ row: String) -> Bool {
        let lower = row.lowercased()
        if ["↑", "↓", "navigate", "to select", "to confirm", "to cancel"].contains(where: { lower.contains($0) }) {
            return true
        }
        return hintWordPattern.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)) != nil
    }

    /// Any rule row, dashed ones included; allowed between options.
    private static func isRule(_ row: String) -> Bool {
        let text = row.trimmingCharacters(in: .whitespaces)
        return text.count >= 3 && text.allSatisfy { "─━═╌-".contains($0) }
    }

    /// A solid rule, which ends a dialog's context.
    private static func isSolidRule(_ text: String) -> Bool {
        text.count >= 10 && text.allSatisfy { "─━═".contains($0) }
    }

    private static func indent(of row: String) -> Int {
        row.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func squash(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }
}
