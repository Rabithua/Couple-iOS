import XCTest

@MainActor
final class CoupleJourneyUITests: XCTestCase {
    func testOnboardingCreateAndJoinFormsAndOuterEdgeHitTargets() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-onboarding"]
        app.launchInSimplifiedChinese()

        let start = app.buttons["onboardingStartButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(start.frame.height, 44)
        start.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()

        let choice = app.descendants(matching: .any)["onboardingSpaceChoice"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        app.buttons["onboardingJoinSpaceButton"].tap()
        let joinNameField = app.textFields["onboardingDisplayNameField"]
        XCTAssertTrue(joinNameField.waitForExistence(timeout: 2))
        let birthdayPicker = app.descendants(matching: .any)["onboardingBirthdayPicker"]
        XCTAssertTrue(birthdayPicker.exists)
        let initialBirthdayPickerFrame = birthdayPicker.frame
        XCTAssertLessThanOrEqual(initialBirthdayPickerFrame.minX, joinNameField.frame.minX)

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(birthdayPicker.waitForExistence(timeout: 2))
        XCTAssertEqual(birthdayPicker.frame.minX, initialBirthdayPickerFrame.minX, accuracy: 2)
        birthdayPicker.tap()
        let birthdayEditor = app.descendants(matching: .any)["onboardingBirthdayEditor"]
        XCTAssertTrue(birthdayEditor.waitForExistence(timeout: 2))
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(birthdayEditor.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.textFields["onboardingInviteCodeField"].exists)

        app.buttons["onboardingBackButton"].tap()
        XCTAssertTrue(app.buttons["onboardingCreateSpaceButton"].waitForExistence(timeout: 2))
        app.buttons["onboardingCreateSpaceButton"].tap()
        let name = app.textFields["onboardingDisplayNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 2))
        XCTAssertFalse(app.textFields["onboardingInviteCodeField"].exists)
        name.tap()
        name.typeText("测试用户")

        let continueButton = app.buttons["onboardingContinueButton"]
        XCTAssertTrue(continueButton.isEnabled)
        XCTAssertGreaterThanOrEqual(continueButton.frame.height, 44)
        continueButton.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.12)).tap()

        XCTAssertTrue(app.buttons["homeInviteCode"].waitForExistence(timeout: 5))
    }

    func testUnpairedHomeShowsInviteCodeAndSharesFromItsOuterEdge() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-unpaired", "-ui-testing-now"]
        app.launchInSimplifiedChinese()

        let nowScroll = app.scrollViews["nowScroll"]
        XCTAssertTrue(nowScroll.waitForExistence(timeout: 5))
        let inviteRow = nowScroll.buttons["homeInviteCode"]
        XCTAssertTrue(inviteRow.waitForExistence(timeout: 5))
        XCTAssertTrue(inviteRow.label.contains("OURSINCE"))
        let emptyAnniversary = nowScroll.staticTexts["还没有纪念日"]
        XCTAssertTrue(emptyAnniversary.exists)
        XCTAssertTrue(nowScroll.staticTexts["还没有共同清单"].exists)
        XCTAssertFalse(nowScroll.staticTexts["在一起"].exists)
        XCTAssertFalse(nowScroll.staticTexts["每天都是独一无二纪念日，庆祝一下吧 🎉"].exists)
        XCTAssertLessThan(inviteRow.frame.minY, emptyAnniversary.frame.minY)
        XCTAssertEqual(inviteRow.frame.minX, emptyAnniversary.frame.minX, accuracy: 1)

