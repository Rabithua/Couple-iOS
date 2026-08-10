import XCTest

@MainActor
final class CoupleJourneyUITests: XCTestCase {
    func testPastNowFutureJourneyAndComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-now"]
        app.launch()
        XCTAssertTrue(app.staticTexts["在一起"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["528"].exists)
        XCTAssertTrue(app.staticTexts["每天都是独一无二纪念日，庆祝一下吧 🎉"].exists)

        app.swipeRight()
        XCTAssertTrue(app.buttons["全部"].waitForExistence(timeout: 3))
        app.buttons["照片"].tap()
        XCTAssertTrue(app.buttons["照片"].isSelected)

        app.terminate()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-now"]
        app.launch()
        let composeButton = app.descendants(matching: .any)["composeMemoryButton"]
        XCTAssertTrue(composeButton.waitForExistence(timeout: 5))
        composeButton.tap()
        XCTAssertTrue(app.navigationBars["记录此刻"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["saveMemoryButton"].isEnabled)
        app.buttons["取消"].tap()

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.7))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons["日历"].waitForExistence(timeout: 3))
        app.buttons["清单"].tap()
        XCTAssertTrue(app.buttons["清单"].isSelected)
        XCTAssertTrue(app.staticTexts["一起去灵隐寺还愿吧"].waitForExistence(timeout: 3))
    }
}
