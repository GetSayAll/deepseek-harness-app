import SwiftUI

struct SettingsView: View {
    let store: AppStore

    var body: some View {
        Form {
            LabeledContent("原生协议版本", value: "0")
            LabeledContent("Host 版本", value: store.hostVersion)
            LabeledContent("连接状态", value: store.connectionState.label)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
    }
}
