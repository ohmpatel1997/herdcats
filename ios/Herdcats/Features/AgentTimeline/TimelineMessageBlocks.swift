import Foundation
import SwiftUI
import UIKit

// MARK: - Block parsing

/// The block structure of an agent message: headings, lists, quotes, rules
/// and fenced code, around paragraphs of inline markdown. Nested lists and
/// tables stay as text.
enum TimelineMessageBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bullets([String])
    case numbered(start: Int, items: [String])
    case quote(String)
    /// `text` is already the shown text, with hidden text-direction
    /// characters removed; `removedHidden` says whether any were.
    case code(language: String?, text: String, removedHidden: Bool)
    case rule

    /// One pass over the lines. Text with no block syntax comes back as one
    /// paragraph, unchanged, so plain messages render exactly as before.
    static func parse(_ text: String) -> [TimelineMessageBlock] {
        var parser = Parser()
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            parser.consume(Substring(line))
        }
        let blocks = parser.finish()
        if blocks.allSatisfy({ if case .paragraph = $0 { true } else { false } }) {
            return [.paragraph(text)]
        }
        return blocks
    }

    private struct Fence {
        let marker: Character
        let length: Int
        let indent: Int
        let language: String?
        var lines: [Substring] = []
    }

    private enum Open {
        case none
        case paragraph([Substring])
        case bullets(indent: Int, items: [String])
        case numbered(indent: Int, start: Int, items: [String])
        case quote([Substring])
        case fence(Fence)
    }

    private struct Parser {
        var blocks: [TimelineMessageBlock] = []
        var open: Open = .none

        mutating func consume(_ line: Substring) {
            if case .fence(var fence) = open {
                if Self.closes(fence, line) {
                    blocks.append(Self.code(fence))
                    open = .none
                } else {
                    fence.lines.append(Self.dropIndent(line, upTo: fence.indent))
                    open = .fence(fence)
                }
                return
            }
            let indent = Self.indent(of: line)
            let blank = line.allSatisfy { $0 == " " || $0 == "\t" }
            if blank {
                if case .paragraph(let lines) = open {
                    open = .paragraph(lines + [line])
                } else {
                    flush()
                }
                return
            }
            if indent <= 3 {
                let body = line.dropFirst(indent)
                if let fence = Self.openingFence(body, indent: indent) {
                    flush(); open = .fence(fence); return
                }
                if let heading = Self.heading(body) {
                    flush(); blocks.append(heading); return
                }
                if Self.isRule(body) {
                    flush(); blocks.append(.rule); return
                }
                if let quoted = Self.quoteContent(body) {
                    if case .quote(let lines) = open {
                        open = .quote(lines + [quoted])
                    } else {
                        flush(); open = .quote([quoted])
                    }
                    return
                }
                if let item = Self.bulletContent(body), !isNested(indent) {
                    if case .bullets(let listIndent, let items) = open {
                        open = .bullets(indent: listIndent, items: items + [String(item)])
                    } else {
                        flush(); open = .bullets(indent: indent, items: [String(item)])
                    }
                    return
                }
                if let (number, item) = Self.numberedContent(body), !isNested(indent) {
                    if case .numbered(let listIndent, let start, let items) = open {
                        open = .numbered(indent: listIndent, start: start, items: items + [String(item)])
                        return
                    }
                    // A numbered line only interrupts a paragraph when it
                    // starts at 1, so "2024. That year…" stays a sentence.
                    if case .paragraph = open, number != 1 {
                        appendText(line)
                        return
                    }
                    flush(); open = .numbered(indent: indent, start: number, items: [String(item)])
                    return
                }
            }
            appendText(line)
        }

        /// A marker indented past the open list's own marker is a nested
        /// list, which stays as text inside the current item.
        private func isNested(_ indent: Int) -> Bool {
            switch open {
            case .bullets(let listIndent, _), .numbered(let listIndent, _, _): indent > listIndent
            default: false
            }
        }

        /// Plain text continues the open block: a list item, a quote or a paragraph.
        private mutating func appendText(_ line: Substring) {
            switch open {
            case .bullets(let indent, var items):
                items[items.count - 1] += "\n" + line.drop { $0 == " " || $0 == "\t" }
                open = .bullets(indent: indent, items: items)
            case .numbered(let indent, let start, var items):
                items[items.count - 1] += "\n" + line.drop { $0 == " " || $0 == "\t" }
                open = .numbered(indent: indent, start: start, items: items)
            case .quote(let lines):
                open = .quote(lines + [line])
            case .paragraph(let lines):
                open = .paragraph(lines + [line])
            case .none, .fence:
                open = .paragraph([line])
            }
        }

        private mutating func flush() {
            switch open {
            case .none, .fence: break
            case .paragraph(var lines):
                while let last = lines.last, last.allSatisfy({ $0 == " " || $0 == "\t" }) { lines.removeLast() }
                if !lines.isEmpty { blocks.append(.paragraph(lines.joined(separator: "\n"))) }
            case .bullets(_, let items): blocks.append(.bullets(items))
            case .numbered(_, let start, let items): blocks.append(.numbered(start: start, items: items))
            case .quote(let lines): blocks.append(.quote(lines.joined(separator: "\n")))
            }
            open = .none
        }

        mutating func finish() -> [TimelineMessageBlock] {
            // An unterminated fence runs to the end of the message.
            if case .fence(let fence) = open {
                blocks.append(Self.code(fence))
                open = .none
            }
            flush()
            return blocks
        }

        private static func indent(of line: Substring) -> Int {
            var count = 0
            for character in line {
                if character == " " { count += 1 } else if character == "\t" { count += 4 } else { break }
            }
            return count
        }

        private static func dropIndent(_ line: Substring, upTo count: Int) -> Substring {
            var dropped = 0
            var index = line.startIndex
            while dropped < count, index < line.endIndex, line[index] == " " {
                dropped += 1
                index = line.index(after: index)
            }
            return line[index...]
        }

        private static func run(of marker: Character, in text: Substring) -> Int {
            text.prefix { $0 == marker }.count
        }

        private static func openingFence(_ body: Substring, indent: Int) -> Fence? {
            guard let marker = body.first, marker == "`" || marker == "~" else { return nil }
            let length = run(of: marker, in: body)
            guard length >= 3 else { return nil }
            let info = body.dropFirst(length).trimmingCharacters(in: .whitespaces)
            // A backtick fence's info string can't contain backticks.
            if marker == "`" && info.contains("`") { return nil }
            let language = info.split(whereSeparator: \.isWhitespace).first.map(String.init)
            return Fence(marker: marker, length: length, indent: indent, language: language)
        }

        /// Closes on the same marker, at least as long, with nothing after it.
        private static func closes(_ fence: Fence, _ line: Substring) -> Bool {
            guard Self.indent(of: line) <= 3 else { return false }
            let body = line.drop { $0 == " " || $0 == "\t" }
            let length = run(of: fence.marker, in: body)
            return length >= fence.length && body.dropFirst(length).allSatisfy { $0 == " " || $0 == "\t" }
        }

        private static func code(_ fence: Fence) -> TimelineMessageBlock {
            let shown = TimelineMarkdown.displayCode(fence.lines.joined(separator: "\n"))
            return .code(language: fence.language, text: shown.text, removedHidden: shown.removedHidden)
        }

        private static func heading(_ body: Substring) -> TimelineMessageBlock? {
            let level = run(of: "#", in: body)
            guard (1...6).contains(level) else { return nil }
            let rest = body.dropFirst(level)
            guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
            var text = rest.trimmingCharacters(in: .whitespaces)
            // Drop an optional closing run of #s, as in "## Title ##".
            if let closing = text.lastIndex(where: { $0 != "#" }), text[closing] == " " {
                text = String(text[...closing]).trimmingCharacters(in: .whitespaces)
            } else if text.allSatisfy({ $0 == "#" }) {
                text = ""
            }
            return .heading(level: level, text: text)
        }

        private static func isRule(_ body: Substring) -> Bool {
            guard let marker = body.first, marker == "-" || marker == "*" || marker == "_" else { return false }
            var count = 0
            for character in body {
                if character == marker { count += 1 } else if character != " " && character != "\t" { return false }
            }
            return count >= 3
        }

        private static func quoteContent(_ body: Substring) -> Substring? {
            guard body.first == ">" else { return nil }
            let rest = body.dropFirst()
            return rest.first == " " ? rest.dropFirst() : rest
        }

        private static func bulletContent(_ body: Substring) -> Substring? {
            guard let marker = body.first, marker == "-" || marker == "*" || marker == "+" else { return nil }
            let rest = body.dropFirst()
            guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
            return rest.drop { $0 == " " || $0 == "\t" }
        }

        private static func numberedContent(_ body: Substring) -> (Int, Substring)? {
            let digits = body.prefix { $0.isASCII && $0.isNumber }
            guard (1...9).contains(digits.count), let number = Int(digits) else { return nil }
            let rest = body.dropFirst(digits.count)
            guard let delimiter = rest.first, delimiter == "." || delimiter == ")" else { return nil }
            let after = rest.dropFirst()
            guard after.isEmpty || after.first == " " || after.first == "\t" else { return nil }
            return (number, after.drop { $0 == " " || $0 == "\t" })
        }
    }
}

