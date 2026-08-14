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
}
