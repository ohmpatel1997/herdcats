import Foundation
import SwiftUI

/// Converts terminal ANSI SGR sequences into styled lines for SwiftUI.
///
/// Supports reset/bold/dim/reverse, standard + bright colors, 256-color, and
/// truecolor (`38;2` / `48;2`). Non-SGR CSI/OSC sequences are stripped.
enum ANSIText {
    struct Line: Equatable {
        var plain: String
        var attributed: AttributedString
        /// Background of the line's first character as `#rrggbb`.
        /// Explicit RGB values stay intact for agents that mark user messages this way.
        var background: String? = nil

        static func == (lhs: Line, rhs: Line) -> Bool {
            lhs.plain == rhs.plain
                && String(lhs.attributed.characters) == String(rhs.attributed.characters)
        }
    }

    /// Splits ANSI text into lines, preserving per-run colors across the stream.
    ///
    /// Standard ANSI slots follow the supplied palette. Extended colors and
    /// explicit RGB values preserve the remote application's requested colors,
    /// with foreground-only contrast correction when needed in either appearance.
    static func lines(from ansi: String, palette: TerminalPalette = TerminalPalette(palette: .moonlit, dark: true)) -> [Line] {
        let normalized: String
        // Scalar check: Swift treats "\r\n" as one Character, so
        // `ansi.contains("\r")` misses CRLF rows and every row would merge
        // into a single line.
        if ansi.unicodeScalars.contains("\r") {
            normalized = ansi
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
        } else {
            normalized = ansi
        }

        var lines: [Line] = []
        var currentPlain = ""
        var currentAttributed = AttributedString()
        var currentBackground: String?
        var style = Style(palette: palette)
        var index = normalized.startIndex

        func commitLine() {
            lines.append(Line(plain: currentPlain, attributed: currentAttributed, background: currentBackground))
            currentPlain = ""
            currentAttributed = AttributedString()
            currentBackground = nil
        }

        func appendRun(_ text: String) {
            if currentPlain.isEmpty, !text.isEmpty { currentBackground = style.background?.hex }
            currentPlain += text
            var run = AttributedString(text)
            style.apply(to: &run)
            currentAttributed.append(run)
        }

        func appendChunk(_ chunk: Substring) {
            guard !chunk.isEmpty else { return }
            let parts = chunk.split(separator: "\n", omittingEmptySubsequences: false)
            for (idx, part) in parts.enumerated() {
                if idx > 0 {
                    commitLine()
                }
                if !part.isEmpty {
                    appendRun(String(part))
                }
            }
        }

        while index < normalized.endIndex {
            if normalized[index] == "\u{1B}" {
                let next = normalized.index(after: index)
                guard next < normalized.endIndex else { break }
                switch normalized[next] {
                case "[":
                    if let parsed = parseCSI(normalized, startingAt: next) {
                        if parsed.final == "m" {
                            style.apply(sgr: parsed.params)
                        }
                        index = parsed.end
                        continue
                    }
                    index = next
                case "]":
                    index = skipOSC(normalized, startingAt: next)
                case "(", ")", "*", "+", "-", ".", "/":
                    index = normalized.index(next, offsetBy: 1, limitedBy: normalized.endIndex)
                        ?? normalized.endIndex
                default:
                    index = next
                }
                continue
            }

            let end = normalized[index...].firstIndex(of: "\u{1B}") ?? normalized.endIndex
            appendChunk(normalized[index..<end])
            index = end
        }

        commitLine()
        return lines
    }

    // MARK: - CSI / OSC

    private struct CSI {
        var params: [Int]
        var final: Character
        var end: String.Index
    }