// MARK: - Rendered blocks

/// A fenced code block as shown: inline it keeps at most
/// `inlineLineLimit` lines of at most `inlineCharacterLimit` characters each;
/// the sheet and Copy use every line in full.
struct TimelineCodeBlock: Equatable {
    static let inlineLineLimit = 40
    static let inlineCharacterLimit = 500

    let language: String?
    /// The shown text: what Copy puts on the clipboard.
    let text: String
    let removedHidden: Bool
    let lines: [String]

    init(language: String?, text: String, removedHidden: Bool) {
        self.language = language
        self.text = text
        self.removedHidden = removedHidden
        lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }

    var isShortened: Bool { lines.count > Self.inlineLineLimit }

    /// Long lines are cut so a minified one-line file can't build a huge view.
    var inlineLines: [String] {
        lines.prefix(Self.inlineLineLimit).map { line in
            line.count > Self.inlineCharacterLimit ? String(line.prefix(Self.inlineCharacterLimit)) + "…" : line
        }
    }
}

/// Blocks with their inline markdown parsed and links vetted.
enum TimelineRenderedBlock: Equatable {
    case paragraph(AttributedString)
    case heading(level: Int, text: AttributedString)
    case bullets([AttributedString])
    case numbered(start: Int, items: [AttributedString])
    case quote(AttributedString)
    case code(TimelineCodeBlock)
    case rule
}

