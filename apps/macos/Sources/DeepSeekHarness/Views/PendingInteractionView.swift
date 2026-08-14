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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 22))
                    .foregroundStyle(DSTheme.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("需要你的批准")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DSTheme.textPrimary)
                    Text(approval.reason ?? "工具 \(approval.toolName) 请求一次额外权限。")
                        .font(.system(size: 13))
                        .foregroundStyle(DSTheme.textSecondary)
                }
            }

            if let card = toolCard {
                Text(card.arguments)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(DSTheme.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(DSTheme.surfacePrimary.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DSTheme.borderSubtle)
                    }
            }

            HStack {
                Spacer()
                Button("拒绝") { answer("rejected") }
                    .disabled(busy)
                Button("允许一次") { answer("allowed-once") }
                    .buttonStyle(.borderedProminent)
                    .tint(DSTheme.brandPrimary)
                    .disabled(busy)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 176)
        .dsCard(cornerRadius: 16, fill: DSTheme.warning.opacity(0.08), border: DSTheme.warning.opacity(0.45), shadow: true)
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
        VStack(spacing: 0) {
            HStack {
                Label("智能体需要更多信息", systemImage: "questionmark.bubble")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DSTheme.textPrimary)
                Spacer()
                Text("\(answeredCount)/\(request.questions.count) 已回答")
                    .font(.system(size: 12))
                    .foregroundStyle(DSTheme.textSecondary)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .overlay(alignment: .bottom) { Divider() }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(request.questions) { question in
                        questionSection(question)
                    }
                    if let validationMessage {
                        Text(validationMessage)
                            .foregroundStyle(DSTheme.danger)
                            .font(.system(size: 12))
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: 236)

            HStack {
                Button("取消") { cancel() }.disabled(busy)
                Spacer()
                Button("提交回答") { submit() }
                    .buttonStyle(.borderedProminent)
                    .tint(DSTheme.brandPrimary)
                    .disabled(busy || answeredCount != request.questions.count)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .dsCard(cornerRadius: 16, shadow: true)
    }

    @ViewBuilder
    private func questionSection(_ question: PendingQuestion.Question) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let header = question.header {
                Text(header)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DSTheme.textSecondary)
            }
            Text(question.question)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DSTheme.textPrimary)
            if let detail = question.detail {
                Text((try? AttributedString(markdown: detail)) ?? AttributedString(detail))
                    .font(.system(size: 13))
                    .foregroundStyle(DSTheme.textSecondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                ForEach(question.options) { option in
                    optionButton(option, question: question)
                }
            }

            TextField(question.options.isEmpty ? "请输入回答" : "补充说明（可选）", text: customBinding(question), axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .padding(10)
                .background(DSTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(DSTheme.borderSubtle) }
                .disabled(busy || draft(question).skipped)

            Toggle("跳过这个问题", isOn: skippedBinding(question))
                .font(.system(size: 12))
                .disabled(busy)
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
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? (question.multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle") : (question.multiSelect ? "square" : "circle"))
                    .foregroundStyle(selected ? DSTheme.brandPrimary : DSTheme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DSTheme.textPrimary)
                    if let description = option.description {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundStyle(DSTheme.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            .background(selected ? DSTheme.selectionFill : DSTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? DSTheme.brandPrimary.opacity(0.65) : DSTheme.borderSubtle)
            }
        }
        .buttonStyle(.plain)
        .disabled(busy || draft(question).skipped)
    }

    private var answeredCount: Int {
        request.questions.filter { question in
            let value = draft(question)
            return value.skipped || !value.selected.isEmpty || !value.custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
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
        guard answeredCount == request.questions.count else {
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
