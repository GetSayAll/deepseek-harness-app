import AppKit
import Foundation

@MainActor
enum DirectoryPicker {
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择工作区"
        panel.prompt = "添加"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