    private static func parseCSI(_ string: String, startingAt bracket: String.Index) -> CSI? {
        var idx = string.index(after: bracket)
        var paramBuffer = ""
        while idx < string.endIndex {
            let ch = string[idx]
            if ch.isASCII && (ch.isNumber || ch == ";" || ch == "?" || ch == ":" || ch == "<" || ch == "=" || ch == ">") {
                if ch.isNumber || ch == ";" || ch == ":" {
                    paramBuffer.append(ch)
                }
                idx = string.index(after: idx)
                continue
            }
            let scalar = ch.unicodeScalars.first?.value ?? 0
            guard (0x40...0x7E).contains(scalar) else { return nil }
            let params: [Int]
            if paramBuffer.isEmpty {
                params = [0]
            } else {
                params = paramBuffer
                    .split(separator: ";", omittingEmptySubsequences: false)
                    .map { Int($0.split(separator: ":").first ?? "0") ?? 0 }
            }
            return CSI(params: params, final: ch, end: string.index(after: idx))
        }
        return nil
    }

    private static func skipOSC(_ string: String, startingAt bracket: String.Index) -> String.Index {
        var idx = string.index(after: bracket)
        while idx < string.endIndex {
            let ch = string[idx]
            if ch == "\u{07}" {
                return string.index(after: idx)
            }
            if ch == "\u{1B}" {
                let next = string.index(after: idx)
                if next < string.endIndex, string[next] == "\\" {
                    return string.index(after: next)
                }
            }
            idx = string.index(after: idx)
        }
        return idx
    }

    // MARK: - Style

    private struct Style {
        let palette: TerminalPalette
        var bold = false
        var dim = false
        var reverse = false
        var foreground: RGBA?
        var background: RGBA?

        mutating func apply(sgr params: [Int]) {
            if params.isEmpty {
                reset()
                return
            }
            var i = 0
            while i < params.count {
                let code = params[i]
                switch code {
                case 0:
                    reset()
                case 1:
                    bold = true
                case 2:
                    dim = true
                case 22:
                    bold = false
                    dim = false
                case 7:
                    reverse = true
                case 27:
                    reverse = false
                case 39:
                    foreground = nil
                case 49:
                    background = nil
                case 30...37:
                    foreground = ansi16(code - 30)
                case 90...97:
                    foreground = ansi16(code - 90 + 8)
                case 40...47:
                    background = ansi16(code - 40)
                case 100...107:
                    background = ansi16(code - 100 + 8)
                case 38, 48:
                    let isForeground = code == 38
                    if i + 1 < params.count {
                        let mode = params[i + 1]
                        if mode == 5, i + 2 < params.count {
                            let index = min(max(params[i + 2], 0), 255)
                            let color = index < 16 ? ansi16(index) : RGBA.ansi256(index)
                            if isForeground { foreground = color } else { background = color }
                            i += 2
                        } else if mode == 2, i + 4 < params.count {
                            let color = RGBA(r: params[i + 2], g: params[i + 3], b: params[i + 4])
                            if isForeground { foreground = color } else { background = color }
                            i += 4
                        } else {
                            i += 1
                        }
                    }
                default:
                    break
                }
                i += 1
            }
        }

        mutating func reset() {
            bold = false
            dim = false
            reverse = false
            foreground = nil
            background = nil
        }

        private func ansi16(_ index: Int) -> RGBA {
            RGBA(hex: palette.colors[min(max(index, 0), 15)])
        }

        func apply(to attributed: inout AttributedString) {
            var fg = foreground ?? RGBA(hex: palette.foreground)
            var bg = background
            if reverse {
                let originalForeground = fg
                fg = bg ?? RGBA(hex: palette.background)
                bg = originalForeground
            }

            let backdrop = bg ?? RGBA(hex: palette.background)
            // Resolve dimming into an opaque color first: applying opacity
            // after contrast correction would make small text faint again.
            let displayed = dim ? fg.blended(toward: backdrop, fraction: 0.45) : fg
            attributed.foregroundColor = displayed.readable(on: backdrop).color
            if let color = bg?.color {
                attributed.backgroundColor = color
            }

            if bold {
                attributed.inlinePresentationIntent = .stronglyEmphasized
            }
        }
    }

    /// The terminal's AA adjuster for app code colours: returns `foreground`
    /// unchanged when it already reaches 4.5:1 on `background`, otherwise the
    /// smallest blend toward black or white that does.
    static func readableHex(_ foreground: UInt32, on background: UInt32) -> UInt32 {
        let adjusted = RGBA(hex: foreground).readable(on: RGBA(hex: background))
        return adjusted.hexValue
    }

