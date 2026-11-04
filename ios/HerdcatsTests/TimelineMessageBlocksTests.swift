import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Herdcats

/// Headings, lists, quotes and fenced code in agent messages.
@Suite("Timeline message blocks")
struct TimelineMessageBlocksTests {
    private func links(_ text: AttributedString) -> [URL] { text.runs.compactMap(\.link) }

    @Test func plainTextIsOneUnchangedParagraph() {
        for text in ["Hello **world**.", "First line\nsecond line\n\n\nAfter blank lines\n",
                     "#hashtag is not a heading", "Use `let` here.", ""] {
            #expect(TimelineMessageBlock.parse(text) == [.paragraph(text)], "\(text)")
        }
        // A numbered line only starts a list mid-paragraph when it starts at 1.
        let sentence = "We shipped it in\n2024. That year it grew."
        #expect(TimelineMessageBlock.parse(sentence) == [.paragraph(sentence)])
    }

    @Test func fencedCodeKeepsTextAndLanguage() {
        let blocks = TimelineMessageBlock.parse("Before\n\n```swift title\nlet a = 1\n    indented\n```\nAfter")
        #expect(blocks == [
            .paragraph("Before"),
            .code(language: "swift", text: "let a = 1\n    indented", removedHidden: false),
            .paragraph("After"),
        ])
        // The fence's own indent is removed from its lines.
        #expect(TimelineMessageBlock.parse("  ```\n  a\n    b\n  ```")
                == [.code(language: nil, text: "a\n  b", removedHidden: false)])
    }

    @Test func tildeAndLongerFencesCloseCorrectly() {
        #expect(TimelineMessageBlock.parse("~~~\ncode ``` inside\n~~~")
                == [.code(language: nil, text: "code ``` inside", removedHidden: false)])
        // A shorter fence inside a longer one is code.
        #expect(TimelineMessageBlock.parse("````md\n```\nstill code\n````")
                == [.code(language: "md", text: "```\nstill code", removedHidden: false)])
        // The other marker never closes the fence.
        #expect(TimelineMessageBlock.parse("```\nx\n~~~\n```")
                == [.code(language: nil, text: "x\n~~~", removedHidden: false)])
        // A closing fence takes nothing after it.
        #expect(TimelineMessageBlock.parse("```\nx\n``` not closed\n```")
                == [.code(language: nil, text: "x\n``` not closed", removedHidden: false)])
    }

    @Test func unterminatedFenceRunsToTheEnd() {
        #expect(TimelineMessageBlock.parse("Intro\n```js\nconst a = 1\n\nconst b = 2") == [
            .paragraph("Intro"),
            .code(language: "js", text: "const a = 1\n\nconst b = 2", removedHidden: false),
        ])
    }

    @Test func headingsListsQuotesAndRulesParse() {
        let text = """
            # Title
            ### Smaller ###
            Intro line
            continued.

            - one
            * two
              wrapped
            + three
                - nested stays text

            3. third
            4) fourth

            > quoted
            > more
            ---
            * * *
            """
        #expect(TimelineMessageBlock.parse(text) == [
            .heading(level: 1, text: "Title"),
            .heading(level: 3, text: "Smaller"),
            .paragraph("Intro line\ncontinued."),
            .bullets(["one", "two\nwrapped", "three\n- nested stays text"]),
            .numbered(start: 3, items: ["third", "fourth"]),
            .quote("quoted\nmore"),
            .rule,
            .rule,
        ])
        #expect(TimelineMessageBlock.parse("# C#") == [.heading(level: 1, text: "C#")])
        #expect(TimelineMessageBlock.parse("####### seven") == [.paragraph("####### seven")])
        // A bare "#" stays text, not an empty heading.
        #expect(TimelineMessageBlock.parse("#\n\n- a") == [.paragraph("#"), .bullets(["a"])])
    }

    @Test func numberedStepsSeparatedByTextKeepTheirNumbers() {
        // Agents often explain each step between the steps.
        #expect(TimelineMessageBlock.parse(
            "1. Install the app\n\nThis installs the bridge.\n\n2. Configure it\n\nThis writes the config.\n\n3. Run it") == [
            .numbered(start: 1, items: ["Install the app"]),
            .paragraph("This installs the bridge."),
            .numbered(start: 2, items: ["Configure it"]),
            .paragraph("This writes the config."),
            .numbered(start: 3, items: ["Run it"]),
        ])
        #expect(TimelineMessageBlock.parse("Done so far:\n\n3. Run tests\n4. Deploy")
                == [.paragraph("Done so far:"), .numbered(start: 3, items: ["Run tests", "Deploy"])])
        // Text right under an item, with no blank line, continues that item.
        #expect(TimelineMessageBlock.parse("1. a\ntext\n2. b") == [.numbered(start: 1, items: ["a\ntext", "b"])])
    }

    @Test func aFenceAfterANumberedItemKeepsTheListGoing() {
        let expected: [TimelineMessageBlock] = [
            .numbered(start: 1, items: ["Build:"]),
            .code(language: "sh", text: "make", removedHidden: false),
            .numbered(start: 2, items: ["Run"]),
        ]
        #expect(TimelineMessageBlock.parse("1. Build:\n```sh\nmake\n```\n2. Run") == expected)
        #expect(TimelineMessageBlock.parse("1. Build:\n   ```sh\n   make\n   ```\n2. Run") == expected)
        // Indented to the item's text, even after a blank line.
        #expect(TimelineMessageBlock.parse("1. Build:\n\n    ```sh\n    make\n    ```\n2. Run") == expected)
        // The same indent with no list above is not a fence.
        let indented = "Text\n\n    ```sh\n    make\n    ```"
        #expect(TimelineMessageBlock.parse(indented) == [.paragraph(indented)])
    }

    @Test func codeLanguageLabelsAreCleanedAndCapped() {
        #expect(TimelineMessageBlock.parse("```sw\u{202E}ift\nx\n```")
                == [.code(language: "swift", text: "x", removedHidden: false)])
        let long = String(repeating: "a", count: 80)
        #expect(TimelineMessageBlock.parse("```\(long)\nx\n```")
                == [.code(language: String(repeating: "a", count: 40), text: "x", removedHidden: false)])
    }

    @Test func codeBlocksNeverProduceLinks() {
        let rendered = TimelineMessageBlocks.render("```\n[x](https://example.com) <https://example.com>\n```")
        #expect(rendered == [.code(TimelineCodeBlock(
            language: nil, text: "[x](https://example.com) <https://example.com>", removedHidden: false))])
        // Inline code inside a paragraph stays a code span, never a link.
        guard case .paragraph(let text) = TimelineMessageBlocks.render("Run `https://example.com` now.\n\n# H")[0] else {
            Issue.record("Expected a paragraph"); return
        }
        #expect(links(text).isEmpty)
    }

    @Test func unsafeLinksInsideListItemsAreStillStripped() {
        let rendered = TimelineMessageBlocks.render("""
            - [tap me](tel:+15555550100)
            - [docs](https://example.com/docs)
            - [https://apple.com](https://evil.example)

            1. [run](shortcuts://run-shortcut?name=x)

            > [open](myapp://deep/link)

            ## [heading](javascript:alert(1))
            """)
        guard rendered.count == 4,
              case .bullets(let bullets) = rendered[0], case .numbered(_, let numbered) = rendered[1],
              case .quote(let quote) = rendered[2], case .heading(_, let heading) = rendered[3] else {
            Issue.record("Unexpected blocks: \(rendered)"); return
        }
        #expect(links(bullets[0]).isEmpty)
        #expect(links(bullets[1]) == [URL(string: "https://example.com/docs")!])
        #expect(links(bullets[2]).isEmpty)
        #expect(String(bullets[0].characters) == "tap me")
        #expect(links(numbered[0]).isEmpty)
        #expect(links(quote).isEmpty)
        #expect(links(heading).isEmpty)
    }

    @Test func codeBlocksStripBidiControlsLikeOtherText() {
        let blocks = TimelineMessageBlock.parse("```\nlet a = \u{202E}1 // b\n```")
        #expect(blocks == [.code(language: nil, text: "let a = 1 // b", removedHidden: true)])
        guard case .code(let code) = TimelineMessageBlocks.render("```\nlet a = \u{202E}1 // b\n```")[0] else {
            Issue.record("Expected code"); return
        }
        // What is shown and what Copy copies are the same, with no bidi scalars.
        #expect(!code.text.unicodeScalars.contains { $0.properties.isBidiControl })
        #expect(!code.inlineLines.joined().unicodeScalars.contains { $0.properties.isBidiControl })
        #expect(code.removedHidden)
        #expect(TimelineMessageBlock.parse("```\nlet a = 1\n```")
                == [.code(language: nil, text: "let a = 1", removedHidden: false)])
        let isolates = TimelineMarkdown.displayCode("a\u{2066}b\u{2069}c\u{200F}d")
        #expect(isolates.text == "abcd")
        #expect(isolates.removedHidden)
    }

    @Test func longCodeLinesAreCappedInline() {
        let long = String(repeating: "x", count: 600)
        let lines = [long] + (1...44).map { "line \($0)" }
        let code = TimelineCodeBlock(language: nil, text: lines.joined(separator: "\n"), removedHidden: false)
        #expect(code.lines.count == 45)
        #expect(code.lines[0].count == 600)
        #expect(code.inlineLines.count == TimelineCodeBlock.inlineLineLimit)
        #expect(code.inlineLines[0].count == 501)
        #expect(code.inlineLines[0].hasSuffix("…"))
        #expect(code.isShortened)
        #expect(code.needsSheet)
        #expect(code.sheetLines[0].count == 600)
        let short = TimelineCodeBlock(language: nil, text: "a\nb", removedHidden: false)
        #expect(!short.isShortened)
        #expect(!short.needsSheet)
        // A short block with one long line still offers the sheet.
        let wide = TimelineCodeBlock(language: nil, text: "a\n" + long, removedHidden: false)
        #expect(!wide.isShortened)
        #expect(wide.needsSheet)
        // A minified line is cut in the sheet too; Copy keeps it whole.
        let minified = String(repeating: "x", count: 50_000)
        let huge = TimelineCodeBlock(language: nil, text: minified, removedHidden: false)
        #expect(huge.sheetCutsLines)
        #expect(huge.sheetLines[0].count == TimelineCodeBlock.sheetCharacterLimit + 1)
        #expect(huge.text.count == 50_000)
        #expect(!wide.sheetCutsLines)
    }

    @Test func hugeMessagesSkipBlockParsing() {
        let huge = "# Heading\n" + String(repeating: "word ", count: TimelineMessageBlocks.maxParsedBytes / 5 + 10)
        #expect(TimelineMessageBlocks.render(huge).count == 1)
        guard case .paragraph = TimelineMessageBlocks.render(huge)[0] else {
            Issue.record("Expected one paragraph"); return
        }
    }

    /// One long paragraph, quote or fence: doubling it must roughly double
    /// the time. A parser that rebuilds the block on every line would take
    /// about four times as long; the 3× bound leaves room for runner noise.
    @Test func longSingleBlocksParseInLinearTime() {
        func block(_ shape: String, _ count: Int) -> String {
            let lines = (1...count).map { "line \($0) of a long agent log that keeps going" }
            switch shape {
            case "quote": return lines.map { "> " + $0 }.joined(separator: "\n")
            case "fence": return "```\n" + lines.joined(separator: "\n") + "\n```"
            default: return lines.joined(separator: "\n")
            }
        }
        func fastest(_ text: String) -> Duration {
            (0..<3).map { _ in ContinuousClock().measure { _ = TimelineMessageBlock.parse(text) } }.min()!
        }
        for shape in ["paragraph", "quote", "fence"] {
            let small = block(shape, 10_000), large = block(shape, 20_000)
            let parsed = TimelineMessageBlock.parse(large)
            #expect(parsed.count == 1, "\(shape)")
            _ = fastest(small)
            let ratio = fastest(large) / fastest(small)
            #expect(ratio < 3, "\(shape): 20,000 lines took \(ratio)× as long as 10,000")
        }
    }

    @Test func parsingScalesToLongMessages() {
        // 20,000 lines of mixed blocks parse in one pass.
        let chunk = "## Step\n- item\n1. first\n> note\n```\ncode\n```\nText line\n\n"
        let text = String(repeating: chunk, count: 2_000)
        let blocks = TimelineMessageBlock.parse(text)
        #expect(blocks.count == 2_000 * 6)
    }

    @Test func everyCodeForegroundMeetsAAInAll8Combinations() {
        let support = ContrastTestSupport.self
        #expect(support.combinations.count == 8)
        for (palette, dark) in support.combinations {
            for line in [TimelineCodeColors.Line.context, .added, .removed] {
                let background = TimelineCodeColors.background(line, palette: palette, dark: dark)
                let colors = TimelineCodeColors.colors(palette: palette, dark: dark, line: line)
                let foregrounds: [(String, UInt32)] = [
                    ("text", colors.text), ("comment", colors.comment), ("keyword", colors.keyword),
                    ("number", colors.number), ("string", colors.string),
                    ("added marker", colors.added), ("removed marker", colors.removed),
                ]
                for (name, hex) in foregrounds {
                    let ratio = support.ratio(UIColor(hex: hex), over: UIColor(hex: background))
                    #expect(ratio >= 4.5, "\(support.name(palette, dark: dark)) \(line) \(name): \(ratio)")
                }
            }
        }
        // The adjuster really runs: Solarized Dark's text is 4.00:1 on the
        // green wash before adjusting.
        let wash = TimelineCodeColors.background(.added, palette: .solarizedDark, dark: true)
        let raw = TimelineCodeColors.hex(Theme.uiColor("text", palette: .solarizedDark, dark: true), over: wash)
        #expect(support.ratio(UIColor(hex: raw), over: UIColor(hex: wash)) < 4.5)
        #expect(TimelineCodeColors.colors(palette: .solarizedDark, dark: true, line: .added).text != raw)
    }

    @Test func codeSitsOnTheCardColour() {
        for (palette, dark) in ContrastTestSupport.combinations {
            let card = TimelineCodeColors.hex(Theme.uiColor("card", palette: palette, dark: dark), over: 0)
            #expect(TimelineCodeColors.background(.context, palette: palette, dark: dark) == card)
            #expect(TimelineCodeColors.background(.added, palette: palette, dark: dark) != card)
            #expect(TimelineCodeColors.background(.removed, palette: palette, dark: dark) != card)
        }
    }
}

@Suite("Timeline block cache")
@MainActor struct TimelineBlockCacheTests {
    private func entry(_ id: String, _ text: String) -> AgentTimelineEntry {
        AgentTimelineEntry(id: id, kind: "message", text: text, role: "assistant", toolName: nil,
                           status: nil, details: nil, truncated: false)
    }

    @Test func parsesOncePerTextAndAgainWhenAnEntryIsRevised() {
        let cache = TimelineBlockCache()
        let first = cache.blocks(for: entry("a", "# One"))
        #expect(first == [.heading(level: 1, text: TimelineMarkdown.sanitized("One"))])
        #expect(cache.blocks(for: entry("a", "# One")) == first)
        // The same id with new text is a revision: it parses again.
        #expect(cache.blocks(for: entry("a", "# Two")) == [.heading(level: 1, text: TimelineMarkdown.sanitized("Two"))])
        cache.reset()
        #expect(cache.blocks(for: entry("a", "plain")) == [.paragraph(TimelineMarkdown.sanitized("plain"))])
        #expect(TimelineMessageBlocks.singleParagraph(cache.blocks(for: entry("b", "plain"))) != nil)
        #expect(TimelineMessageBlocks.singleParagraph(first) == nil)
    }
}
