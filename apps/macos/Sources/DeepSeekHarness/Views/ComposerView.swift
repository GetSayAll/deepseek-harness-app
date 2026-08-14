import SwiftUI

struct ComposerView: View {
    let store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(canCompose ? "给智能体发消息…" : "选择一个工作区开始", text: draftBinding, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(DSTheme.textPrimary)
                .lineLimit(3...10)
                .textFieldStyle(.plain)
                .disabled(!canCompose)
                .onSubmit { Task { await store.send() } }

            HStack(spacing: 8) {
                if store.selectedSessionId == nil {
                    Menu {
                        ForEach(store.workspaces) { workspace in
                            Button {
                                store.preferredWorkspaceId = workspace.workspaceId
                            } label: {
                                if store.preferredWorkspaceId == workspace.workspaceId {
                                    Label(workspace.title, systemImage: "checkmark")
                                } else {
                                    Text(workspace.title)
                                }
                            }
                        }
                    } label: {
                        Label(selectedWorkspaceTitle, systemImage: "folder")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(store.workspaces.isEmpty)
                } else {
                    Label("通用助手", systemImage: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(DSTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(DSTheme.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Spacer()

                Button { Task { store.isSending ? await store.cancel() : await store.send() } } label: {
                    Image(systemName: store.isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(store.isSending ? DSTheme.danger : DSTheme.brandPrimary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!store.isSending && (!canCompose || store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                .opacity(!store.isSending && (!canCompose || store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.4 : 1)
                .help(store.isSending ? "停止生成" : "发送")
            }
        }
        .padding(16)
        .frame(minHeight: 116, maxHeight: 336, alignment: .top)
        .dsCard(cornerRadius: 16, shadow: true)
    }

    private var draftBinding: Binding<String> {
        Binding(get: { store.draft }, set: { store.draft = $0 })
    }

    private var canCompose: Bool {
        !store.workspaces.isEmpty
    }

    private var selectedWorkspaceTitle: String {
        store.workspaces.first { $0.workspaceId == store.preferredWorkspaceId }?.title
            ?? store.workspaces.first?.title
            ?? "选择工作区"
    }
}