enum TimelineMessageBlocks {
    /// Beyond this size a message is shown as one paragraph, as before, so a
    /// huge message can't make block parsing expensive.
    static let maxParsedBytes = 256 * 1024

    /// Every piece of text except code goes through the same link vetting as
    /// before. Code is shown as plain text, so it never becomes a link.
    static func render(_ text: String) -> [TimelineRenderedBlock] {
        guard text.utf8.count <= maxParsedBytes else { return [.paragraph(TimelineMarkdown.sanitized(text))] }
        return TimelineMessageBlock.parse(text).map { (block) -> TimelineRenderedBlock in
            switch block {
            case .paragraph(let text): .paragraph(TimelineMarkdown.sanitized(text))
            case .heading(let level, let text): .heading(level: level, text: TimelineMarkdown.sanitized(text))
            case .bullets(let items): .bullets(items.map(TimelineMarkdown.sanitized))
            case .numbered(let start, let items): .numbered(start: start, items: items.map(TimelineMarkdown.sanitized))
            case .quote(let text): .quote(TimelineMarkdown.sanitized(text))
            case .code(let language, let text, let removedHidden):
                .code(TimelineCodeBlock(language: language, text: text, removedHidden: removedHidden))
            case .rule: .rule
            }
        }
    }

    /// The text of a message made of one plain paragraph, which keeps the
    /// single text element it always had.
    static func singleParagraph(_ blocks: [TimelineRenderedBlock]) -> AttributedString? {
        guard blocks.count == 1, case .paragraph(let text) = blocks[0] else { return nil }
        return text
    }
}

/// Parsed messages, kept across redraws so a long transcript parses each
/// message once, not on every body pass. Keyed by entry id plus the text's
/// length and hash, so a revised entry parses again. The Timeline holds one
/// per conversation and resets it when the conversation changes.
@MainActor final class TimelineBlockCache {
    private final class Entry {
        let blocks: [TimelineRenderedBlock]
        init(_ blocks: [TimelineRenderedBlock]) { self.blocks = blocks }
    }
    private let cache = NSCache<NSString, Entry>()

    init() { cache.countLimit = 500 }

