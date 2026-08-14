import SwiftUI

struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case models = "模型"
        case agents = "智能体预设"
        case plugins = "插件"
        case updates = "更新"
        case general = "通用"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .models: "cube"
            case .agents: "person"
            case .plugins: "puzzlepiece.extension"
            case .updates: "arrow.triangle.2.circlepath"
            case .general: "gearshape"
            }
        }
    }

    let store: AppStore
    @ObservedObject var updates: UpdateService
    @State private var selection: Section = .models
    @State private var apiKey = ""
    @State private var confirmsRemoval = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                settingsSidebar
                    .frame(width: 188)
                Divider()
                settingsContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack(spacing: 8) {
                Circle()
                    .fill(store.connectionState == .ready ? DSTheme.success : DSTheme.warning)
                    .frame(width: 8, height: 8)
                Text(store.connectionState.label)
                    .font(.system(size: 12))
                    .foregroundStyle(DSTheme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 42)
            .background(DSTheme.surfacePrimary)
        }
        .background(DSTheme.backgroundBase)
        .preferredColorScheme(.light)
        .confirmationDialog("移除 DeepSeek API Key？", isPresented: $confirmsRemoval) {
            Button("移除 API Key", role: .destructive) {
                Task { await store.removeDeepSeekAPIKey() }
            }
        } message: {
            Text("移除后，新的 DeepSeek 请求将无法运行，直到再次配置。")
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("设置")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DSTheme.textPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 10)

            ForEach(Section.allCases) { section in
                Button { selection = section } label: {
                    Label(section.rawValue, systemImage: section.symbol)
                        .font(.system(size: 14, weight: selection == section ? .semibold : .medium))
                        .foregroundStyle(selection == section ? DSTheme.brandPrimary : DSTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 44)
                        .padding(.horizontal, 14)
                        .background(selection == section ? DSTheme.selectionFill : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .background(DSTheme.sidebarFill)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch selection {
        case .models:
            ModelsSettingsView(
                store: store,
                apiKey: $apiKey,
                confirmsRemoval: $confirmsRemoval
            )
        case .agents:
            FutureSettingsView(title: "智能体预设", description: "原生预设管理将在协议接入后提供。", symbol: "person.2")
        case .plugins:
            FutureSettingsView(title: "插件", description: "原生插件配置将在协议接入后提供。", symbol: "puzzlepiece.extension")
        case .updates:
            UpdateSettingsView(updates: updates)
        case .general:
            GeneralSettingsView(store: store)
        }
    }
}

private struct UpdateSettingsView: View {
    private let versionHistory = URL(string: "https://dsapp.sayall.app/version-history?from=mac-settings")!
    @ObservedObject var updates: UpdateService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("更新")
                        .font(.system(size: 20, weight: .semibold))
                    Text("每天自动检查一次；发现新版本后由你确认下载和安装。")
                        .font(.system(size: 13))
                        .foregroundStyle(DSTheme.textSecondary)
                }

                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(DSTheme.brandPrimary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("DS Harness \(versionText)")
                                .font(.system(size: 16, weight: .semibold))
                            Text(updates.isConfigured ? updates.channelLabel : "开发构建未配置更新签名")
                                .font(.system(size: 12))
                                .foregroundStyle(DSTheme.textSecondary)
                        }
                        Spacer()
                        Button("检查更新…") {
                            updates.checkForUpdates()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DSTheme.brandPrimary)
                        .disabled(!updates.canCheckForUpdates)
                    }
                    .padding(18)

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("接收预览版更新", isOn: $updates.checksForPreviewUpdates)
                            .disabled(!updates.isConfigured)
                        Text("关闭时只接收正式版；开启后，自动检查和手动检查也会包含最新预览版。预览版可能包含尚未完成充分验证的功能。")
                            .font(.system(size: 12))
                            .foregroundStyle(DSTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("更新内容")
                                .font(.system(size: 13, weight: .semibold))
                            Text("发现新版本时，更新窗口会显示该版本的发布说明。")
                                .font(.system(size: 12))
                                .foregroundStyle(DSTheme.textSecondary)
                        }
                        Spacer()
                        Link("查看版本历史", destination: versionHistory)
                    }
                    .padding(18)
                }
                .dsCard()
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .background(DSTheme.backgroundBase)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1"
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return version
        }
        return "\(version)（\(build)）"
    }
}

private struct ModelsSettingsView: View {
    let store: AppStore
    @Binding var apiKey: String
    @Binding var confirmsRemoval: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("模型")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(DSTheme.textPrimary)
                    Text("配置模型提供方与连接凭据。")
                        .font(.system(size: 13))
                        .foregroundStyle(DSTheme.textSecondary)
                }

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        BrandMark(size: 36)
                        Text("DeepSeek")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(DSTheme.textPrimary)
                        Spacer()
                        Label(credentialStatus, systemImage: credentialSymbol)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(credentialColor)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(credentialColor.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(18)

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("API Key")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DSTheme.textPrimary)
                        SecureField("粘贴 DeepSeek API Key", text: $apiKey)
                            .textContentType(.password)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(DSTheme.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 8).stroke(DSTheme.borderSubtle) }

                        HStack {
                            Text("Key 通过 Harness 凭据服务单向写入，界面无法读取或回显。")
                                .font(.system(size: 11))
                                .foregroundStyle(DSTheme.textSecondary)
                            Spacer()
                            if store.deepSeekCredential?.configured == true {
                                Button("移除", role: .destructive) { confirmsRemoval = true }
                                    .disabled(store.isCredentialSaving || store.deepSeekCredential?.writable == false)
                            }
                            Button("保存") {
                                Task {
                                    if await store.saveDeepSeekAPIKey(apiKey) { apiKey = "" }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DSTheme.brandPrimary)
                            .disabled(apiKey.isEmpty || store.isCredentialSaving || store.deepSeekCredential?.writable == false)
                            if store.isCredentialSaving { ProgressView().controlSize(.small) }
                        }
                    }
                    .padding(18)

                    Divider()

                    LabeledContent("Base URL", value: "https://api.deepseek.com")
                        .font(.system(size: 13))
                        .padding(18)
                }
                .dsCard(cornerRadius: 12)

                VStack(alignment: .leading, spacing: 10) {
                    Text("运行环境")
                        .font(.system(size: 14, weight: .semibold))
                    Text("DS Harness 已内置完整 Node 运行时和原生 Host，无需额外安装或设置环境变量。")
                        .font(.system(size: 13))
                        .foregroundStyle(DSTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .dsCard(cornerRadius: 12)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .background(DSTheme.backgroundBase)
    }

    private var credentialStatus: String {
        guard let credential = store.deepSeekCredential else { return "正在检查…" }
        if credential.configured { return credential.writable ? "已连接" : "启动环境已配置" }
        return "未配置"
    }

    private var credentialSymbol: String {
        store.deepSeekCredential?.configured == true ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var credentialColor: Color {
        store.deepSeekCredential?.configured == true ? DSTheme.success : DSTheme.warning
    }
}

private struct GeneralSettingsView: View {
    let store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("通用")
                    .font(.system(size: 20, weight: .semibold))
                VStack(spacing: 14) {
                    LabeledContent("原生协议版本", value: "0")
                    Divider()
                    LabeledContent("Host 版本", value: store.hostVersion)
                    Divider()
                    LabeledContent("连接状态", value: store.connectionState.label)
                }
                .padding(18)
                .dsCard()
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .background(DSTheme.backgroundBase)
    }
}

private struct FutureSettingsView: View {
    let title: String
    let description: String
    let symbol: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(description))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DSTheme.backgroundBase)
    }
}
