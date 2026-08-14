import SwiftUI

struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case models = "模型"
        case agents = "智能体预设"
        case plugins = "插件"
        case general = "通用"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .models: "cube"
            case .agents: "person"
            case .plugins: "puzzlepiece.extension"
            case .general: "gearshape"
            }
        }
    }

    let store: AppStore
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
        case .general:
            GeneralSettingsView(store: store)
        }
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
