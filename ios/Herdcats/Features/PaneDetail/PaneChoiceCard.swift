import Observation
import SwiftUI

/// What happened to the last tap on a choice card. A result is matched to its
/// tap by a token, so a late result from an earlier tap can't overwrite a
/// newer one.
@MainActor
@Observable
final class PaneChoiceAnswerState {
    enum Phase: Equatable {
        case idle
        /// An answer for this option is on its way.
        case sending(option: Int)
        /// The answer went out for the prompt with this identity. The card
        /// stays hidden for it, and shows again for any other prompt.
        case sent(identity: [String])
    }

    static let sendingText = "Sending your answer…"
    static let changedText = "The question changed. Check the screen and try again."
    static let notSentText = "Nothing was sent. Check the screen and try again."
    static let uncertainText = "Couldn’t confirm your answer was sent. Check the screen."
    /// Taps this soon after the card changed are refused: a finger already
    /// on its way was aiming at what the card showed before.
    static let settleTime: TimeInterval = 0.5

    private(set) var phase: Phase = .idle
    /// A line about the last tap that didn't send: the question changed, or
    /// the answer may or may not have arrived. Kept until the next tap.
    private(set) var message: String?
    var collapsed = false
    private var token: UUID?
    private var identity: [String]?
    private var changedAt: TimeInterval = 0

    var isSending: Bool {
        if case .sending = phase { return true }
        return false
    }

    /// The status line under the options.
    var statusText: String? {
        isSending ? Self.sendingText : message
    }

    /// Call whenever the detected prompt changes. A different prompt, even
    /// one with the same option labels, shows its card again.
    func sync(_ prompt: PaneChoicePrompt?, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let next = prompt?.identity
        guard next != identity else { return }
        identity = next
        changedAt = now
        if isSending { return }
        if prompt == nil {
            phase = .idle
            message = nil
            collapsed = false
        } else if case .sent = phase {
            phase = .idle
        }
    }

    func isHidden(for prompt: PaneChoicePrompt) -> Bool {
        if case let .sent(identity) = phase { return identity == prompt.identity }
        return false
    }

    /// Starts an answer to the prompt the card drew. Returns nil, and sends
    /// nothing, while another answer is on its way, or when the prompt now
    /// detected differs from the drawn one in any way, or changed moments ago.
    func begin(
        option: Int,
        drawn: PaneChoicePrompt,
        current: PaneChoicePrompt?,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> UUID? {
        guard !isSending else { return nil }
        guard current?.identity == drawn.identity else {
            message = Self.changedText
            return nil
        }
        // Just appeared or just changed: ignore the tap without a word.
        guard now - changedAt >= Self.settleTime else { return nil }
        let token = UUID()
        self.token = token
        phase = .sending(option: option)
        message = nil
        return token
    }

    func finish(token: UUID, result: PaneChoiceSendResult, identity: [String]) {
        guard token == self.token else { return }
        self.token = nil
        switch result {
        case .sent:
            phase = .sent(identity: identity)
        case .changed:
            phase = .idle
            message = Self.changedText
        case .notSent:
            phase = .idle
            message = Self.notSentText
        }
    }

    func fail(token: UUID, message: String) {
        guard token == self.token else { return }
        self.token = nil
        phase = .idle
        self.message = message
    }
}

/// Buttons for a numbered prompt at the bottom of the pane, shown above the
/// key row. A tap re-reads the screen and sends the option's digit or letter
/// only if the prompt is unchanged.
struct PaneChoiceCard: View {
    let prompt: PaneChoicePrompt
    let agent: String?
    let state: PaneChoiceAnswerState
    /// False while keys are queued, being sent or paused for a fresh read.
    let rowsEnabled: Bool
    /// Called with the prompt this card drew and the tapped option, so the
    /// answer is checked against what the user saw.
    let onAnswer: (PaneChoicePrompt, Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var freeTextOption: PaneChoicePrompt.Option? {
        prompt.options.first(where: \.isFreeText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if !state.collapsed {
                // Short lists take their own height; longer ones scroll.
                ViewThatFits(in: .vertical) {
                    optionList
                    ScrollView { optionList }
                        .scrollBounceBehavior(.basedOnSize)
                }
                .frame(maxHeight: maxListHeight)
                if let freeTextOption {
                    Text("For “\(freeTextOption.label)”, use ↓ and type.")
                        .font(.jost(.caption))
                        .foregroundStyle(Theme.textMuted)
                }
                if let status = state.statusText {
                    Text(status)
                        .font(.jost(.caption))
                        .foregroundStyle(state.isSending ? Theme.textMuted : Theme.warning)
                        .lineLimit(2)
                        .accessibilityIdentifier("pane-choice-status")
                }
            }
        }
        .padding(10)
        .modifier(PaneInputGlassSurface(cornerRadius: DesignSystem.CornerRadius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane-choice-card")
    }

    private var optionList: some View {
        VStack(spacing: 4) {
            ForEach(prompt.options, id: \.number) { option in
                optionRow(option)
            }
        }
    }

    /// About four rows; larger text gets a little more room.
    private var maxListHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 260 : 184
    }

    private var header: some View {
        HStack(spacing: 8) {
            NeedsAnswerHeader()
            if state.collapsed {
                Text("\(prompt.options.count) choices")
                    .font(.jost(.caption))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
            Button {
                state.collapsed.toggle()
            } label: {
                Image(systemName: state.collapsed ? "chevron.up" : "chevron.down")
                    .font(.jost(13, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.collapsed ? "Show choices" : "Hide choices")
            .accessibilityIdentifier("pane-choice-collapse")
        }
    }

    @ViewBuilder
    private func optionRow(_ option: PaneChoicePrompt.Option) -> some View {
        let key = prompt.answerKey(option: option.number, agent: agent)
        let isHighlighted = option.number == prompt.highlighted
        let isSendingThis = state.phase == .sending(option: option.number)
        Button {
            HapticFeedback.impact(.light)
            onAnswer(prompt, option.number)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(option.shortcut.map { $0 == "esc" ? "Esc" : $0 } ?? String(option.number))
                    .font(.jost(.subheadline, weight: .semibold).monospaced())
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.jost(.subheadline))
                        .foregroundStyle(Theme.text)
                        .lineLimit(3)
                    if let detail = option.detail {
                        Text(detail)
                            .font(.jost(.caption))
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if isSendingThis {
                    CircularArcSpinner(size: 15)
                } else if option.checked == true {
                    Image(systemName: "checkmark")
                        .font(.jost(13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .overlay {
                // The row the agent has selected right now.
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(key == nil || !rowsEnabled || state.isSending)
        .opacity(key == nil ? 0.55 : 1)
        .accessibilityLabel(accessibilityLabel(for: option, isHighlighted: isHighlighted))
        .accessibilityHint(key.map(PaneChoicePrompt.accessibilityHint(forKey:)) ?? "")
        .accessibilityIdentifier("pane-choice-option-\(option.number)")
    }

    private func accessibilityLabel(for option: PaneChoicePrompt.Option, isHighlighted: Bool) -> String {
        var parts = ["\(option.number). \(option.label)"]
        if let detail = option.detail { parts.append(detail) }
        if option.checked == true { parts.append("Checked") }
        if option.checked == false { parts.append("Not checked") }
        if isHighlighted { parts.append("Selected on screen") }
        return parts.joined(separator: ", ")
    }
}
