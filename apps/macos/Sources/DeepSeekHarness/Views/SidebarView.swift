import SwiftUI

struct SidebarView: View {
    let store: AppStore
    let compact: Bool

    var body: some View {
        Group {
            if compact { compactSidebar } else { expandedSidebar }
        }
        .background(DSTheme.sidebarFill)
    }

    private var expandedSidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text("DS")
                    Text("HARNESS")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DSTheme.textPrimary)
                .tracking(0.6)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 16)

            Button { Task { await store.newSession() } } label: {
                Label("新会话", systemImage: "plus.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(DSTheme.brandPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)

            HStack {
                Text("工作区")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DSTheme.textPrimary)
                Spacer()
                Button { Task { await store.addWorkspace() } } label: {
                    Image(systemName: "folder.badge.plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DSTheme.textSecondary)
                .help("添加工作区")
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 8)

            List(selection: sessionSelection) {
                ForEach(store.workspaces) { workspace in
                    DisclosureGroup {
                        ForEach(sessions(in: workspace)) { session in
                            SessionRow(session: session)
                                .tag(session.sessionId)
                        }
                        Button("在此工作区新建会话") {
                            Task { await store.newSession(workspaceId: workspace.workspaceId) }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(DSTheme.brandPrimary)
                    } label: {
                        Label(workspace.title, systemImage: "folder")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }

                if !ungroupedSessions.isEmpty {
                    Section("其他会话") {
                        ForEach(ungroupedSessions) { session in
                            SessionRow(session: session)
                                .tag(session.sessionId)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
            SettingsLink {
                Label("设置", systemImage: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 48)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DSTheme.textPrimary)
        }
    }

    private var compactSidebar: some View {
        VStack(spacing: 12) {
            BrandMark(size: 36)
                .padding(.top, 14)

            Button { Task { await store.newSession() } } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(DSTheme.brandPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help("新会话")

            Button { Task { await store.addWorkspace() } } label: {
                Image(systemName: "folder.badge.plus")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DSTheme.textSecondary)
            .help("添加工作区")

            Divider().padding(.horizontal, 10)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.sessions.prefix(8)) { session in
                        Button { Task { await store.selectSession(session.sessionId) } } label: {
                            Image(systemName: session.running ? "circle.fill" : "bubble.left")
                                .font(.system(size: session.running ? 9 : 16))
                                .foregroundStyle(session.running ? DSTheme.success : DSTheme.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(store.selectedSessionId == session.sessionId ? DSTheme.selectionFill : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(session.title)
                    }
                }
            }

            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DSTheme.textSecondary)
            .help("设置")
            .padding(.bottom, 12)
        }
    }

    private var sessionSelection: Binding<String?> {
        Binding(
            get: { store.selectedSessionId },
            set: { value in Task { await store.selectSession(value) } }
        )
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
            Image(systemName: "bubble.left")
                .font(.system(size: 13))
                .foregroundStyle(session.running ? DSTheme.brandPrimary : DSTheme.textSecondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let cwd = session.cwd {
                    Text(URL(fileURLWithPath: cwd).lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(DSTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if session.running {
                Circle().fill(DSTheme.brandPrimary).frame(width: 6, height: 6)
                    .accessibilityLabel("运行中")
            }
        }
        .padding(.vertical, 2)
    }
}
