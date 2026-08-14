import SwiftUI

struct DetailsPanelView: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(store.selectedTool?.title ?? "工具详情")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DSTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Button { store.selectTool(nil) } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DSTheme.textSecondary)
                .help("关闭详情")
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
            .background(DSTheme.surfacePrimary)
            .overlay(alignment: .bottom) { Divider() }

            if let tool = store.selectedTool {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        DetailSection(title: "输入") {
                            CodeCard(text: formattedArguments(tool.arguments), dark: false)
                        }
                        DetailSection(title: "输出") {
                            CodeCard(
                                text: tool.completed ? (tool.detail.isEmpty ? "工具未返回可显示内容" : tool.detail) : "工具正在运行…",
                                dark: tool.card == "terminal"
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(DSTheme.surfacePrimary)
    }

    private func formattedArguments(_ arguments: String) -> String {
        guard !arguments.isEmpty else { return "无输入参数" }
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else { return arguments }
        return text
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DSTheme.textPrimary)
            content
        }
    }
}

private struct CodeCard: View {
    let text: String
    let dark: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(dark ? Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255) : DSTheme.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .background(dark ? Color(red: 30 / 255, green: 37 / 255, blue: 48 / 255) : DSTheme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(dark ? Color.white.opacity(0.06) : DSTheme.borderSubtle, lineWidth: 1)
        }
    }
}
