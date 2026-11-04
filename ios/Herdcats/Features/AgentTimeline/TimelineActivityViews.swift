import SwiftUI
import UIKit

// MARK: - Timeline activity view

struct TimelineActivityView: View {
    let entries: [AgentTimelineEntry]
    let loadContent: @MainActor (String) async throws -> Data
    private struct PreviewKey: Equatable { let entries: [AgentTimelineEntry]; let retry: Int }
    @State private var previewRetry = 0
    @State private var previewFailed = false
    @State private var previewLoading = false
    @State private var showsDetails = false
    @State private var fileChanges: [TimelineFileChange] = []
    /// The icon column grows with the title at larger text sizes.
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 24
    private var failures: Int { entries.filter { $0.status == "failed" }.count }

    var body: some View {
        VStack(spacing: 12) {
            // A quiet summary row: muted text on a thin rail, so tool steps
            // read as part of the agent's turn rather than as replies.
            Button { showsDetails = true } label: {
                HStack(spacing: 10) {
                    Group {
                        if entries.contains(where: TimelineActivitySummary.isRunning) {
                            CircularArcSpinner(size: 15, color: Theme.statusWorking)
                        } else {
                            Image(systemName: failures > 0 ? "exclamationmark.circle" : "wrench.and.screwdriver")
                                .font(.jost(.subheadline))
                                .foregroundStyle(failures > 0 ? Theme.destructive : Theme.textMuted)
                        }
                    }
                    .frame(width: iconWidth)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TimelineActivitySummary.title(entries))
                            .font(.jost(.subheadline))
                        if failures > 0 {
                            Text("\(failures) failed or interrupted")
                                .font(.jost(.caption)).foregroundStyle(Theme.destructive)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.jost(.caption, weight: .medium))
                }
                .foregroundStyle(Theme.textMuted)
                .padding(.leading, 10)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(alignment: .leading) {
                    // Muted text at a third: faint, but visible in every palette,
                    // including Solarized Light, where the raised fill is the canvas.
                    Capsule().fill(Theme.textMuted.opacity(0.35)).frame(width: 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("timeline-tool-\(entries[0].id)")
            .sheet(isPresented: $showsDetails) {
                TimelineActivityDrawer(entries: entries)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(20)
            }
            ForEach(fileChanges) { change in
                TimelineDiffCard(change: change)
            }
            if previewLoading && fileChanges.isEmpty {
                Text("Loading code preview…").font(.jost(.caption)).foregroundStyle(Theme.textMuted)
            }
            if previewFailed {
                HStack {
                    Text("Some code previews couldn’t load.").foregroundStyle(Theme.textMuted)
                    Button("Retry") { previewRetry += 1 }.tint(Theme.accent)
                }.font(.jost(.caption))
            }
        }
        .task(id: PreviewKey(entries: entries, retry: previewRetry)) {
            let snapshot = entries
            var changes: [TimelineFileChange] = []
            var failed = false
            previewLoading = true
            defer { if !Task.isCancelled { previewLoading = false } }
            for entry in snapshot where entry.status == "completed" && ["edit", "multiedit", "write"].contains(entry.toolName?.lowercased() ?? "") {
                guard !Task.isCancelled else { return }
                let preview = await Task.detached(priority: .userInitiated) { TimelineFileChange.from(entry) }.value
                guard !Task.isCancelled else { return }
                if !preview.isEmpty { changes += preview; continue }
                guard entry.truncated else { continue }
                guard let reference = entry.contentRef, let length = TimelineContentReference.length(reference), length <= 512 * 1024 else {
                    failed = true
                    continue
                }
                do {
                    let input = try await loadContent(reference)
                    try Task.checkCancellation()
                    let complete = await Task.detached(priority: .userInitiated) { TimelineFileChange.from(entry, inputData: input) }.value
                    try Task.checkCancellation()
                    changes += complete
                    if complete.isEmpty { failed = true }
                } catch {
                    guard !Task.isCancelled else { return }
                    failed = true
                    TimelineHistoryDiagnostics.record("code.preview_failed reason=\(TimelineHistoryDiagnostics.reason(error))", failure: true)
                }
            }
            guard !Task.isCancelled else { return }
            fileChanges = changes
            previewFailed = failed
        }
    }
}

struct TimelineDiffCard: View {
    let change: TimelineFileChange
    @State private var showsDiff = false
    var body: some View {
        Button { showsDiff = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                TimelineDiffHeading(change: change)
                TimelineDiffCode(lines: Array(change.previewLines.prefix(12)))
                    .frame(maxHeight: 260)
            }
            .padding(14).foregroundStyle(Theme.text)
            .background(Theme.cardBackground)
            .overlay {
                Rectangle().strokeBorder(Theme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("timeline-diff-\(change.id)")
        .sheet(isPresented: $showsDiff) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TimelineDiffHeading(change: change)
                        TimelineDiffCode(lines: change.previewLines)
                    }.padding(16)
                }
                .background(Theme.background)
                .navigationTitle(change.writtenContent ? "Written content" : "Code changes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showsDiff = false } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close").accessibilityIdentifier("timeline-diff-close")
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
        }
    }
}

struct TimelineDiffHeading: View {
    let change: TimelineFileChange
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(change.displayPath).font(.jost(.subheadline, weight: .semibold)).lineLimit(2)
                Spacer()
                if !change.writtenContent {
                    Text("+\(change.additions)").foregroundStyle(Theme.successGreen)
                    Text("−\(change.deletions)").foregroundStyle(Theme.destructive)
                }
            }.font(.system(.caption, design: .monospaced, weight: .medium))
            if change.previewShortened {
                Text("Showing the first \(change.lines.count) lines").font(.jost(.caption2)).foregroundStyle(Theme.textMuted)
            }
        }
    }
}

