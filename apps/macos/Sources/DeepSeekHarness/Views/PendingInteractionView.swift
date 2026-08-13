import SwiftUI

struct PendingInteractionView: View {
    let store: AppStore
    let pending: PendingInteraction

    var body: some View {
        switch pending {
        case let .approval(approval): ApprovalView(store: store, approval: approval)
        case let .question(question): QuestionView(store: store, request: question)
        }
    }
}

private struct ApprovalView: View {
    let store: AppStore
    let approval: PendingApproval
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("等待批准", systemImage: "exclamationmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(approval.reason ?? "工具 \(approval.toolName) 请求一次额外权限。")
            if let card = toolCard {
                Text(card.arguments)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(6)
            }
            HStack {
                Spacer()
                Button("拒绝") { answer("rejected") }.disabled(busy)
                Button("允许一次") { answer("allowed-once") }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
            }
        }
        .padding(16)
        .background(.orange.opacity(0.08))
    }

    private var toolCard: ToolCard? {
        guard let callId = approval.callId else { return nil }
        return store.conversation.compactMap { item -> ToolCard? in
            guard case let .tool(card) = item, card.callId == callId else { return nil }
            return card
        }.last
    }

    private func answer(_ outcome: String) {
        busy = true
        Task {
            await store.answerApproval(approval, outcome: outcome)
            busy = false
        }
    }
}

private struct QuestionDraft: Equatable {
    var selected: Set<String> = []
    var custom = ""
    var skipped = false
}

private struct QuestionView: View {
    let store: AppStore
    let request: PendingQuestion
    @State private var drafts: [String: QuestionDraft] = [:]
    @State private var busy = false
    @State private var validationMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("DeepSeek 正在等待你的回答", systemImage: "questionmark.bubble.fill")
                    .font(.headline)
                ForEach(request.questions) { question in
                    questionSection(question)
                }
                if let validationMessage {
                    Text(validationMessage).foregroundStyle(.red).font(.caption)
                }
                HStack {
                    Button("取消") { cancel() }.disabled(busy)
                    Spacer()
                    Button("提交回答") { submit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy)
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 360)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func questionSection(_ question: PendingQuestion.Question) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header = question.header {
                Text(header).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(question.question).font(.body.weight(.semibold))
            if let detail = question.detail {
                Text((try? AttributedString(markdown: detail)) ?? AttributedString(detail))
                    .foregroundStyle(.secondary)
            }
            ForEach(question.options) { option in
                optionButton(option, question: question)
            }
            TextField(question.options.isEmpty ? "请输入回答" : "其他回答（可选）", text: customBinding(question))
                .textFieldStyle(.roundedBorder)
                .disabled(busy || draft(question).skipped)
            Toggle("跳过这个问题", isOn: skippedBinding(question)).disabled(busy)
        }
    }

    private func optionButton(_ option: PendingQuestion.Question.Option, question: PendingQuestion.Question) -> some View {
        let selected = draft(question).selected.contains(option.label)
        return Button {
            update(question) { value in
                value.skipped = false
                value.custom = question.multiSelect ? value.custom : ""
                if question.multiSelect {
                    if selected { value.selected.remove(option.label) }
                    else { value.selected.insert(option.label) }
                } else {
                    value.selected = [option.label]
                }
            }
        } label: {
            HStack(alignment: .top) {
                Image(systemName: selected ? (question.multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle") : (question.multiSelect ? "square" : "circle"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                    if let description = option.description {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(busy || draft(question).skipped)
    }

    private func draft(_ question: PendingQuestion.Question) -> QuestionDraft {
        drafts[question.id] ?? .init()
    }

    private func update(_ question: PendingQuestion.Question, _ body: (inout QuestionDraft) -> Void) {
        var value = draft(question)
        body(&value)
        drafts[question.id] = value
        validationMessage = nil
    }

    private func customBinding(_ question: PendingQuestion.Question) -> Binding<String> {
        Binding(
            get: { draft(question).custom },
            set: { text in
                update(question) { value in
                    value.custom = text
                    value.skipped = false
                    if !question.multiSelect { value.selected.removeAll() }
                }
            }
        )
    }

    private func skippedBinding(_ question: PendingQuestion.Question) -> Binding<Bool> {
        Binding(
            get: { draft(question).skipped },
            set: { skipped in
                update(question) { value in
                    value.skipped = skipped
                    if skipped {
                        value.selected.removeAll()
                        value.custom = ""
                    }
                }
            }
        )
    }

    private func submit() {
        let unanswered = request.questions.first { question in
            let value = draft(question)
            return !value.skipped && value.selected.isEmpty && value.custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard unanswered == nil else {
            validationMessage = "请回答或跳过每个问题。"
            return
        }
        let answers = request.questions.map { question -> QuestionResponsePayload.Answer.Item in
            let value = draft(question)
            let custom = value.custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(
                id: question.id,
                selected: value.skipped ? [] : Array(value.selected).sorted(),
                custom: value.skipped || custom.isEmpty ? nil : custom
            )
        }
        busy = true
        Task {
            await store.answerQuestion(request, answers: answers)
            busy = false
        }
    }

    private func cancel() {
        busy = true
        Task {
            await store.cancelQuestion(request)
            busy = false
        }
    }
}
