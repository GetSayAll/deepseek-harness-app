import XCTest
@testable import DeepSeekHarness

@MainActor
final class AppDelegateTests: XCTestCase {
    func testVisibleMainWindowIsRecognized() {
        XCTAssertTrue(AppDelegate.isVisibleMainWindow(identifier: "main-AppWindow-test", visible: true))
    }

    func testAboutAndHiddenMainWindowsDoNotSuppressMainWindowCreation() {
        XCTAssertFalse(AppDelegate.isVisibleMainWindow(identifier: "about", visible: true))
        XCTAssertFalse(AppDelegate.isVisibleMainWindow(identifier: "main-AppWindow-test", visible: false))
    }

    func testNotificationsAreSuppressedOnlyForTheVisibleSession() {
        XCTAssertFalse(SystemNotificationService.shouldDeliver(
            isApplicationActive: true,
            selectedSessionId: "selected",
            targetSessionId: "selected"
        ))
        XCTAssertTrue(SystemNotificationService.shouldDeliver(
            isApplicationActive: true,
            selectedSessionId: "selected",
            targetSessionId: "background"
        ))
        XCTAssertTrue(SystemNotificationService.shouldDeliver(
            isApplicationActive: false,
            selectedSessionId: "selected",
            targetSessionId: "selected"
        ))
    }

    func testDockBadgeShowsOnlyPositivePendingCounts() {
        XCTAssertNil(SystemNotificationService.dockBadgeLabel(for: 0))
        XCTAssertEqual(SystemNotificationService.dockBadgeLabel(for: 3), "3")
    }
}
