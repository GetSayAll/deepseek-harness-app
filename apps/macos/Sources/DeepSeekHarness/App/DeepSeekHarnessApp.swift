import AppKit
import SwiftUI
import UserNotifications

@main
struct DeepSeekHarnessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("DS Harness", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    appDelegate.stopApplication = { await store.stop() }
                    appDelegate.openSession = { sessionId in await store.selectSession(sessionId) }
                    await store.start()
                }
        }
        .defaultSize(width: 1243, height: 852)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新会话") {
                    Task { await store.newSession() }
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("添加工作区…") {
                    Task { await store.addWorkspace() }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
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
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 920, height: 700)
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    var stopApplication: (() async -> Void)?
    var openSession: ((String) async -> Void)? {
        didSet { openPendingSessionIfPossible() }
    }
    private var pendingSessionId: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            self.presentMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentMainWindow()
        return true
    }

    static func hasVisibleMainWindow(in windows: [NSWindow]) -> Bool {
        windows.contains { window in
            isVisibleMainWindow(identifier: window.identifier?.rawValue, visible: window.isVisible)
        }
    }

    static func isVisibleMainWindow(identifier: String?, visible: Bool) -> Bool {
        visible && identifier?.hasPrefix("main-") == true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let stopApplication else { return .terminateNow }
        Task {
            await stopApplication()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        pendingSessionId = response.notification.request.content.userInfo["sessionId"] as? String
        center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
        presentMainWindow()
        openPendingSessionIfPossible()
        completionHandler()
    }

    private func presentMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: {
            Self.isVisibleMainWindow(identifier: $0.identifier?.rawValue, visible: $0.isVisible)
        }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
        }
    }

    private func openPendingSessionIfPossible() {
        guard let pendingSessionId, let openSession else { return }
        self.pendingSessionId = nil
        Task { await openSession(pendingSessionId) }
    }
}
