import SwiftUI

struct ConversationHeaderView: View {
    let store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(store.selectedSession?.title ?? "新会话")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DSTheme.textPrimary)
                    .lineLimit(1)
                    .help(store.selectedSession?.title ?? "新会话")
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DSTheme.textSecondary)
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
                Text("对话")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DSTheme.textPrimary)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(DSTheme.brandPrimary).frame(height: 2).offset(y: 11)
                    }
                Text("运行轨迹")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DSTheme.textSecondary)
                    .help("原生轨迹协议接入后可用")
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(DSTheme.backgroundBase)
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 28) }
    }
}