struct TimelineDiffCode: View {
    let lines: [TimelineDiffLine]
    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text(line.kind == .added ? "+" : line.kind == .removed ? "−" : " ")
                            .frame(width: 14).foregroundStyle(tint(line))
                        Text(highlight(line.text, omitted: line.kind == .omitted))
                            .fixedSize(horizontal: true, vertical: true)
                        Spacer(minLength: 8)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint(line).opacity(line.kind == .context ? 0 : 0.13))
                }
            }
        }
        .background(Theme.subtleFill)
        .clipped()
    }
    private func tint(_ line: TimelineDiffLine) -> Color {
        switch line.kind {
        case .added: Theme.successGreen
        case .removed: Theme.destructive
        default: Theme.textMuted
        }
    }
    private static let highlightRules: [(NSRegularExpression, UIColor)] = [
        (try! NSRegularExpression(pattern: #"\b(let|var|const|func|function|return|if|else|for|while|class|struct|enum|import|from|true|false|null|nil|async|await|try|throw|public|private|static)\b"#), .systemPurple),
        (try! NSRegularExpression(pattern: #"\b[0-9]+(?:\.[0-9]+)?\b"#), .systemOrange),
        (try! NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'"#), .systemGreen),
        (try! NSRegularExpression(pattern: #"//.*$"#), .secondaryLabel)
    ]

    private func highlight(_ text: String, omitted: Bool) -> AttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.foregroundColor: UIColor(omitted ? Theme.textMuted : Theme.text)])
        guard !omitted else { return AttributedString(result) }
        let textRange = NSRange(text.startIndex..., in: text)
        for (expression, color) in Self.highlightRules {
            for match in expression.matches(in: text, range: textRange) {
                result.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
        return AttributedString(result)
    }
}

struct TimelineActivityDrawer: View {
    let entries: [AgentTimelineEntry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.jost(.body))
                                .foregroundStyle(entry.status == "failed" ? Theme.destructive : Theme.textMuted)
                                .accessibilityLabel(entry.status == "failed" ? "Failed or interrupted" : "Tool activity")
                                .accessibilityIdentifier("timeline-activity-icon-\(entry.id)")
                            Text(TimelineActivitySummary.purpose(entry))
                                .font(.jost(.body, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Theme.cardBackground, in: .rect(cornerRadius: DesignSystem.CornerRadius.lg))
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("timeline-activity-close")
                }
            }
        }
    }
}