    func blocks(for entry: AgentTimelineEntry) -> [TimelineRenderedBlock] {
        let key = "\(entry.id):\(entry.text.utf8.count):\(entry.text.hashValue)" as NSString
        if let cached = cache.object(forKey: key) { return cached.blocks }
        let blocks = TimelineMessageBlocks.render(entry.text)
        cache.setObject(Entry(blocks), forKey: key)
        return blocks
    }

    func reset() { cache.removeAllObjects() }
}

// MARK: - Code colours

/// Colours for code in the Timeline: the selected palette's terminal colours
/// for syntax, and the app's text, muted and status colours for the rest.
/// Every one goes through the terminal's AA adjuster against the line's
/// real background, so each reaches 4.5:1 in every palette.
struct TimelineCodeColors: Equatable {
    enum Line { case context, added, removed }

    let text: UInt32
    let comment: UInt32
    let keyword: UInt32
    let number: UInt32
    let string: UInt32
    let added: UInt32
    let removed: UInt32

    /// The palette the app is showing in this appearance.
    static func palette(dark: Bool) -> AppPalette {
        dark ? AppThemePreferences.shared.dark : AppThemePreferences.shared.light
    }

    /// Code sits on the card colour. A changed line adds its 13% wash.
    static func background(_ line: Line, palette: AppPalette, dark: Bool) -> UInt32 {
        let card = hex(Theme.uiColor("card", palette: palette, dark: dark), over: 0)
        switch line {
        case .context: return card
        case .added: return blend(hex(Theme.uiColor("done", palette: palette, dark: dark), over: card), over: card, alpha: 0.13)
        case .removed: return blend(hex(Theme.uiColor("blocked", palette: palette, dark: dark), over: card), over: card, alpha: 0.13)
        }
    }

    static func colors(palette: AppPalette, dark: Bool, line: Line) -> TimelineCodeColors {
        colors(palette: palette, dark: dark, on: background(line, palette: palette, dark: dark))
    }

    static func colors(palette: AppPalette, dark: Bool, on background: UInt32) -> TimelineCodeColors {
        let terminal = TerminalPalette(palette: palette, dark: dark)
        func token(_ name: String) -> UInt32 {
            ANSIText.readableHex(hex(Theme.uiColor(name, palette: palette, dark: dark), over: background), on: background)
        }
        func slot(_ index: Int) -> UInt32 { ANSIText.readableHex(terminal.colors[index], on: background) }
        return TimelineCodeColors(
            text: token("text"), comment: token("muted"),
            keyword: slot(5), number: slot(3), string: slot(2),
            added: token("done"), removed: token("blocked"))
    }

