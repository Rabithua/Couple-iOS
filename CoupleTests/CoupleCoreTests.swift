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

    @MainActor
    func testCalendarMonthMarksTodoDueDateAsScheduled() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dueDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 15,
            hour: 21
        )))
        let otherDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: dueDate))
        let month = try XCTUnwrap(CalendarMonth.make(
            startingAt: dueDate,
            count: 1,
            calendar: calendar
        ).first)
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
        let view = CalendarMonthView(month: month, events: [], todos: [todo])

        XCTAssertTrue(view.hasScheduledItem(on: dueDate, calendar: calendar))
        XCTAssertFalse(view.hasScheduledItem(on: otherDate, calendar: calendar))
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
