import XCTest

@MainActor
final class CoupleJourneyUITests: XCTestCase {
    func testFutureHorizontalSwipesDoNotOpenComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launch()

        let addButton = app.buttons["添加日程"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        let addButtonTarget = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0.2,
                dy: addButton.frame.midY / app.frame.height
            )
        )
        addButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: addButtonTarget,
                withVelocity: .slow,
                thenHoldForDuration: 0
            )

        XCTAssertFalse(app.navigationBars["新日程"].exists)
        XCTAssertTrue(app.buttons["清单"].isSelected)

        app.swipeRight()
        XCTAssertTrue(app.buttons["日历"].isSelected)

        let calendar = app.scrollViews["futureCalendarScroll"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 3))
        let calendarStart = calendar.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.25))
        let calendarEnd = calendar.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.25))
        calendarStart.press(
            forDuration: 0.1,
            thenDragTo: calendarEnd,
            withVelocity: .slow,
            thenHoldForDuration: 0
        )

        XCTAssertFalse(app.navigationBars["新日程"].exists)
        XCTAssertTrue(app.buttons["清单"].isSelected)

        app.swipeRight()
        XCTAssertTrue(app.buttons["日历"].isSelected)
        app.buttons["添加日程"].tap()
        XCTAssertTrue(app.navigationBars["新日程"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
    }

    func testPastNowFutureJourneyAndComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-now"]
        app.launch()
        XCTAssertTrue(app.staticTexts["在一起"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["528"].exists)
        XCTAssertTrue(app.staticTexts["每天都是独一无二纪念日，庆祝一下吧 🎉"].exists)

        let photoCarousel = app.scrollViews["featuredPhotoCarousel"]
        XCTAssertTrue(photoCarousel.waitForExistence(timeout: 3))
        let photoStart = photoCarousel.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5))
        let photoEnd = photoCarousel.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5))
        photoStart.press(forDuration: 0.05, thenDragTo: photoEnd)
        XCTAssertTrue(app.staticTexts["在一起"].exists)
        XCTAssertTrue(photoCarousel.isHittable)
        XCTAssertFalse(app.buttons["日历"].isHittable)

        app.swipeRight()
        XCTAssertTrue(app.buttons["全部"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["全部"].isSelected)

        let allScroll = app.scrollViews["pastAllScroll"]
        XCTAssertTrue(allScroll.waitForExistence(timeout: 3))
        allScroll.swipeUp()
        let scrollMarker = app.staticTexts["谁能拒绝坐在水边逮一下午虾呢～"]
        XCTAssertTrue(scrollMarker.waitForExistence(timeout: 3))
        let preservedY = scrollMarker.frame.minY

        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["在一起"].waitForExistence(timeout: 3))
        app.swipeRight()
        XCTAssertTrue(allScroll.waitForExistence(timeout: 3))
        XCTAssertTrue(allScroll.isHittable)
        XCTAssertEqual(scrollMarker.frame.minY, preservedY, accuracy: 4)

        app.swipeRight()
        XCTAssertTrue(app.buttons["照片"].isSelected)
        app.swipeLeft()
        XCTAssertTrue(app.buttons["全部"].isSelected)
        app.buttons["照片"].tap()
        XCTAssertTrue(app.buttons["照片"].isSelected)

        app.terminate()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-now"]
        app.launch()
        let composeButton = app.buttons["composeMemoryButton"]
        XCTAssertTrue(composeButton.waitForExistence(timeout: 5))
        composeButton.tap()
        XCTAssertTrue(app.navigationBars["记录此刻"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["saveMemoryButton"].isEnabled)
        app.buttons["取消"].tap()

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.7))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons["日历"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["日历"].isSelected)
        app.swipeLeft()
        XCTAssertTrue(app.buttons["清单"].isSelected)
        XCTAssertTrue(app.staticTexts["一起去灵隐寺还愿吧"].waitForExistence(timeout: 3))
    }
}
