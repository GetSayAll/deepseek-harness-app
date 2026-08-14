import SwiftUI

struct ConversationView: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            if store.selectedSessionId == nil || (
                store.conversation.isEmpty
                    && !store.isSending
                    && store.selectedPendingInteraction == nil
            ) {
                VStack(spacing: 22) {
                    Spacer(minLength: 32)
                    EmptyConversationView(store: store)
                    ComposerSeatView(store: store)
                    Spacer(minLength: 84)
                }
            } else {
                ConversationHeaderView(store: store)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 22) {
                            ForEach(store.conversation) { item in
                                ConversationItemView(store: store, item: item).id(item.id)
                            }
                        }
                        .frame(maxWidth: DSTheme.contentMaximum)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 20)
                    }
                    .onChange(of: store.conversation) { _, conversation in
                        guard let id = conversation.last?.id else { return }
                        withAnimation(.easeInOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }

                ComposerSeatView(store: store)
            }
        }
        .background(DSTheme.backgroundBase)
    }
}

private struct EmptyConversationView: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 12) {
            BrandMark(size: 72)
            Text("今天想构建什么？")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(DSTheme.textPrimary)
            Text("选择工作区，描述目标，Harness 会调用模型与工具完成任务。")
                .font(.system(size: 14))
                .foregroundStyle(DSTheme.textSecondary)
            if store.workspaces.isEmpty {
                Button("添加工作区") { Task { await store.addWorkspace() } }
                    .buttonStyle(.bordered)
                    .tint(DSTheme.brandPrimary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ComposerSeatView: View {
    let store: AppStore

    var body: some View {
        ZStack(alignment: .bottom) {
            ComposerView(store: store)
                .allowsHitTesting(store.selectedPendingInteraction == nil)
                .opacity(store.selectedPendingInteraction == nil ? 1 : 0)

            if let pending = store.selectedPendingInteraction {
                PendingInteractionView(store: store, pending: pending)
                    .id(pending.id)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: DSTheme.composerMaximum)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}

private struct ConversationItemView: View {
    let store: AppStore
    let item: ConversationItem

    var body: some View {
        switch item {
        case let .message(message): MessageView(message: message)
        case let .tool(tool): ToolRowView(store: store, tool: tool)
        }
    }
}

private struct ToolRowView: View {
    let store: AppStore
    let tool: ToolCard

    var body: some View {
        Button { store.selectTool(tool) } label: {
            HStack(spacing: 10) {
                Image(systemName: tool.isError ? "exclamationmark.triangle.fill" : symbol)
                    .foregroundStyle(tool.isError ? DSTheme.danger : DSTheme.textSecondary)
                    .frame(width: 18)
                Text(tool.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DSTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                status
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DSTheme.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(store.selectedToolId == tool.id ? DSTheme.selectionFill : DSTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(store.selectedToolId == tool.id ? DSTheme.brandPrimary.opacity(0.25) : DSTheme.borderSubtle)
            }
        }
        .buttonStyle(.plain)
        .help("查看工具输入与输出")
    }

    @ViewBuilder
    private var status: some View {
        if tool.completed {
            Label(tool.isError ? "失败" : "已完成", systemImage: tool.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(tool.isError ? DSTheme.danger : DSTheme.success)
        } else {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("运行中")
            }
            .font(.system(size: 11))
            .foregroundStyle(DSTheme.brandPrimary)
        }
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
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                Text(message.role == .assistant ? "DS Harness" : "你")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(message.role == .assistant ? DSTheme.textPrimary : DSTheme.textSecondary)
                Text(markdown)
                    .font(.system(size: 15))
                    .foregroundStyle(DSTheme.textPrimary)
                    .textSelection(.enabled)
                    .lineSpacing(5)
                    .padding(message.role == .user ? 12 : 0)
                    .background(message.role == .user ? DSTheme.selectionFill : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: message.role == .user ? 525 : .infinity, alignment: .leading)
                if message.streaming {
                    ProgressView().controlSize(.small).tint(DSTheme.brandHighlight)
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if message.role == .assistant {
            BrandMark(size: 30)
        } else {
            Image(systemName: "person")
                .font(.system(size: 15))
                .foregroundStyle(DSTheme.brandPrimary)
                .frame(width: 30, height: 30)
                .background(DSTheme.selectionFill)
                .clipShape(Circle())
        }
    }

    private var markdown: AttributedString {
        (try? AttributedString(markdown: message.text)) ?? AttributedString(message.text)
    }
}
