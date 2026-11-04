import SwiftUI

struct QuestionFieldTarget: Hashable {
    let scope: String
    let requestId: String
    let questionIndex: Int
}

struct QuestionFieldFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [QuestionFieldTarget: CGRect] { [:] }
    static func reduce(value: inout [QuestionFieldTarget: CGRect], nextValue: () -> [QuestionFieldTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct QuestionCard: View {
    let pending: AgentPendingQuestion
    let response: QuestionAnswerState
    let onSubmit: () -> Void
    let onSkip: () -> Void
    var scope: String = ""
    var onFieldFocus: (QuestionFieldTarget?) -> Void = { _ in }
    @State private var editingOther: Set<Int> = []
    @State private var focusOnInsertion: Int?
    @FocusState private var focusedQuestion: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NeedsAnswerHeader()
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: pending.questions.count == 1 ? pending.questions[0].text : "\(pending.questions.count) questions")
                    .font(.jost(.title3, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if response.phase == .sending { ProgressView().accessibilityLabel("Sending answer") }
            }
            if case .cursorQuestion(let index, let total) = pending.step, total > 1 {
                // Cursor shows one question of its form at a time.
                Text("Question \(index + 1) of \(total)").font(.jost(.caption)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("question-position")
            }
            ForEach(pending.questions, id: \.index) { question in
                questionControls(question)
            }
            .disabled(response.isDisabled)
            if pending.questionKind == .codexAsync, let countdown = pending.countdown {
                Text("Codex moves on in \(countdown)").font(.jost(.caption)).foregroundStyle(.secondary)
            }
            if let message = response.message {
                Text(message).font(.jost(.caption))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("question-response-message")
            }
            Button("Submit", action: onSubmit)
                .buttonStyle(.herdrPrimary())
                .disabled(!response.canSubmit)
                .accessibilityIdentifier("question-submit")
            if pending.questionKind == .codexAsync {
                Button("Skip", action: onSkip)
                    .buttonStyle(.herdrGhost())
                    .disabled(response.isDisabled)
                    .accessibilityIdentifier("question-skip")
            }
        }
        .padding(16)
        .foregroundStyle(Theme.text)
        .needsAnswerCard()
        .accessibilityIdentifier("timeline-question-card")
        .onChange(of: focusedQuestion) { _, index in
            onFieldFocus(index.map { fieldTarget($0) })
        }
        .onChange(of: response.isDisabled) { _, disabled in
            if disabled { focusOnInsertion = nil; focusedQuestion = nil }
        }
        .onDisappear { onFieldFocus(nil) }
    }

    private func questionControls(_ question: AgentQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if pending.questions.count > 1 {
                if let header = question.header {
                    Text(verbatim: header).font(.jost(.caption, weight: .semibold)).foregroundStyle(.secondary)
                }
                Text(verbatim: question.text).font(.jost(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(question.options, id: \.number) { option in
                let selected = response.selections[question.index, default: []].contains(option.number)
                Button {
                    response.select(question: question.index, option: option.number)
                    if !question.multiSelect && pending.questionKind != .codexPlan {
                        editingOther.remove(question.index)
                        focusOnInsertion = nil
                        focusedQuestion = nil
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        selectionIcon(selected: selected, multi: question.multiSelect)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: option.label).fixedSize(horizontal: false, vertical: true)
                            if let description = option.description {
                                Text(verbatim: description).font(.jost(.subheadline)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(ApprovalOptionButtonStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            if pending.questionKind == .codexPlan {
                answerField(question, label: "Notes (optional)")
            } else if question.allowsOther {
                if editingOther.contains(question.index) || !(response.texts[question.index] ?? "").isEmpty {
                    answerField(question, label: "Type something…")
                } else {
                    Button {
                        focusOnInsertion = question.index
                        editingOther.insert(question.index)
                        response.setText("", question: question.index)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            selectionIcon(selected: false, multi: question.multiSelect)
                            Text("Type something…")
                        }
                    }
                    .buttonStyle(ApprovalOptionButtonStyle())
                }
            }
        }
    }
    private func selectionIcon(selected: Bool, multi: Bool) -> some View {
        Image(systemName: multi ? (selected ? "checkmark.square.fill" : "square")
              : (selected ? "largecircle.fill.circle" : "circle"))
            .foregroundStyle(selected ? Theme.accentFill : Theme.textMuted)
            .accessibilityHidden(true)
    }
    private func fieldTarget(_ index: Int) -> QuestionFieldTarget {
        QuestionFieldTarget(scope: scope, requestId: pending.requestId, questionIndex: index)
    }
    private func answerField(_ question: AgentQuestion, label: String) -> some View {
        TextField(label, text: Binding(
            get: { response.texts[question.index, default: ""] },
            set: { response.setText($0, question: question.index) }))
            .font(.jost(.subheadline))
            .padding(12)
            .frame(minHeight: 44)
            .background(Theme.fieldBackground, in: RoundedRectangle.continuous(DesignSystem.CornerRadius.button))
            .id(fieldTarget(question.index))
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: QuestionFieldFramesPreferenceKey.self,
                        value: [fieldTarget(question.index): geometry.frame(in: .named("timeline-viewport"))])
                }
            }
            .focused($focusedQuestion, equals: question.index)
            .onAppear {
                // The field now exists; setting focus in the insertion button
                // runs before SwiftUI has installed its focus binding.
                if focusOnInsertion == question.index {
                    focusOnInsertion = nil
                    focusedQuestion = question.index
                }
            }
            .submitLabel(.done)
            .onSubmit { focusedQuestion = nil }
            .accessibilityLabel("\(question.header ?? question.text): \(label)")
    }
}