        inviteRow.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.12)).tap()

        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 3))
    }

    func testSettingsIsAvailableAfterTheTodoList() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launchInSimplifiedChinese()

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
        XCTAssertTrue(app.buttons["设置"].isSelected)

        settingsForm.swipeRight()
        XCTAssertTrue(app.buttons["清单"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["清单"].isSelected)
    }

    func testSettingsLanguagePickerSwitchesImmediately() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launchInSimplifiedChinese()

        openSettings(in: app, labels: ["设置", "Settings", "設定"])
        chooseLanguage(in: app, labels: ["跟随系统", "System Default", "跟隨系統"])
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 5))

        openSettings(in: app, labels: ["设置"])
        chooseLanguage(in: app, labels: ["English"])
        XCTAssertTrue(app.buttons["Calendar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["List"].exists)
        XCTAssertTrue(app.buttons["Settings"].exists)

        app.buttons["Calendar"].tap()
        let calendar = Calendar.current
        guard let currentMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: .now)
        ) else {
            return XCTFail("Unable to make the current month date")
        }
        let englishMonthTitle = app.staticTexts[
            "calendarMonthTitle-\(currentMonthStart.dateOnlyTestIdentifier)"
        ]
        XCTAssertTrue(englishMonthTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(englishMonthTitle.label, localizedMonthTitle(locale: "en_US"))

        openSettings(in: app, labels: ["Settings"])
        XCTAssertTrue(app.staticTexts["Preferences"].waitForExistence(timeout: 5))
        chooseLanguage(in: app, labels: ["繁體中文"])
        XCTAssertTrue(app.buttons["日曆"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["清單"].exists)
        XCTAssertTrue(app.buttons["設定"].exists)

        openSettings(in: app, labels: ["設定"])
        XCTAssertTrue(app.staticTexts["個人資料"].waitForExistence(timeout: 5))
        chooseLanguage(in: app, labels: ["跟隨系統"])
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 5))
    }

    func testEnglishComposePromptStaysOnOneLine() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launchInSimplifiedChinese()

        openSettings(in: app, labels: ["设置", "Settings", "設定"])
        chooseLanguage(in: app, labels: ["English"])
        app.buttons["Calendar"].tap()
        app.swipeRight()

        let composeButton = app.buttons["composeMemoryButton"]
        XCTAssertTrue(composeButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(composeButton.frame.width, 180)
        XCTAssertLessThanOrEqual(composeButton.frame.height, 48)
    }

    func testLongPressTodoOffersEditAndDeleteActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launchInSimplifiedChinese()

        app.buttons["清单"].tap()
        let todo = app.scrollViews["futureListScroll"]
            .staticTexts["一起去灵隐寺还愿吧"]
        XCTAssertTrue(todo.waitForExistence(timeout: 5))
        todo.press(forDuration: 1)

        XCTAssertTrue(app.buttons["编辑"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["删除"].exists)
        app.buttons["编辑"].tap()
        let editorNavigationBar = app.navigationBars["编辑清单"]
        XCTAssertTrue(editorNavigationBar.waitForExistence(timeout: 2))
        assertUsesMediumContentSheet(editorNavigationBar, in: app)
    }

    func testTodoListUsesSingleLineTitlesAndSeparateInteractions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launch(language: "en", locale: "en_US")

        app.buttons["List"].tap()
        let title = "Let's go back to Lingyin Temple to fulfill our vow"
        let todoID = "40000000-0000-4000-8000-000000000001"
        let list = app.scrollViews["futureListScroll"]
        let titleText = list.staticTexts[title]
        XCTAssertTrue(titleText.waitForExistence(timeout: 5))

        let titleButton = list.buttons["todoTitleButton-\(todoID)"]
        XCTAssertTrue(titleButton.waitForExistence(timeout: 2))
        XCTAssertLessThanOrEqual(titleButton.frame.height, 44.5)
        let checkbox = list.buttons["Complete \(title)"]
        XCTAssertTrue(checkbox.exists)
        XCTAssertGreaterThanOrEqual(checkbox.frame.height, 43.5)
        titleButton.tap()
        XCTAssertTrue(app.navigationBars["Edit List Item"].waitForExistence(timeout: 2))
        app.buttons["Cancel"].tap()

        list.buttons["Complete \(title)"].tap()

        XCTAssertTrue(list.buttons["Reopen \(title)"].waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            list.buttons["todoTitleButton-\(todoID)"].frame.height,
            44.5
        )
    }

    func testHomeTodoTitleOpensEditorWithoutChangingCompletion() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-now"]
        app.launchInSimplifiedChinese()

        let title = "一起去灵隐寺还愿吧"
        let todoID = "40000000-0000-4000-8000-000000000001"
        let nowScroll = app.scrollViews["nowScroll"]
        XCTAssertTrue(nowScroll.waitForExistence(timeout: 5))
        let titleButton = nowScroll.buttons["todoTitleButton-\(todoID)"]
        XCTAssertTrue(titleButton.waitForExistence(timeout: 5))
        for _ in 0..<3 where titleButton.isHittable == false {
            nowScroll.swipeUp()
        }
        XCTAssertTrue(titleButton.isHittable)
        XCTAssertTrue(nowScroll.buttons["完成\(title)"].exists)

        titleButton.tap()

        XCTAssertTrue(app.navigationBars["编辑清单"].waitForExistence(timeout: 2))
        app.buttons["取消"].tap()
        XCTAssertTrue(nowScroll.buttons["完成\(title)"].waitForExistence(timeout: 3))
    }

    func testHomeTodoTitlePageSwipeDoesNotOpenEditor() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-now"]
        app.launchInSimplifiedChinese()

        let todoID = "40000000-0000-4000-8000-000000000001"
        let nowScroll = app.scrollViews["nowScroll"]
        XCTAssertTrue(nowScroll.waitForExistence(timeout: 5))
        let titleButton = nowScroll.buttons["todoTitleButton-\(todoID)"]
        XCTAssertTrue(titleButton.waitForExistence(timeout: 5))
        for _ in 0..<3 where titleButton.isHittable == false {
            nowScroll.swipeUp()
        }
        XCTAssertTrue(titleButton.isHittable)

        let start = titleButton.coordinate(
            withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)
        )
        let destination = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0.12,
                dy: titleButton.frame.midY / app.frame.height
            )
        )
        start.press(
            forDuration: 0.1,
            thenDragTo: destination,
            withVelocity: .slow,
            thenHoldForDuration: 0
        )

        XCTAssertTrue(app.buttons["日历"].isSelected)
        XCTAssertFalse(app.navigationBars["编辑清单"].waitForExistence(timeout: 1))
    }

    func testCalendarAgendaTodoSeparatesTitleAndCheckbox() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launchInSimplifiedChinese()

        guard let todoDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) else {
            return XCTFail("Unable to make the demo todo date")
        }
        let todoID = "40000000-0000-4000-8000-000000000001"
        let dateIdentifier = todoDate.dateOnlyTestIdentifier
        let day = app.buttons["calendarDay-\(dateIdentifier)"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()

        let agenda = app.descendants(matching: .any)["calendarAgenda-\(dateIdentifier)"]
        XCTAssertTrue(agenda.waitForExistence(timeout: 3))
        let titleButton = agenda.buttons["todoTitleButton-\(todoID)"]
        XCTAssertTrue(titleButton.waitForExistence(timeout: 2))
        let checkbox = agenda.buttons["完成一起去灵隐寺还愿吧"]
        XCTAssertTrue(checkbox.exists)
        XCTAssertGreaterThanOrEqual(checkbox.frame.height, 43.5)

        titleButton.tap()
        XCTAssertTrue(app.navigationBars["编辑清单"].waitForExistence(timeout: 2))
        app.buttons["取消"].tap()

        agenda.buttons["完成一起去灵隐寺还愿吧"].tap()
        XCTAssertTrue(
            agenda.buttons["重新打开一起去灵隐寺还愿吧"]
                .waitForExistence(timeout: 5)
        )
    }

    func testFutureAddButtonPresentsImmediately() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launchInSimplifiedChinese()

        let addButton = app.buttons["futureAddButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        let eventNavigationBar = app.navigationBars["新日程"]
        XCTAssertTrue(eventNavigationBar.waitForExistence(timeout: 2))
        assertUsesMediumContentSheet(eventNavigationBar, in: app)
        XCTAssertEqual(app.navigationBars.matching(identifier: "新日程").count, 1)
        let endTimeToggle = app.switches["结束时间"]
        XCTAssertTrue(endTimeToggle.waitForExistence(timeout: 2))
        XCTAssertEqual(endTimeToggle.value as? String, "1")
        app.buttons["取消"].tap()

        app.buttons["清单"].tap()
        XCTAssertTrue(app.buttons["清单"].isSelected)
        app.buttons["futureAddButton"].tap()
        let todoNavigationBar = app.navigationBars["新清单"]
        XCTAssertTrue(todoNavigationBar.waitForExistence(timeout: 2))
        assertUsesMediumContentSheet(todoNavigationBar, in: app)
        XCTAssertEqual(app.navigationBars.matching(identifier: "新清单").count, 1)
    }

    func testCalendarDayTapExpandsAgendaBeforeCreatingEvent() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launchInSimplifiedChinese()

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
        XCTAssertTrue(
            app.buttons["calendarAgendaEvent-60000000-0000-4000-8000-000000000001"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.staticTexts["这天还没有安排"].exists)
        XCTAssertFalse(app.navigationBars["新日程"].exists)

        let anniversaryButton = app.buttons["calendarAgendaNewAnniversaryButton"]
        XCTAssertTrue(anniversaryButton.exists)
        XCTAssertGreaterThanOrEqual(anniversaryButton.frame.height, 43.5)
        anniversaryButton.coordinate(
            withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)
        ).tap()
        XCTAssertTrue(app.navigationBars["新纪念日"].waitForExistence(timeout: 2))
        app.buttons["取消"].tap()

        let eventButton = app.buttons["calendarAgendaNewEventButton"]
        XCTAssertGreaterThanOrEqual(eventButton.frame.height, 43.5)
        eventButton.coordinate(
            withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)
        ).tap()
        XCTAssertTrue(app.navigationBars["新日程"].waitForExistence(timeout: 2))
    }

    func testCalendarCanBrowseAndOpenPastMonth() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launchInSimplifiedChinese()

        let calendar = Calendar.current
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: .now),
              let currentMonthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: .now)
              ),
              let previousMonthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: previousMonth)
              ),
              let pastDate = calendar.date(byAdding: .day, value: 14, to: previousMonthStart)
        else {
            return XCTFail("Unable to make a date in the previous month")
        }

        let calendarScroll = app.scrollViews["futureCalendarScroll"]
        XCTAssertTrue(calendarScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts[
                "calendarMonthTitle-\(currentMonthStart.dateOnlyTestIdentifier)"
            ].waitForExistence(timeout: 5)
        )

        let pastDay = app.buttons["calendarDay-\(pastDate.dateOnlyTestIdentifier)"]
        for _ in 0..<4 where pastDay.isHittable == false {
            calendarScroll.swipeDown()
        }
        XCTAssertTrue(pastDay.isHittable)

        pastDay.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "calendarAgenda-\(pastDate.dateOnlyTestIdentifier)"
            ].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["calendarAgendaNewEventButton"].exists)
        XCTAssertTrue(app.buttons["calendarAgendaNewAnniversaryButton"].exists)
    }

    func testCalendarDayExpansionPreservesScrollPosition() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launchInSimplifiedChinese()

        let today = app.buttons["calendarDay-\(Date.now.dateOnlyTestIdentifier)"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertTrue(today.isHittable)
        let todayY = today.frame.minY

        today.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "calendarAgenda-\(Date.now.dateOnlyTestIdentifier)"
            ].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["这天还没有安排"].exists)
        XCTAssertEqual(today.frame.minY, todayY, accuracy: 4)
    }

    func testCalendarHorizontalRoundTripsPreserveScrollPosition() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launchInSimplifiedChinese()

        let today = app.buttons["calendarDay-\(Date.now.dateOnlyTestIdentifier)"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertTrue(today.isHittable)
        let todayY = today.frame.minY

        for _ in 0..<3 {
            app.swipeLeft()
            XCTAssertTrue(app.buttons["清单"].isSelected)
            app.swipeRight()
            XCTAssertTrue(app.buttons["日历"].isSelected)
            XCTAssertTrue(today.isHittable)
            XCTAssertEqual(today.frame.minY, todayY, accuracy: 4)
        }
    }

    func testCalendarTodayButtonAndNavigationReturnToToday() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launchInSimplifiedChinese()

        let calendarScroll = app.scrollViews["futureCalendarScroll"]
        XCTAssertTrue(calendarScroll.waitForExistence(timeout: 5))
        let today = app.buttons["calendarDay-\(Date.now.dateOnlyTestIdentifier)"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertTrue(today.isHittable)
        today.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "calendarAgenda-\(Date.now.dateOnlyTestIdentifier)"
            ].waitForExistence(timeout: 3)
        )

        for _ in 0..<4 where today.isHittable {
            calendarScroll.swipeUp()
        }
        XCTAssertFalse(today.isHittable)

        let todayButton = app.buttons["calendarTodayButton"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 3))
        todayButton.tap()
        XCTAssertTrue(waitForHittable(today, timeout: 3))
        XCTAssertTrue(todayButton.waitForNonExistence(timeout: 2))

        for _ in 0..<4 where today.isHittable {
            calendarScroll.swipeDown()
        }
        XCTAssertFalse(today.isHittable)
        XCTAssertTrue(todayButton.waitForExistence(timeout: 3))

        app.buttons["日历"].tap()

        XCTAssertTrue(waitForHittable(today, timeout: 3))
        XCTAssertTrue(todayButton.waitForNonExistence(timeout: 2))

        for _ in 0..<4 where today.isHittable {
            calendarScroll.swipeUp()
        }
        XCTAssertFalse(today.isHittable)
        app.buttons["清单"].tap()
        XCTAssertTrue(app.buttons["清单"].isSelected)

        app.buttons["日历"].tap()

        XCTAssertTrue(waitForHittable(today, timeout: 3))
        XCTAssertTrue(todayButton.waitForNonExistence(timeout: 2))
    }

    func testCalendarMonthTitleStaysPinnedAsMonthChanges() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launchInSimplifiedChinese()

        let calendar = Calendar.current
        guard let currentMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: .now)
        ), let nextMonthStart = calendar.date(
            byAdding: .month,
            value: 1,
            to: currentMonthStart
        ) else {
            return XCTFail("Unable to make calendar month dates")
        }

        let calendarScroll = app.scrollViews["futureCalendarScroll"]
        XCTAssertTrue(calendarScroll.waitForExistence(timeout: 5))
        let currentTitle = app.staticTexts[
            "calendarMonthTitle-\(currentMonthStart.dateOnlyTestIdentifier)"
        ]
        XCTAssertTrue(currentTitle.waitForExistence(timeout: 5))
        let pinnedY = currentTitle.frame.minY
        let nextTitle = app.staticTexts[
            "calendarMonthTitle-\(nextMonthStart.dateOnlyTestIdentifier)"
        ]

        for _ in 0..<5 {
            guard nextTitle.exists == false || nextTitle.frame.minY > pinnedY + 4 else {
                break
            }
            calendarScroll.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)
            ).press(
                forDuration: 0.05,
                thenDragTo: calendarScroll.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)
                ),
                withVelocity: .slow,
                thenHoldForDuration: 0
            )
        }

        XCTAssertTrue(nextTitle.isHittable)
        XCTAssertEqual(nextTitle.frame.minY, pinnedY, accuracy: 4)
    }

    func testFutureHorizontalSwipesDoNotOpenNewItem() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
        app.launchInSimplifiedChinese()

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
        app.launchInSimplifiedChinese()

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
        app.launchInSimplifiedChinese()

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
        app.launchInSimplifiedChinese()

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
        app.launchInSimplifiedChinese()

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
        app.launchInSimplifiedChinese()

        let photosTab = app.buttons["照片"]
        XCTAssertTrue(photosTab.waitForExistence(timeout: 5))
        photosTab.tap()
        XCTAssertTrue(photosTab.isSelected)

        let firstPhoto = app.buttons[
            "photoPreviewSource-past.pastPhotosScroll.50000000-0000-4000-8000-000000000001-70000000-0000-4000-8000-000000000001"
        ]
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 3))
        let lastPhotoInFirstRow = app.buttons[
            "photoPreviewSource-past.pastPhotosScroll.50000000-0000-4000-8000-000000000001-70000000-0000-4000-8000-000000000002"
        ]
        XCTAssertTrue(lastPhotoInFirstRow.waitForExistence(timeout: 3))
        let photosScroll = app.scrollViews["pastPhotosScroll"]
        let leadingInset = firstPhoto.frame.minX - photosScroll.frame.minX
        let trailingInset = photosScroll.frame.maxX - lastPhotoInFirstRow.frame.maxX
        XCTAssertEqual(trailingInset, leadingInset, accuracy: 1)
        XCTAssertEqual(
            firstPhoto.frame.width / lastPhotoInFirstRow.frame.width,
            (2 / 3) / 1.5,
            accuracy: 0.02
        )
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
        app.launchInSimplifiedChinese()
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
        app.launchInSimplifiedChinese()
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

    func testComposerCapturesLocationAndPersistsIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-now", "-ui-testing-location"]
        app.launchInSimplifiedChinese()

        let composeButton = app.buttons["composeMemoryButton"]
        XCTAssertTrue(composeButton.waitForExistence(timeout: 5))
        composeButton.tap()
        let composerNavigationBar = app.navigationBars["记录此刻"]
        XCTAssertTrue(composerNavigationBar.waitForExistence(timeout: 3))

        let value = app.staticTexts["memoryLocationValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 15))
        let remove = app.buttons["removeMemoryLocationButton"]
        XCTAssertTrue(remove.exists)
        for _ in 0..<3 where !remove.isHittable { app.swipeUp() }
        XCTAssertTrue(remove.isHittable)
        XCTAssertGreaterThanOrEqual(remove.frame.height, 44)
        let capturedLocation = value.label
        XCTAssertFalse(capturedLocation.isEmpty)

        let content = app.textFields["写下此刻……"]
        XCTAssertTrue(content.exists)
        content.tap()
        content.typeText("位置验收动态")
        let save = app.buttons["saveMemoryButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.staticTexts["位置验收动态"].waitForExistence(timeout: 5))
        app.swipeRight()
        XCTAssertTrue(app.staticTexts[capturedLocation].waitForExistence(timeout: 5))
    }

    func testNowBottomGestureSeparatesPageSwipeFromComposePull() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-demo", "-ui-testing-now"]
        app.launchInSimplifiedChinese()

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

    func testPrimaryNavigationIsLocalizedInAllSupportedLanguages() {
        continueAfterFailure = false
        let expectations = [
            (language: "zh-Hans", locale: "zh_CN", calendar: "日历", list: "清单", settings: "设置"),
            (language: "en", locale: "en_US", calendar: "Calendar", list: "List", settings: "Settings"),
            (language: "zh-Hant", locale: "zh_TW", calendar: "日曆", list: "清單", settings: "設定")
        ]

        for expectation in expectations {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing-demo", "-ui-testing-future"]
            app.launch(language: expectation.language, locale: expectation.locale)

            XCTAssertTrue(app.buttons[expectation.calendar].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons[expectation.list].exists)
            XCTAssertTrue(app.buttons[expectation.settings].exists)
            app.terminate()
        }
    }

    private func openSettings(in app: XCUIApplication, labels: [String]) {
        for label in labels {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 2) {
                button.tap()
                return
            }
        }
        XCTFail("Settings tab was not available")
    }

    private func chooseLanguage(in app: XCUIApplication, labels: [String]) {
        let picker = app.descendants(matching: .any)["appLanguagePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()

        for label in labels {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 2) {
                button.tap()
                return
            }
        }
        XCTFail("Requested language option was not available")
    }

    private func localizedMonthTitle(locale identifier: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: identifier)
        formatter.timeZone = .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: .now)
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func assertUsesMediumContentSheet(
        _ navigationBar: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThan(
            navigationBar.frame.minY,
            app.frame.height * 0.3,
            "Expected the content editor to begin in a medium-height sheet",
            file: file,
            line: line
        )
    }
}

private extension XCUIApplication {
    func launchInSimplifiedChinese() {
        launch(language: "zh-Hans", locale: "zh_CN")
    }

    func launch(language: String, locale: String) {
        launchArguments.append(contentsOf: [
            "-ui-testing-reset-language",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ])
        launch()
    }
}

private extension Date {
    var dateOnlyTestIdentifier: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}
