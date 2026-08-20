import Foundation
import XCTest
@testable import Couple

final class CoupleCoreTests: XCTestCase {
    func testBase64URLRoundTrip() throws {
        let original = Data([0x00, 0x01, 0xFE, 0xFF, 0x40, 0x7F])
        let encoded = original.base64URLEncodedString()

        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertEqual(Data(base64URLEncoded: encoded), original)
    }

    func testAPIDecoderAcceptsFractionalAndRegularISO8601Dates() throws {
        let payload = #"""
        {
          "code": 0,
          "message": "success",
          "data": {
            "id": "couple-1",
            "startedOn": "2025-02-28",
            "timezone": "Asia/Shanghai",
            "createdAt": "2026-08-10T10:30:00.123Z",
            "updatedAt": "2026-08-10T10:30:00Z"
          }
        }
        """#.data(using: .utf8)!

        let envelope = try APIClient.decoder.decode(APIEnvelope<Couple>.self, from: payload)

        XCTAssertTrue(envelope.code.isSuccess)
        XCTAssertEqual(envelope.data.id, "couple-1")
        XCTAssertNotNil(envelope.data.createdAt)
        XCTAssertNotNil(envelope.data.updatedAt)
    }

    func testCalendarMonthUsesSundayFirstGrid() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 16)))

        let month = try XCTUnwrap(CalendarMonth.make(startingAt: start, count: 1, calendar: calendar).first)

        XCTAssertEqual(month.days.count, 35)
        XCTAssertEqual(month.days.prefix(3).compactMap { $0 }.count, 0)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(month.days[3])), 1)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(month.days[32])), 30)
    }

    func testDateOnlyParsingKeepsStrictCalendarDates() throws {
        let date = try XCTUnwrap(Date.fromDateOnly("2026-08-19"))

        XCTAssertEqual(date.dateOnlyString, "2026-08-19")
        XCTAssertNil(Date.fromDateOnly("2026-02-30"))
        XCTAssertNil(Date.fromDateOnly("2026/08/19"))
    }

    func testCalendarScheduleIndexMarksTodoDueDateAsScheduled() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dueDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 15,
            hour: 21
        )))
        let otherDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: dueDate))
        let todo = Todo(
            id: "todo-with-due-date",
            coupleId: "couple",
            ownerId: "owner",
            title: "有日期的清单",
            note: nil,
            dueTime: dueDate,
            visibility: .shared,
            completed: false,
            completedAt: nil,
            completedBy: nil,
            reminderOffset: 60,
            createdAt: dueDate,
            updatedAt: dueDate
        )
        let schedule = CalendarScheduleIndex(
            events: [],
            todos: [todo],
            calendar: calendar
        )

        XCTAssertTrue(schedule.hasScheduledItem(on: dueDate, calendar: calendar))
        XCTAssertEqual(schedule.todos(on: dueDate, calendar: calendar).map(\.id), [todo.id])
        XCTAssertFalse(schedule.hasScheduledItem(on: otherDate, calendar: calendar))
    }

    func testCalendarScheduleIndexTracksEarliestScheduledDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let eventDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2025,
            month: 3,
            day: 8,
            hour: 18
        )))
        let todoDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2025,
            month: 2,
            day: 14,
            hour: 20
        )))
        let event = CalendarEvent(
            id: "event",
            coupleId: "couple",
            ownerId: "owner",
            title: "Event",
            description: nil,
            allDay: false,
            startTime: eventDate,
            endTime: nil,
            timezone: "UTC",
            yearly: false,
            visibility: .shared,
            reminderOffset: nil,
            createdAt: eventDate,
            updatedAt: eventDate,
            occurrenceId: nil,
            recurrenceSourceId: nil
        )
        let todo = Todo(
            id: "todo",
            coupleId: "couple",
            ownerId: "owner",
            title: "Todo",
            note: nil,
            dueTime: todoDate,
            visibility: .shared,
            completed: false,
            completedAt: nil,
            completedBy: nil,
            reminderOffset: nil,
            createdAt: todoDate,
            updatedAt: todoDate
        )

        let schedule = CalendarScheduleIndex(
            events: [event],
            todos: [todo],
            calendar: calendar
        )

        XCTAssertEqual(schedule.earliestScheduledDate, calendar.startOfDay(for: todoDate))
    }

    func testCalendarScheduleIndexChangesWhenSystemTimeZoneChanges() throws {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var shanghaiCalendar = Calendar(identifier: .gregorian)
        shanghaiCalendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 60 * 60))
        let eventTime = try XCTUnwrap(utcCalendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 19,
            hour: 16,
            minute: 30
        )))
        let event = CalendarEvent(
            id: "timezone-event",
            coupleId: "couple",
            ownerId: "owner",
            title: "Timezone boundary",
            description: nil,
            allDay: false,
            startTime: eventTime,
            endTime: nil,
            timezone: "UTC",
            yearly: false,
            visibility: .shared,
            reminderOffset: nil,
            createdAt: eventTime,
            updatedAt: eventTime,
            occurrenceId: nil,
            recurrenceSourceId: nil
        )

        let utcIndex = CalendarScheduleIndex(events: [event], calendar: utcCalendar)
        let shanghaiIndex = CalendarScheduleIndex(events: [event], calendar: shanghaiCalendar)
        let utcDay = try XCTUnwrap(utcCalendar.date(
            from: DateComponents(year: 2026, month: 8, day: 19, hour: 12)
        ))
        let shanghaiDay = try XCTUnwrap(shanghaiCalendar.date(
            from: DateComponents(year: 2026, month: 8, day: 20, hour: 12)
        ))

        XCTAssertNotEqual(utcIndex, shanghaiIndex)
        XCTAssertEqual(utcIndex.events(on: utcDay, calendar: utcCalendar).map(\.id), [event.id])
        XCTAssertTrue(utcIndex.events(on: shanghaiDay, calendar: utcCalendar).isEmpty)
        XCTAssertEqual(
            shanghaiIndex.events(on: shanghaiDay, calendar: shanghaiCalendar).map(\.id),
            [event.id]
        )
        XCTAssertTrue(shanghaiIndex.events(on: utcDay, calendar: shanghaiCalendar).isEmpty)
    }

    func testCalendarScheduleIndexIncludesAnnualLeapDayAnniversaryOnFebruary28() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anniversary = Anniversary(
            id: "leap-anniversary",
            coupleId: "couple",
            ownerId: "owner",
            title: "闰日纪念日",
            date: "2024-02-29",
            annual: true,
            visibility: .shared,
            reminderOffset: 1_440,
            reminderInstant: nil,
            createdAt: .now,
            updatedAt: .now,
            nextOccurrence: nil
        )
        let nonLeapOccurrence = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2027, month: 2, day: 28)
        ))
        let wrongDay = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2027, month: 3, day: 1)
        ))
        let schedule = CalendarScheduleIndex(
            anniversaries: [anniversary],
            calendar: calendar
        )

        XCTAssertEqual(schedule.anniversaries(on: nonLeapOccurrence, calendar: calendar), [anniversary])
        XCTAssertTrue(schedule.hasScheduledItem(on: nonLeapOccurrence, calendar: calendar))
        XCTAssertTrue(schedule.anniversaries(on: wrongDay, calendar: calendar).isEmpty)
    }

    func testCalendarScheduleIndexKeepsOneTimeAnniversaryOnSavedDateOnly() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anniversary = Anniversary(
            id: "one-time-anniversary",
            coupleId: "couple",
            ownerId: "owner",
            title: "一次纪念日",
            date: "2026-08-20",
            annual: false,
            visibility: .shared,
            reminderOffset: nil,
            reminderInstant: nil,
            createdAt: .now,
            updatedAt: .now,
            nextOccurrence: nil
        )
        let savedDate = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 20)
        ))
        let nextYear = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2027, month: 8, day: 20)
        ))
        let schedule = CalendarScheduleIndex(
            anniversaries: [anniversary],
            calendar: calendar
        )

        XCTAssertEqual(schedule.anniversaries(on: savedDate, calendar: calendar), [anniversary])
        XCTAssertTrue(schedule.anniversaries(on: nextYear, calendar: calendar).isEmpty)
    }

    func testNotificationDestinationParsesCalendarOccurrence() throws {
        let destination = try XCTUnwrap(NotificationDestination(userInfo: [
            "eventType": "anniversary_reminder",
            "route": "futureCalendar",
            "entityType": "anniversary",
            "entityId": "anniversary-id",
            "occurrenceDate": "2027-02-28",
        ]))

        XCTAssertEqual(destination.route, .futureCalendar)
        XCTAssertEqual(destination.entityType, "anniversary")
        XCTAssertEqual(destination.entityId, "anniversary-id")
        XCTAssertEqual(destination.occurrenceDate?.dateOnlyString, "2027-02-28")
    }

    @MainActor
    func testDemoStoreLoadsCompleteHomeData() async {
        let store = AppStore(
            environment: ["COUPLE_DEMO_MODE": "1"],
            arguments: ["CoupleTests"]
        )

        await store.start()

        XCTAssertEqual(store.phase, .main)
        XCTAssertEqual(store.home?.daysTogether, 528)
        XCTAssertEqual(store.relationship?.members.count, 2)
        XCTAssertFalse(store.notes.isEmpty)
        XCTAssertFalse(store.todos.isEmpty)
        XCTAssertFalse(store.anniversaries.isEmpty)
    }
}
