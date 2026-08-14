import SwiftUI

struct ComposerView: View {
    let store: AppStore
    @AppStorage("conversationComposerHeight") private var storedHeight = 116.0
    @State private var dragStartHeight: Double?

    private let minimumHeight = 104.0
    private let maximumHeight = 300.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            resizeHandle

            VStack(alignment: .leading, spacing: 8) {
                TextField(canCompose ? "给智能体发消息…" : "选择一个工作区开始", text: draftBinding, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(DSTheme.textPrimary)
                    .lineLimit(1...10)
                    .textFieldStyle(.plain)
                    .frame(maxHeight: .infinity, alignment: .top)
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
                        agentPresetMenu
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
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(height: clampedHeight, alignment: .top)
        .dsCard(cornerRadius: 16, shadow: true)
    }

    private var resizeHandle: some View {
        Capsule()
            .fill(DSTheme.borderSubtle)
            .frame(width: 34, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartHeight ?? clampedHeight
                        dragStartHeight = start
                        storedHeight = min(max(start - value.translation.height, minimumHeight), maximumHeight)
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
            .help("拖动调整输入框高度")
    }

    private var agentPresetMenu: some View {
        Menu {
            if store.agentPresets.isEmpty {
                Text("当前未配置可选助手")
            } else {
                ForEach(store.agentPresets) { preset in
                    Button {
                        Task { await store.selectAgentPreset(preset.id) }
                    } label: {
                        if store.selectedAgentPresetId == preset.id {
                            Label(preset.displayName, systemImage: "checkmark")
                        } else {
                            Text(preset.displayName)
                        }
                    }
                    .disabled(store.selectedSession?.blank != true || preset.broken != nil)
                }
            }
            if store.selectedSession?.blank == false {
                Divider()
                Text("会话开始后不可更换助手")
            }
        } label: {
            Label(store.selectedAgentPresetTitle, systemImage: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(DSTheme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(DSTheme.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(store.isAgentPresetSaving)
        .help("选择智能体预设")
    }

    private var draftBinding: Binding<String> {
        Binding(get: { store.draft }, set: { store.draft = $0 })
    }

    private var clampedHeight: Double {
        min(max(storedHeight, minimumHeight), maximumHeight)
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
