import AppKit
import SwiftUI

@main
struct DeepSeekHarnessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("DS Harness", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 760, minHeight: 520)
                .task {
                    appDelegate.stopApplication = { await store.stop() }
                    await store.start()
                }
        }
        .defaultSize(width: 960, height: 680)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutLink()
            }
            CommandGroup(after: .appInfo) {
                Button("重新连接 Host") {
                    Task { await store.restart() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Window("关于 DS Harness", id: "about") {
            AboutView()
        }
        .defaultSize(width: 420, height: 360)
        .windowResizability(.contentSize)

        Settings {
            SettingsView(store: store)
        }
    }
}

private struct AboutLink: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("关于 DS Harness") {
            openWindow(id: "about")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var stopApplication: (() async -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            if NSApp.windows.isEmpty {
                NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil) }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let stopApplication else { return .terminateNow }
        Task {
            await stopApplication()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
