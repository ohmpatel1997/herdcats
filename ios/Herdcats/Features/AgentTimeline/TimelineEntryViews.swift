import Foundation
import ImageIO
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Timeline markdown

/// Parses agent-authored inline markdown and drops any link that could be used
/// to launch other apps (`shortcuts://`, `tel:`, `sms:`, custom deep links) or to
/// disguise its destination behind a URL-looking label.
enum TimelineMarkdown {
    static func sanitized(_ text: String) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        // Bidi controls in unlinked text can reorder a neighboring link too.
        // Remove them across the rendered string; preserve ordinary whitespace
        // and joiners outside links. Capture ranges before replacing in reverse.
        let runs = attributed.runs.map {
            (range: $0.range, attributes: $0.attributes, linked: $0.link != nil)
        }
        for run in runs.reversed() {
            let original = String(attributed[run.range].characters)
            let cleaned = run.linked ? droppingInvisibleCharacters(original)
                : String(original.unicodeScalars.filter { !$0.properties.isBidiControl })
            guard cleaned != original else { continue }
            attributed.replaceSubrange(
                run.range, with: AttributedString(cleaned, attributes: run.attributes))
        }
        // Inline styling (`**bold**`, `_em_`, `code`) splits one link into several runs
        // that share the same URL. Coalesce adjacent runs so the complete visible label
        // is validated, not each styled fragment on its own.
        var unsafeRanges: [Range<AttributedString.Index>] = []
        var group: (url: URL, range: Range<AttributedString.Index>)?
        func flush() {
            guard let current = group else { return }
            let label = String(attributed[current.range].characters)
            if !isSafe(current.url, label: label) { unsafeRanges.append(current.range) }
            group = nil
        }
        for run in attributed.runs {
            guard let url = run.link else { flush(); continue }
            if let current = group, current.url == url {
                group = (url, current.range.lowerBound..<run.range.upperBound)
            } else {
                flush()
                group = (url, run.range)
            }
        }
        flush()
        for range in unsafeRanges { attributed[range].link = nil }
        return attributed
    }

    /// Your own messages: the same sanitizing, then an underline on every
    /// link that survives it. Inside your bubble links take the text colour,
    /// which is readable on the bubble in every palette, so the underline is
    /// what marks them as links.
    static func bubbleStyled(_ text: String) -> AttributedString {
        var attributed = sanitized(text)
        let linked = attributed.runs.filter { $0.link != nil }.map(\.range)
        for range in linked {
            attributed[range][AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = .single
            attributed[range][AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Theme.text
        }
        return attributed
    }

    /// One VoiceOver action per link in an already-sanitized string, named by
    /// the link's host ("Open link: example.com"). Your bubble reads as one
    /// element, so these actions are how links inside it stay reachable.
    static func linkActions(_ attributed: AttributedString) -> [TimelineLinkAction] {
        var actions: [TimelineLinkAction] = []
        var seen: Set<URL> = []
        for run in attributed.runs {
            guard let url = run.link, seen.insert(url).inserted else { continue }
            // Name by host; add the path, then the whole address, only when
            // an earlier link already took the shorter name.
            let host = url.host?.lowercased() ?? url.absoluteString
            var name = "Open link: \(host)"
            if actions.contains(where: { $0.name == name }) { name = "Open link: \(host)\(url.path)" }
            if actions.contains(where: { $0.name == name }) { name = "Open link: \(url.absoluteString)" }
            actions.append(TimelineLinkAction(name: name, url: url))
        }
        return actions
    }

    private static func isSafe(_ url: URL, label: String) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        let visible = visibleText(of: label)
        let lowered = visible.lowercased()
        guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || hasSchemeAndHost(visible) else {
            return true
        }
        // The label presents itself as a URL: it must point at the same host.
        guard let labelHost = URL(string: visible)?.host?.lowercased(), !labelHost.isEmpty else { return false }
        return labelHost == host
    }

    /// The label as a reader perceives it: invisible Unicode format characters
    /// (zero-width joiners/non-joiners, bidi marks, BOM, ...), other default-
    /// ignorable scalars (variation selectors, combining grapheme joiner, ...),
    /// and control characters are dropped so they cannot hide a URL-looking
    /// label from the check.
    private static func visibleText(of label: String) -> String {
        droppingInvisibleCharacters(label).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops every scalar that never renders visibly: format and control
    /// characters, bidi overrides/isolates, and other default-ignorable code
    /// points (variation selectors, combining grapheme joiner, ...).
    private static func droppingInvisibleCharacters(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            // Braille blank renders as empty space but is neither whitespace
            // nor default-ignorable, and can conceal a URL prefix.
            if scalar.value == 0x2800 || scalar.properties.isDefaultIgnorableCodePoint { continue }
            switch scalar.properties.generalCategory {
            case .format, .control: continue
            default: scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    private static func hasSchemeAndHost(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty,
              let host = url.host, !host.isEmpty else { return false }
        return true
    }
}

struct TimelineLinkAction: Equatable {
    let name: String
    let url: URL
}

// MARK: - Agent timeline entry view

struct AgentTimelineEntryView: View {
    let entry: AgentTimelineEntry
    let files: TimelineContentFiles
    let scope: String
    let loadContent: @MainActor (String) async throws -> Data
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @State private var thumbnail: UIImage?
    @State private var originalURL: URL?
    @State private var previewURL: URL?
    @State private var imageLink: URL?
    @State private var imageError: String?

    /// Your bubble never grows wider than this, even on iPad.
    static let bubbleMaxWidth: CGFloat = 560
    /// The bubble's corners: rounded, with a tighter corner on the side it
    /// was sent from. The corners mirror in right-to-left layouts.
    static let bubbleShape = UnevenRoundedRectangle(
        cornerRadii: .init(topLeading: 16, bottomLeading: 16, bottomTrailing: 6, topTrailing: 16),
        style: .continuous)

    /// Space kept clear on the leading side of your bubble. It shrinks at
    /// accessibility text sizes so the bubble still fits a few words a line.
    static func bubbleLeadingGap(isAccessibilitySize: Bool) -> CGFloat {
        isAccessibilitySize ? 16 : 48
    }

    var body: some View {
        Group {
            switch TimelineTurnLayout.role(entry: entry) {
            case .user: userLayout
            case .notice: noticeLayout
            case .agent, .activity: agentLayout
            }
        }
        .task(id: entry.contentRef) { if entry.kind == "image" { await loadImage() } }
        .onDisappear { thumbnail = nil }
        .quickLookPreview($previewURL)
    }

    // MARK: Your messages

    /// A bubble on the trailing side that hugs its text. It is offered the
    /// column width minus the leading gap, up to `bubbleMaxWidth`; padding
    /// and frames give that exactly, where a Spacer in an HStack would share
    /// the width and could wrap a long message early.
    private var userLayout: some View {
        VStack(alignment: .trailing, spacing: 4) {
            bubble
            if entry.truncated {
                Text("Preview shortened.")
                    .font(.jost(.caption)).foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: Self.bubbleMaxWidth, alignment: .trailing)
        .padding(.leading, Self.bubbleLeadingGap(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder private var bubble: some View {
        if entry.kind == "image" {
            // The image button keeps its own label and identifier; the group
            // is named "You" so VoiceOver still says who sent it.
            VStack(alignment: .trailing, spacing: 8) { imageContent }
                .modifier(UserBubbleFill())
                .accessibilityElement(children: .contain)
                .accessibilityLabel("You")
                .accessibilityIdentifier("timeline-message-\(entry.id)")
        } else {
            let text = bubbleMarkdown
            Text(text)
                .font(.jost(.body)).lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(UserBubbleFill())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("You")
                .accessibilityValue(String(text.characters))
                .accessibilityIdentifier("timeline-message-\(entry.id)")
                .accessibilityActions {
                    ForEach(TimelineMarkdown.linkActions(text), id: \.url) { action in
                        Button(action.name) { openURL(action.url) }
                    }
                }
        }
    }

    // MARK: The agent's messages

    /// Open text across the column, with no fill.
    private var agentLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            if entry.kind == "image" {
                imageContent
            } else {
                Text(markdown).font(.jost(.body)).lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("timeline-message-\(entry.id)")
            }
            if entry.truncated {
                Text("Preview shortened.")
                    .font(.jost(.caption)).foregroundStyle(Theme.textMuted)
            }
        }
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Notices

    @ViewBuilder private var noticeLayout: some View {
        if entry.kind == "record" {
            // Leading, like the record details under it.
            VStack(alignment: .leading, spacing: 6) {
                TimelineNotice("Unsupported content: \(entry.text)", systemImage: "questionmark.square.dashed",
                    alignment: .leading)
                if let details = entry.details {
                    Text(details).font(.jost(.caption)).foregroundStyle(Theme.textMuted)
                        .textSelection(.enabled).lineLimit(8)
                        .accessibilityIdentifier("timeline-record-\(entry.id)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TimelineNotice(entry.text, systemImage: "stop.circle")
                .accessibilityIdentifier("timeline-interrupted-\(entry.id)")
        }
    }

    /// Muted text is too faint on your bubble in some palettes, so captions
    /// inside it use the text colour.
    private var captionColor: Color { isYours ? Theme.text : Theme.textMuted }
    private var isYours: Bool { TimelineTurnLayout.role(entry: entry) == .user }

    @ViewBuilder private var imageContent: some View {
        if let thumbnail {
            Button { previewURL = originalURL } label: {
                Image(uiImage: thumbnail).resizable().scaledToFit().frame(maxHeight: 320)
                    // The bubble's "You" isn't always spoken inside a group,
                    // so the image itself says who sent it.
                    .accessibilityLabel(isYours ? "Image you sent" : "Session image")
                    .accessibilityIdentifier("timeline-image-\(entry.id)")
            }.buttonStyle(.plain)
            Text("Tap to open original").font(.jost(.caption)).foregroundStyle(captionColor)
        } else if let imageLink {
            Label("Image link", systemImage: "photo")
            Text(imageLink.absoluteString).font(.jost(.caption)).textSelection(.enabled)
            Link("Open image", destination: imageLink)
        } else if let imageError {
            Label("Image", systemImage: "photo")
            Text(imageError).font(.jost(.caption)).foregroundStyle(captionColor)
            Button("Retry") { Task { await loadImage() } }
        } else {
            ProgressView { Text("Loading image…").foregroundStyle(captionColor) }
        }
    }
    @MainActor private func loadImage() async {
        guard let reference = entry.contentRef else { imageError = "Image reference is unavailable."; return }
        imageError = nil
        do {
            let data = try await loadContent(reference)
            let decoded = try await Task.detached(priority: .userInitiated) { try TimelineImagePayload.decode(data) }.value
            try Task.checkCancellation()
            switch decoded {
            case .image(let preview, let original, let suffix):
                originalURL = try await files.file(data: original, key: "\(scope):\(reference):image", name: "Session image.\(suffix)")
                thumbnail = UIImage(data: preview)
                if thumbnail == nil { throw AgentBridgeError.invalidFrame }
            case .link(let url): imageLink = url
            }
        } catch {
            if !Task.isCancelled { imageError = "This image could not be displayed. Try loading it again." }
        }
    }
    private var markdown: AttributedString { Self.sanitizedMarkdown(entry.text) }
    private var bubbleMarkdown: AttributedString { TimelineMarkdown.bubbleStyled(entry.text) }
    static func sanitizedMarkdown(_ text: String) -> AttributedString { TimelineMarkdown.sanitized(text) }
}

/// The fill and shape of your bubble. Links inside take the text colour.
private struct UserBubbleFill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Theme.text)
            .tint(Theme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.userBubble, in: AgentTimelineEntryView.bubbleShape)
    }
}

// MARK: - Timeline history scroll anchor & preference keys

struct TimelineHistoryScrollAnchor: Equatable {
    let token = UUID()
    let id: String
    let top: CGFloat
    let height: CGFloat
    let viewportHeight: CGFloat
    var unitY: CGFloat {
        let available = viewportHeight - height
        return abs(available) > 1 ? top / available : 0
    }
}

struct TimelineEntryFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct TimelineAtBottomPreferenceKey: PreferenceKey {
    static var defaultValue: Bool { true }
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value && nextValue() }
}

// MARK: - Timeline content files cache

@MainActor final class TimelineContentFiles {
    private let cache = NSCache<NSString, NSData>()
    private let ioQueue = DispatchQueue(label: "com.enchantinglabs.herdcats.timeline-files", qos: .userInitiated)
    private var directory = FileManager.default.temporaryDirectory.appendingPathComponent("timeline-" + UUID().uuidString)
    private var files: [String: URL] = [:]
    init() { cache.totalCostLimit = 32 * 1024 * 1024 }
    func data(key: String, load: @MainActor () async throws -> Data) async throws -> Data {
        try Task.checkCancellation()
        if let bytes = cache.object(forKey: key as NSString) { return bytes as Data }
        let directory = directory
        let bytes = try await load()
        try Task.checkCancellation()
        guard self.directory == directory else { throw CancellationError() }
        cache.setObject(bytes as NSData, forKey: key as NSString, cost: bytes.count)
        return bytes
    }
    func file(data: Data, key: String, name: String) async throws -> URL {
        try Task.checkCancellation()
        let directory = directory
        let cachedFile = files[key]
        let url: URL = try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                if let cachedFile, FileManager.default.fileExists(atPath: cachedFile.path) {
                    continuation.resume(returning: cachedFile)
                    return
                }
                let folder = directory.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let url = folder.appendingPathComponent(name)
                    try data.write(to: url, options: [.atomic, .completeFileProtection])
                    continuation.resume(returning: url)
                } catch {
                    try? FileManager.default.removeItem(at: folder)
                    continuation.resume(throwing: error)
                }
            }
        }
        try Task.checkCancellation()
        guard self.directory == directory else { throw CancellationError() }
        files[key] = url
        return url
    }
    func reset() {
        cache.removeAllObjects()
        files.removeAll()
        let retiredDirectory = directory
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("timeline-" + UUID().uuidString)
        // Serialize cleanup after pending writes; a new session has its own directory.
        ioQueue.async { try? FileManager.default.removeItem(at: retiredDirectory) }
    }
    deinit {
        let directory = directory
        ioQueue.async { try? FileManager.default.removeItem(at: directory) }
    }
}

// MARK: - Timeline image payload

enum TimelineImagePayload: Sendable {
    case image(preview: Data, original: Data, suffix: String)
    case link(URL)
    nonisolated static func decode(_ data: Data) throws -> Self {
        guard let block = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let source = block["source"] as? [String: Any] else { throw AgentBridgeError.invalidFrame }
        if let raw = source["url"] as? String, let url = URL(string: raw),
           ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return .link(url) }
        guard let encoded = source["data"] as? String, let original = Data(base64Encoded: encoded),
              let image = CGImageSourceCreateWithData(original as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 200_000_000,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(image, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw AgentBridgeError.invalidFrame }
        let preview = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(preview, UTType.png.identifier as CFString, 1, nil) else { throw AgentBridgeError.invalidFrame }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { throw AgentBridgeError.invalidFrame }
        let identifier = CGImageSourceGetType(image).map { $0 as String } ?? UTType.data.identifier
        let suffix = UTType(identifier)?.preferredFilenameExtension ?? "image"
        return .image(preview: preview as Data, original: original, suffix: suffix)
    }
}
