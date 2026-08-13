import SwiftUI

struct ComposerView: View {
    let store: AppStore

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("给 DeepSeek 发送消息…", text: Binding(
                get: { store.draft },
                set: { store.draft = $0 }
            ), axis: .vertical)
            .lineLimit(1...8)
            .textFieldStyle(.plain)
            .padding(10)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onSubmit { Task { await store.send() } }

            if store.isSending {
                Button { Task { await store.cancel() } } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .help("停止生成")
            } else {
                Button { Task { await store.send() } } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("发送")
            }
        }
        .padding(16)
    }
}
