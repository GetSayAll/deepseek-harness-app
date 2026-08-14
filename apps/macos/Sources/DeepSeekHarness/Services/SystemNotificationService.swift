import AppKit
import UserNotifications

@MainActor
final class SystemNotificationService {
    private enum UserInfoKey {
        static let sessionId = "sessionId"
    }

    private let center = UNUserNotificationCenter.current()
    private var deliveryVersions: [String: Int] = [:]

    func notifyApproval(sessionId: String, approvalId: String, selectedSessionId: String?) {
        schedule(
            identifier: "approval-\(approvalId)",
            title: "DS Harness 需要审批",
            body: "有一个任务正在等待你的确认。",
            sessionId: sessionId,
            selectedSessionId: selectedSessionId
        )
    }

    func notifyQuestion(sessionId: String, rpcId: String, selectedSessionId: String?) {
        schedule(
            identifier: "question-\(rpcId)",
            title: "DS Harness 需要你的回答",
            body: "有一个任务需要更多信息才能继续。",
            sessionId: sessionId,
            selectedSessionId: selectedSessionId
        )
    }

    func notifyTurnEnded(sessionId: String, selectedSessionId: String?) {
        schedule(
            identifier: "turn-ended-\(sessionId)",
            title: "DS Harness 任务已结束",
            body: "会话已停止运行，可以回来查看结果。",
            sessionId: sessionId,
            selectedSessionId: selectedSessionId
        )
    }

    func removeApproval(approvalId: String) {
        remove(identifier: "approval-\(approvalId)")
    }

    func removeQuestion(rpcId: String) {
        remove(identifier: "question-\(rpcId)")
    }

    func setPendingInteractionCount(_ count: Int) {
        NSApp.dockTile.badgeLabel = Self.dockBadgeLabel(for: count)
    }

    static func shouldDeliver(
        isApplicationActive: Bool,
        selectedSessionId: String?,
        targetSessionId: String
    ) -> Bool {
        !isApplicationActive || selectedSessionId != targetSessionId
    }

    static func dockBadgeLabel(for count: Int) -> String? {
        count > 0 ? String(count) : nil
    }

    private func schedule(
        identifier: String,
        title: String,
        body: String,
        sessionId: String,
        selectedSessionId: String?
    ) {
        let version = nextDeliveryVersion(for: identifier)
        removeFromCenter(identifier: identifier)
        Task {
            await deliver(
                identifier: identifier,
                title: title,
                body: body,
                sessionId: sessionId,
                selectedSessionId: selectedSessionId,
                version: version
            )
        }
    }

    private func deliver(
        identifier: String,
        title: String,
        body: String,
        sessionId: String,
        selectedSessionId: String?,
        version: Int
    ) async {
        guard Self.shouldDeliver(
            isApplicationActive: NSApp.isActive,
            selectedSessionId: selectedSessionId,
            targetSessionId: sessionId
        ) else { return }
        guard await isAuthorized() else { return }
        guard deliveryVersions[identifier] == version else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = sessionId
        content.userInfo = [UserInfoKey.sessionId: sessionId]
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    private func isAuthorized() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional:
            true
        case .notDetermined:
            (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        case .denied:
            false
        @unknown default:
            false
        }
    }

    private func remove(identifier: String) {
        _ = nextDeliveryVersion(for: identifier)
        removeFromCenter(identifier: identifier)
    }

    private func nextDeliveryVersion(for identifier: String) -> Int {
        let version = (deliveryVersions[identifier] ?? 0) + 1
        deliveryVersions[identifier] = version
        return version
    }

    private func removeFromCenter(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