    private struct RGBA: Equatable {
        var r: Int
        var g: Int
        var b: Int

        var color: Color {
            Color(
                red: Double(clamped(r)) / 255,
                green: Double(clamped(g)) / 255,
                blue: Double(clamped(b)) / 255
            )
        }

        var hex: String {
            String(format: "#%02x%02x%02x", clamped(r), clamped(g), clamped(b))
        }

        var hexValue: UInt32 {
            UInt32(clamped(r)) << 16 | UInt32(clamped(g)) << 8 | UInt32(clamped(b))
        }

        init(r: Int, g: Int, b: Int) {
            self.r = r
            self.g = g
            self.b = b
        }

        init(hex: UInt32) {
            r = Int((hex >> 16) & 0xFF)
            g = Int((hex >> 8) & 0xFF)
            b = Int(hex & 0xFF)
        }

        private var luminance: Double {
            func linear(_ channel: Int) -> Double {
                let c = Double(min(255, max(0, channel))) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }

        private func contrast(on background: RGBA) -> Double {
            let first = luminance, second = background.luminance
            return (max(first, second) + 0.05) / (min(first, second) + 0.05)
        }

        func blended(toward target: RGBA, fraction: Double) -> RGBA {
            func mix(_ source: Int, _ destination: Int) -> Int {
                Int((Double(clamped(source)) * (1 - fraction) + Double(destination) * fraction).rounded())
            }
            return RGBA(r: mix(r, target.r), g: mix(g, target.g), b: mix(b, target.b))
        }

        private static let readableCacheLock = NSLock()
        nonisolated(unsafe) private static var readableCache: [UInt64: RGBA] = [:]
        private static let maxReadableCacheEntries = 1024

        /// Keep colors that already pass AA. Otherwise find the smallest blend
        /// toward black/white that passes, preserving the original hue direction.
        /// Backgrounds and source metadata are never changed.
        func readable(on background: RGBA) -> RGBA {
            let key = (UInt64(clamped(r)) << 40)
                | (UInt64(clamped(g)) << 32)
                | (UInt64(clamped(b)) << 24)
                | (UInt64(clamped(background.r)) << 16)
                | (UInt64(clamped(background.g)) << 8)
                | UInt64(clamped(background.b))

            Self.readableCacheLock.lock()
            if let cached = Self.readableCache[key] {
                Self.readableCacheLock.unlock()
                return cached
            }
            Self.readableCacheLock.unlock()

            let computed = computeReadable(on: background)

            Self.readableCacheLock.lock()
            if Self.readableCache.count >= Self.maxReadableCacheEntries {
                Self.readableCache.removeAll(keepingCapacity: true)
            }
            Self.readableCache[key] = computed
            Self.readableCacheLock.unlock()

            return computed
        }

        private func computeReadable(on background: RGBA) -> RGBA {
            guard contrast(on: background) < 4.5 else { return self }
            let black = RGBA(r: 0, g: 0, b: 0)
            let white = RGBA(r: 255, g: 255, b: 255)
            let target = black.contrast(on: background) >= white.contrast(on: background) ? black : white
            var low = 0.0, high = 1.0
            var result = target
            for _ in 0..<12 {
                let fraction = (low + high) / 2
                let candidate = blended(toward: target, fraction: fraction)
                if candidate.contrast(on: background) >= 4.5 {
                    high = fraction
                    result = candidate
                } else {
                    low = fraction
                }
            }
            return result
        }

        private func clamped(_ value: Int) -> Int {
            min(255, max(0, value))
        }

        static func ansi256(_ index: Int) -> RGBA {
            let i = min(max(index, 0), 255)
            if i < 232 {
                let mapped = i - 16
                let r = mapped / 36
                let g = (mapped % 36) / 6
                let b = mapped % 6
                func level(_ v: Int) -> Int { v == 0 ? 0 : 55 + v * 40 }
                return RGBA(r: level(r), g: level(g), b: level(b))
            }
            let gray = 8 + (i - 232) * 10
            return RGBA(r: gray, g: gray, b: gray)
        }
    }
}
