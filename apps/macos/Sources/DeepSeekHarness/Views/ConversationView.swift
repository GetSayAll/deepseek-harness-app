import SwiftUI

struct ConversationView: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            if store.selectedSessionId == nil {
                ContentUnavailableView {
                    Label("开始一个会话", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("新建会话后即可使用真实 Harness 插件与模型。")
                } actions: {
                    Button("新建会话") { Task { await store.newSession() } }
                    Button("添加工作区") { Task { await store.addWorkspace() } }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 18) {
                            ForEach(store.conversation) { item in
                                ConversationItemView(item: item).id(item.id)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                    }
                    .onChange(of: store.conversation) { _, conversation in
                        guard let id = conversation.last?.id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
                Divider()
                if let pending = store.selectedPendingInteraction {
                    PendingInteractionView(store: store, pending: pending).id(pending.id)
                } else {
                    ComposerView(store: store)
                }
            }
        }
        .navigationTitle(store.selectedSession?.title ?? "新会话")
    }
}

private struct ConversationItemView: View {
    let item: ConversationItem

    var body: some View {
        switch item {
        case let .message(message): MessageView(message: message)
        case let .tool(tool): ToolCardView(tool: tool)
        }
    }
}

private struct ToolCardView: View {
    let tool: ToolCard
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if !tool.detail.isEmpty {
                Text(tool.detail)
                    .font(.system(.caption, design: tool.card == "terminal" ? .monospaced : .default))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tool.isError ? "exclamationmark.triangle.fill" : symbol)
                    .foregroundStyle(tool.isError ? .red : .secondary)
                Text(tool.title).lineLimit(1)
                Spacer()
                if tool.completed {
                    Image(systemName: tool.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(tool.isError ? .red : .green)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var symbol: String {
        switch tool.card {
        case "terminal": "terminal"
        case "diff": "doc.badge.gearshape"
        default: "wrench.and.screwdriver"
        }
    }
}

private struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .assistant {
                content
                Spacer(minLength: 80)
            } else {
                Spacer(minLength: 80)
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.role == .assistant ? "DeepSeek" : "你")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(markdown)
                .textSelection(.enabled)
                .lineSpacing(3)
            if message.streaming { ProgressView().controlSize(.small) }
        }
        .padding(12)
        .background(message.role == .assistant ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.tint.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var markdown: AttributedString {
        (try? AttributedString(markdown: message.text)) ?? AttributedString(message.text)
    }
}
