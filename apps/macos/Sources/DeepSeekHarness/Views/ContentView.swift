import SwiftUI

struct ContentView: View {
    let store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            if store.connectionState == .ready {
                ConversationView(store: store)
            } else {
                HostStatusView(store: store)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await store.restart() }
                } label: {
                    Label("重新连接", systemImage: "arrow.clockwise")
                }
                .disabled(store.connectionState == .starting)
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("好") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "未知错误")
        }
    }
}

private struct HostStatusView: View {
    let store: AppStore

    var body: some View {
        ContentUnavailableView {
            Label(store.connectionState.label, systemImage: symbol)
        } description: {
            Text("正在连接真实 Harness Host，不开放本地端口。")
        } actions: {
            if store.connectionState != .starting {
                Button("重新连接") { Task { await store.restart() } }
            }
        }
    }

    private var symbol: String {
        switch store.connectionState {
        case .starting: "arrow.triangle.2.circlepath.circle"
        case .failed: "exclamationmark.triangle.fill"
        case .ready: "checkmark.circle.fill"
        case .idle: "circle.dotted"
        }
    }
}
