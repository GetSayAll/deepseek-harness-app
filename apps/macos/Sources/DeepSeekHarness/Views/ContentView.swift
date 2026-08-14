import SwiftUI

struct ContentView: View {
    let store: AppStore

    var body: some View {
        GeometryReader { geometry in
            AppFrameView(store: store, availableWidth: geometry.size.width)
        }
        .background(DSTheme.backgroundBase)
        .preferredColorScheme(.light)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await store.restart() }
                } label: {
                    Label("重新连接", systemImage: "arrow.clockwise")
                }
                .disabled(store.connectionState == .starting)
                .help("重新连接 Host")
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
