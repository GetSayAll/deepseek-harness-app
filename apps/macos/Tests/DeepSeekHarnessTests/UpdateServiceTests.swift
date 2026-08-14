import XCTest
@testable import DeepSeekHarness

final class UpdateServiceTests: XCTestCase {
    func testPreviewFeedIsUsedOnlyWhenEnabledAndResolved() throws {
        let stable = "https://example.com/stable.xml"
        let preview = try XCTUnwrap(URL(string: "https://example.com/preview.xml"))
        var selection = UpdateFeedSelection(stableFeedURLString: stable)

        XCTAssertEqual(selection.feedURLString(includesPreviewUpdates: true), stable)
        selection.usePreviewFeed(preview)
        XCTAssertEqual(selection.feedURLString(includesPreviewUpdates: true), preview.absoluteString)
        XCTAssertEqual(selection.feedURLString(includesPreviewUpdates: false), stable)
        selection.useStableFeed()
        XCTAssertEqual(selection.feedURLString(includesPreviewUpdates: true), stable)
    }
}