    /// `color` drawn over an opaque `background`, as one opaque colour.
    static func hex(_ color: UIColor, over background: UInt32) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let top = UInt32((r * 255).rounded()) << 16 | UInt32((g * 255).rounded()) << 8 | UInt32((b * 255).rounded())
        return blend(top, over: background, alpha: Double(a))
    }

    static func blend(_ top: UInt32, over bottom: UInt32, alpha: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let t = Double((top >> shift) & 0xFF), b = Double((bottom >> shift) & 0xFF)
            return UInt32((t * alpha + b * (1 - alpha)).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}

extension Color {
    init(codeHex hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

/// A light, language-agnostic highlighter: keywords, numbers, strings and
/// `//` comments, later rules winning.
enum TimelineCodeHighlighter {
    private enum Role { case keyword, number, string, comment }
    private static let rules: [(NSRegularExpression, Role)] = [
        (try! NSRegularExpression(pattern: #"\b(let|var|const|func|function|return|if|else|for|while|class|struct|enum|import|from|true|false|null|nil|async|await|try|throw|public|private|static)\b"#), .keyword),
        (try! NSRegularExpression(pattern: #"\b[0-9]+(?:\.[0-9]+)?\b"#), .number),
        (try! NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'"#), .string),
        (try! NSRegularExpression(pattern: #"//.*$"#, options: [.anchorsMatchLines]), .comment)
    ]

    /// `plain` text gets one colour and no highlighting.
    static func highlight(_ text: String, colors: TimelineCodeColors, plain: UInt32? = nil) -> AttributedString {
        let result = NSMutableAttributedString(
            string: text, attributes: [.foregroundColor: UIColor(hex: plain ?? colors.text)])
        guard plain == nil else { return AttributedString(result) }
        let range = NSRange(text.startIndex..., in: text)
        for (expression, role) in rules {
            let hex = switch role {
            case .keyword: colors.keyword
            case .number: colors.number
            case .string: colors.string
            case .comment: colors.comment
            }
            for match in expression.matches(in: text, range: range) {
                result.addAttribute(.foregroundColor, value: UIColor(hex: hex), range: match.range)
            }
        }
        return AttributedString(result)
    }
}

// MARK: - Views

/// An agent message made of blocks. Each block keeps its own text selection.
struct TimelineBlocksView: View {
    let blocks: [TimelineRenderedBlock]
    /// Used to name each code block for UI tests.
    let entryID: String
    @ScaledMetric(relativeTo: .body) private var markerWidth: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .paragraph(let text):
                    bodyText(text)
                case .heading(let level, let text):
                    Text(text)
                        .font(level <= 2 ? .jost(.title3, weight: .semibold) : .jost(.headline))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                case .bullets(let items):
                    list(items) { _ in "•" }
                case .numbered(let start, let items):
                    list(items) { "\(start + $0)." }
                case .quote(let text):
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Theme.accent).frame(width: 3)
                            .accessibilityHidden(true)
                        bodyText(text)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                case .code(let code):
                    TimelineCodeBlockView(code: code, identifier: "\(entryID)-\(index)")
                case .rule:
                    Rectangle().fill(Theme.separator).frame(height: 1)
                        .padding(.vertical, 4)
                        .accessibilityHidden(true)
                }
            }
        }
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bodyText(_ text: AttributedString) -> some View {
        Text(text).font(.jost(.body)).lineSpacing(4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Items hang-indent past their marker, with 6pt between items.
    private func list(_ items: [AttributedString], marker: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(marker(index)).font(.jost(.body)).monospacedDigit()
                        .frame(minWidth: markerWidth, alignment: .trailing)
                        .accessibilityHidden(true)
                    bodyText(item)
                }
            }
        }
    }
}

/// A fenced code block: language and Copy on top, then the code on the card
/// colour, scrolling sideways instead of wrapping.
struct TimelineCodeBlockView: View {
    let code: TimelineCodeBlock
    let identifier: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsAll = false
    @State private var copied = false

    var body: some View {
        let dark = colorScheme == .dark
        let colors = TimelineCodeColors.colors(palette: TimelineCodeColors.palette(dark: dark), dark: dark, line: .context)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(verbatim: code.language ?? "Code")
                    .font(.jost(.caption)).foregroundStyle(Theme.textMuted).lineLimit(1)
                Spacer(minLength: 8)
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.jost(.caption, weight: .medium))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.text)
                .accessibilityLabel(copied ? "Copied" : "Copy code")
                .accessibilityIdentifier("timeline-code-copy-\(identifier)")
            }
            .padding(.leading, 12).padding(.trailing, 4)
            ScrollView(.horizontal) {
                Text(TimelineCodeHighlighter.highlight(code.inlineLines.joined(separator: "\n"), colors: colors))
                    .font(.system(.footnote, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.bottom, 12)
                    .accessibilityIdentifier("timeline-code-\(identifier)")
            }
            if code.removedHidden {
                Text("Hidden text-direction characters were removed.")
                    .font(.jost(.caption)).foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }
            if code.isShortened {
                Button("Show all \(code.lines.count) lines") { showsAll = true }
                    .font(.jost(.caption, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("timeline-code-all-\(identifier)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
        .sheet(isPresented: $showsAll) {
            TimelineCodeSheet(code: code, onClose: { showsAll = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
        }
    }

    private func copy() {
        UIPasteboard.general.string = code.text
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

/// Every line of a long code block, loaded lazily as it scrolls.
private struct TimelineCodeSheet: View {
    let code: TimelineCodeBlock
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let colors = TimelineCodeColors.colors(palette: TimelineCodeColors.palette(dark: dark), dark: dark, line: .context)
        NavigationStack {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(code.lines.enumerated()), id: \.offset) { _, line in
                        Text(TimelineCodeHighlighter.highlight(line.isEmpty ? " " : line, colors: colors))
                            .font(.system(.footnote, design: .monospaced))
                            .fixedSize(horizontal: true, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
            }
            .background(Theme.cardBackground)
            .navigationTitle(code.language ?? "Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .accessibilityLabel("Close").accessibilityIdentifier("timeline-code-close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Copy") { UIPasteboard.general.string = code.text }
                        .accessibilityLabel("Copy code")
                }
            }
        }
    }
}
