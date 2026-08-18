import XCTest

@MainActor
final class CoupleJourneyUITests: XCTestCase {
    func testSettingsIsAvailableAfterTheTodoList() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launch()

        app.buttons["设置"].tap()

        XCTAssertTrue(app.buttons["设置"].isSelected)
        let settingsForm = app.descendants(matching: .any)["settingsForm"]
        XCTAssertTrue(settingsForm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editDisplayNameButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["startedOnDatePicker"].exists)
        XCTAssertFalse(app.buttons["保存日期"].exists)
        XCTAssertTrue(app.switches["hapticsToggle"].exists)
        XCTAssertFalse(app.buttons["futureAddButton"].exists)

        settingsForm.swipeUp()
        settingsForm.swipeUp()
        XCTAssertTrue(app.buttons["leaveSpaceButton"].waitForExistence(timeout: 2))
    }

    func testLongPressTodoOffersEditAndDeleteActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launch()

        app.buttons["清单"].tap()
        let todo = app.scrollViews["futureListScroll"]
            .staticTexts["一起去灵隐寺还愿吧"]
        XCTAssertTrue(todo.waitForExistence(timeout: 5))
        todo.press(forDuration: 1)

        XCTAssertTrue(app.buttons["编辑"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["删除"].exists)
        app.buttons["编辑"].tap()
        XCTAssertTrue(app.navigationBars["编辑清单"].waitForExistence(timeout: 2))
    }

    func testFutureAddButtonPresentsImmediately() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launch()

        let addButton = app.buttons["futureAddButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        XCTAssertTrue(app.navigationBars["新日程"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.navigationBars.matching(identifier: "新日程").count, 1)
        let endTimeToggle = app.switches["结束时间"]
        XCTAssertTrue(endTimeToggle.waitForExistence(timeout: 2))
        XCTAssertEqual(endTimeToggle.value as? String, "1")
        app.buttons["取消"].tap()

        app.buttons["清单"].tap()
        XCTAssertTrue(app.buttons["清单"].isSelected)
        app.buttons["futureAddButton"].tap()
        XCTAssertTrue(app.navigationBars["新清单"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.navigationBars.matching(identifier: "新清单").count, 1)
    }

    func testCalendarDayTapExpandsAgendaBeforeCreatingEvent() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launch()

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let eventDate = Calendar.current.date(byAdding: .day, value: 3, to: .now) else {
            return XCTFail("Unable to make the demo event date")
        }
        let dayIdentifier = "calendarDay-\(formatter.string(from: eventDate))"
        let day = app.buttons[dayIdentifier]
        XCTAssertTrue(day.waitForExistence(timeout: 5))

        day.tap()

        let agenda = app.descendants(matching: .any)[
            "calendarAgenda-\(formatter.string(from: eventDate))"
        ]
        XCTAssertTrue(agenda.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["calendarAgendaEvent-60000000-0000-4000-8000-000000000001"].exists)
        XCTAssertFalse(app.navigationBars["新日程"].exists)

        app.buttons["calendarAgendaNewEventButton"].tap()
        XCTAssertTrue(app.navigationBars["新日程"].waitForExistence(timeout: 2))
    }

    func testFutureHorizontalSwipesDoNotOpenNewItem() {
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
        let visibleRightSideDay = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'calendarDay-'"))
            .allElementsBoundByIndex
            .first { day in
                day.isHittable && day.frame.midX > app.frame.width * 0.65
            }
        guard let day = visibleRightSideDay else {
            return XCTFail("Expected a visible calendar day to start the page swipe")
        }
        let dateIdentifier = String(day.identifier.dropFirst("calendarDay-".count))
        let calendarStart = day.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
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
        XCTAssertFalse(
            app.descendants(matching: .any)["calendarAgenda-\(dateIdentifier)"]
                .waitForExistence(timeout: 1)
        )
        app.buttons["添加日程"].tap()
        XCTAssertTrue(app.navigationBars["新日程"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
    }

    func testNowCalendarRoundTripsDoNotOpenNewEvent() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-now"]
        app.launch()

        XCTAssertTrue(app.staticTexts["在一起"].waitForExistence(timeout: 5))

        for verticalPosition in [0.52, 0.66, 0.8] {
            let start = app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.9, dy: verticalPosition)
            )
            let end = app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.1, dy: verticalPosition)
            )
            start.press(
                forDuration: 0.05,
                thenDragTo: end,
                withVelocity: .slow,
                thenHoldForDuration: 0
            )

            XCTAssertTrue(app.buttons["日历"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["日历"].isSelected)
            XCTAssertFalse(app.navigationBars["新日程"].waitForExistence(timeout: 1))

            app.swipeRight()
            XCTAssertTrue(app.staticTexts["在一起"].waitForExistence(timeout: 3))
            XCTAssertFalse(app.navigationBars["新日程"].exists)
        }
    }

    func testPhotoCarouselSwipeStaysOnNow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-now"]
        app.launch()

        let photoCarousel = app.scrollViews["featuredPhotoCarousel"]
        XCTAssertTrue(photoCarousel.waitForExistence(timeout: 5))
        let firstPhoto = app.descendants(matching: .any)["featuredPhoto-0"]
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 3))
        let initialPhotoX = firstPhoto.frame.minX

        photoCarousel.swipeLeft()

        XCTAssertLessThan(firstPhoto.frame.minX, initialPhotoX - 10)
        XCTAssertTrue(app.staticTexts["在一起"].exists)
        XCTAssertFalse(app.buttons["日历"].isHittable)
    }

    func testDiagonalPageSwipeDoesNotMoveVerticalScroll() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-past"]
        app.launch()

        let allScroll = app.scrollViews["pastAllScroll"]
        XCTAssertTrue(allScroll.waitForExistence(timeout: 5))
        allScroll.swipeUp()

        let scrollMarker = app.staticTexts["谁能拒绝坐在水边逮一下午虾呢～"]
        XCTAssertTrue(scrollMarker.waitForExistence(timeout: 3))
        let initialMarkerY = scrollMarker.frame.minY

        let start = allScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.35))
        let end = allScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.53))
        start.press(
            forDuration: 0.05,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0
        )

        XCTAssertTrue(app.staticTexts["在一起"].waitForExistence(timeout: 3))
        app.swipeRight()
        XCTAssertTrue(allScroll.waitForExistence(timeout: 3))
        XCTAssertEqual(scrollMarker.frame.minY, initialMarkerY, accuracy: 6)
    }

    func testFeaturedPhotoPreviewReturnsToItsSource() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-now"]
        app.launch()

        let sourcePhoto = app.descendants(matching: .any)["featuredPhoto-0"]
        XCTAssertTrue(sourcePhoto.waitForExistence(timeout: 5))
        let sourceX = sourcePhoto.frame.minX
        sourcePhoto.tap()

        let preview = app.descendants(matching: .any)
            .matching(identifier: "photoPreviewPager")
            .firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertEqual(preview.frame.minY, windowFrame.minY, accuracy: 1)
        XCTAssertEqual(preview.frame.maxY, windowFrame.maxY, accuracy: 1)
        XCTAssertFalse(app.buttons["photoPreviewCloseButton"].exists)

        let previewPhoto = app.buttons[
            "photoPreviewPage-70000000-0000-4000-8000-000000000001"
        ]
        XCTAssertTrue(previewPhoto.waitForExistence(timeout: 2))
        XCTAssertEqual(previewPhoto.frame.minY, windowFrame.minY, accuracy: 1)
        XCTAssertEqual(previewPhoto.frame.maxY, windowFrame.maxY, accuracy: 1)
        XCTAssertFalse(app.descendants(matching: .any)["photoPreviewPageIndicator"].exists)
        let initialZoomValue = previewPhoto.value as? String
        previewPhoto.doubleTap()
        XCTAssertTrue(previewPhoto.waitForExistence(timeout: 1))
        XCTAssertNotEqual(previewPhoto.value as? String, initialZoomValue)

        previewPhoto.doubleTap()
        XCTAssertEqual(previewPhoto.value as? String, initialZoomValue)
        XCTAssertTrue(preview.waitForExistence(timeout: 1))

        previewPhoto.tap()

        XCTAssertTrue(sourcePhoto.waitForExistence(timeout: 3))
        XCTAssertEqual(sourcePhoto.frame.minX, sourceX, accuracy: 4)
        XCTAssertTrue(app.staticTexts["在一起"].exists)
    }

    func testPastPhotoPreviewPagesAndPreservesLongPressActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-past"]
        app.launch()

        let photosTab = app.buttons["照片"]
        XCTAssertTrue(photosTab.waitForExistence(timeout: 5))
        photosTab.tap()
        XCTAssertTrue(photosTab.isSelected)

        let firstPhoto = app.buttons[
            "photoPreviewSource-past.pastPhotosScroll.50000000-0000-4000-8000-000000000001-70000000-0000-4000-8000-000000000001"
        ]
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 3))
        firstPhoto.tap()

        let preview = app.descendants(matching: .any)
            .matching(identifier: "photoPreviewPager")
            .firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 3))

        let firstPreviewPhoto = app.buttons[
            "photoPreviewPage-70000000-0000-4000-8000-000000000001"
        ]
        XCTAssertTrue(firstPreviewPhoto.waitForExistence(timeout: 2))
        let initialZoomValue = firstPreviewPhoto.value as? String
        firstPreviewPhoto.pinch(withScale: 2, velocity: 1)
        XCTAssertNotEqual(firstPreviewPhoto.value as? String, initialZoomValue)

        preview.swipeLeft()
        XCTAssertTrue(firstPreviewPhoto.isHittable)

        firstPreviewPhoto.pinch(withScale: 0.1, velocity: -2)
        preview.swipeLeft()

        let secondPhoto = app.buttons[
            "photoPreviewPage-70000000-0000-4000-8000-000000000002"
        ]
        XCTAssertTrue(secondPhoto.waitForExistence(timeout: 2))
        XCTAssertFalse(app.descendants(matching: .any)["photoPreviewPageIndicator"].exists)
        secondPhoto.tap()

        XCTAssertTrue(photosTab.waitForExistence(timeout: 3))
        XCTAssertTrue(photosTab.isSelected)
        let returnedPhoto = app.buttons[
            "photoPreviewSource-past.pastPhotosScroll.50000000-0000-4000-8000-000000000001-70000000-0000-4000-8000-000000000002"
        ]
        XCTAssertTrue(returnedPhoto.waitForExistence(timeout: 3))
        returnedPhoto.press(forDuration: 1)
        XCTAssertTrue(app.buttons["编辑"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["删除"].exists)
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
        photoCarousel.swipeLeft()
        let carouselMarker = app.descendants(matching: .any)["featuredPhoto-0"]
        XCTAssertTrue(carouselMarker.waitForExistence(timeout: 2))
        let preservedCarouselX = carouselMarker.frame.minX
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
        XCTAssertEqual(carouselMarker.frame.minX, preservedCarouselX, accuracy: 4)
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

    func testNowBottomGestureSeparatesPageSwipeFromComposePull() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-now"]
        app.launch()

        var composeButton = app.buttons["composeMemoryButton"]
        XCTAssertTrue(composeButton.waitForExistence(timeout: 5))

        let diagonalPageTarget = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0.05,
                dy: max((composeButton.frame.midY - 40) / app.frame.height, 0.1)
            )
        )
        composeButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.05,
                thenDragTo: diagonalPageTarget,
                withVelocity: .slow,
                thenHoldForDuration: 0
            )

        XCTAssertFalse(app.navigationBars["记录此刻"].exists)
        XCTAssertTrue(app.buttons["日历"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["日历"].isSelected)

        app.swipeRight()
        composeButton = app.buttons["composeMemoryButton"]
        XCTAssertTrue(composeButton.waitForExistence(timeout: 3))
        composeButton.tap()
        XCTAssertTrue(app.navigationBars["记录此刻"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
        XCTAssertTrue(composeButton.waitForExistence(timeout: 3))

        let composeTarget = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: composeButton.frame.midX / app.frame.width,
                dy: max((composeButton.frame.midY - 90) / app.frame.height, 0.1)
            )
        )
        composeButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.05,
                thenDragTo: composeTarget,
                withVelocity: .slow,
                thenHoldForDuration: 0
            )

        XCTAssertTrue(app.navigationBars["记录此刻"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.navigationBars.matching(identifier: "记录此刻").count, 1)
    }
}
