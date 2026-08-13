import SwiftUI

struct SidebarView: View {
    let store: AppStore

    var body: some View {
        List(selection: Binding(
            get: { store.selectedSessionId },
            set: { value in Task { await store.selectSession(value) } }
        )) {
            if !store.workspaces.isEmpty {
                Section("工作区") {
                    ForEach(store.workspaces) { workspace in
                        DisclosureGroup {
                            ForEach(sessions(in: workspace)) { session in
                                SessionRow(session: session).tag(session.sessionId)
                            }
                            Button("新建会话") { Task { await store.newSession(workspaceId: workspace.workspaceId) } }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label(workspace.title, systemImage: "folder")
                        }
                    }
                }
            }

            Section("会话") {
                ForEach(ungroupedSessions) { session in
                    SessionRow(session: session).tag(session.sessionId)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("DS Harness")
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await store.newSession() } } label: {
                    Label("新建会话", systemImage: "square.and.pencil")
                }
                Button { Task { await store.addWorkspace() } } label: {
                    Label("添加工作区", systemImage: "folder.badge.plus")
                }
            }
        }
    }

    private func sessions(in workspace: Workspace) -> [SessionSummary] {
        store.sessions.filter { workspace.sessionIds.contains($0.sessionId) && !$0.blank }
    }

    private var ungroupedSessions: [SessionSummary] {
        let grouped = Set(store.workspaces.flatMap(\.sessionIds))
        return store.sessions.filter { !grouped.contains($0.sessionId) && !$0.blank }
    }
}

private struct SessionRow: View {
    let session: SessionSummary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.running ? "circle.fill" : "bubble.left")
                .font(.caption2)
                .foregroundStyle(session.running ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).lineLimit(1)
                if let cwd = session.cwd {
                    Text(cwd).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
