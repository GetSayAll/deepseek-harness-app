import SwiftUI

struct AppFrameView: View {
    let store: AppStore
    let availableWidth: CGFloat

    @AppStorage("mainSidebarWidth") private var savedSidebarWidth = DSTheme.sidebarDefault
    @AppStorage("mainDetailsWidth") private var savedDetailsWidth = DSTheme.detailsDefault

    private var compactSidebar: Bool { availableWidth < 1024 }
    private var showsDetails: Bool {
        store.selectedTool != nil
            && availableWidth >= sidebarWidth + detailsWidth + 640
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(store: store, compact: compactSidebar)
                .frame(width: compactSidebar ? DSTheme.sidebarCompact : sidebarWidth)

            if !compactSidebar {
                ResizableDivider(edge: .leading) { delta in
                    savedSidebarWidth = min(max(savedSidebarWidth + delta, DSTheme.sidebarMinimum), DSTheme.sidebarMaximum)
                }
            } else {
                Divider()
            }

            VStack(spacing: 0) {
                if store.connectionState != .ready {
                    HostConnectionBanner(store: store)
                }
                if store.connectionState == .ready, store.deepSeekCredential?.configured == false {
                    CredentialRequiredView()
                } else {
                    ConversationView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DSTheme.backgroundBase)

            if showsDetails {
                ResizableDivider(edge: .trailing) { delta in
                    savedDetailsWidth = min(max(savedDetailsWidth - delta, DSTheme.detailsMinimum), DSTheme.detailsMaximum)
                }
                DetailsPanelView(store: store)
                    .frame(width: detailsWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(DSTheme.backgroundBase)
    }

    private var sidebarWidth: CGFloat {
        min(max(savedSidebarWidth, DSTheme.sidebarMinimum), DSTheme.sidebarMaximum)
    }

    private var detailsWidth: CGFloat {
        min(max(savedDetailsWidth, DSTheme.detailsMinimum), DSTheme.detailsMaximum)
    }
}

private struct ResizableDivider: View {
    enum Edge { case leading, trailing }

    let edge: Edge
    let onChange: (CGFloat) -> Void
    @State private var previousTranslation = 0.0

    var body: some View {
        Color.clear
            .frame(width: 0)
            .overlay {
                Rectangle()
                    .fill(DSTheme.borderSubtle)
                    .frame(width: 1)
                    .overlay {
                        Color.clear.frame(width: 8)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let delta = value.translation.width - previousTranslation
                                previousTranslation = value.translation.width
                                onChange(delta)
                            }
                            .onEnded { _ in previousTranslation = 0 }
                    )
            }
            .help(edge == .leading ? "调整侧栏宽度" : "调整详情栏宽度")
    }
}

private struct HostConnectionBanner: View {
    let store: AppStore

    var body: some View {
        HStack(spacing: 8) {
            if store.connectionState == .starting {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DSTheme.warning)
            }
            Text(store.connectionState.label)
                .font(.system(size: 12))
                .foregroundStyle(DSTheme.textSecondary)
                .lineLimit(1)
            Spacer()
            if store.connectionState != .starting {
                Button("重新连接") { Task { await store.restart() } }
                    .buttonStyle(.plain)
                    .foregroundStyle(DSTheme.brandPrimary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(DSTheme.warning.opacity(0.10))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct CredentialRequiredView: View {
    var body: some View {
        VStack(spacing: 16) {
            BrandMark(size: 68)
            Text("配置 DeepSeek API Key")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(DSTheme.textPrimary)
            Text("DS Harness 已内置完整运行环境。添加 API Key 后即可开始使用，\n无需安装 Node.js 或启动本地服务。")
                .multilineTextAlignment(.center)
                .foregroundStyle(DSTheme.textSecondary)
            SettingsLink {
                Text("打开设置")
                    .frame(minWidth: 96)
            }
            .buttonStyle(.borderedProminent)
            .tint(DSTheme.brandPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSTheme.backgroundBase)
    }
}
