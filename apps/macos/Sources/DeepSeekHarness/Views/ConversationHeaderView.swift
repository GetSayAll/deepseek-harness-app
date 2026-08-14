import SwiftUI

enum ConversationSection: Hashable {
    case dialogue
    case trace
}

struct ConversationHeaderView: View {
    let store: AppStore
    @Binding var selection: ConversationSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(store.selectedSession?.title ?? "新会话")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DSTheme.textPrimary)
                    .lineLimit(1)
                    .help(store.selectedSession?.title ?? "新会话")
                Spacer()
                Button {
                    if store.selectedTool != nil { store.selectTool(nil) }
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DSTheme.textSecondary)
                .help(store.selectedTool == nil ? "选择工具后查看详情" : "关闭工具详情")
            }

            HStack(spacing: 28) {
                tab("对话", section: .dialogue)
                tab("运行轨迹", section: .trace)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(DSTheme.backgroundBase)
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 28) }
    }

    private func tab(_ title: String, section: ConversationSection) -> some View {
        Button { selection = section } label: {
            Text(title)
                .font(.system(size: 14, weight: selection == section ? .semibold : .medium))
                .foregroundStyle(selection == section ? DSTheme.textPrimary : DSTheme.textSecondary)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    if selection == section {
                        Rectangle().fill(DSTheme.brandPrimary).frame(height: 2).offset(y: 11)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
