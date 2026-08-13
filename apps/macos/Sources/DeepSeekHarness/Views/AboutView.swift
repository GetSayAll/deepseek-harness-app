import SwiftUI

struct AboutView: View {
    private let website = URL(string: "https://dsapp.sayall.app?from=mac")!

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)

            VStack(spacing: 4) {
                Text("DS Harness")
                    .font(.title.bold())
                Text("版本 \(version)")
                    .foregroundStyle(.secondary)
            }

            Text("DeepSeek Harness 的原生 macOS 客户端")
                .foregroundStyle(.secondary)

            Link("访问 DS Harness 官网", destination: website)
        }
        .padding(32)
        .frame(width: 420, height: 360)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1"
    }
}
