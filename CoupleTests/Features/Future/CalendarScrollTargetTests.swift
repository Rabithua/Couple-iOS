import Foundation
import Testing
@testable import Couple

@MainActor
struct CalendarScrollTargetTests {
    @Test func targetsForTheSameDateRemainDistinct() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let identifiers: Set<AnyHashable> = [
            AnyHashable(CalendarScrollTarget.month(date)),
            AnyHashable(CalendarScrollTarget.today(date)),
            AnyHashable(date)
        ]

        #expect(identifiers.count == 3)
    }

    @Test func changingTodayInvalidatesTheEquatableMonthView() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 19))
        )
        let tomorrow = try #require(
            calendar.date(byAdding: .day, value: 1, to: today)
        )
        let month = try #require(
            CalendarMonth.make(startingAt: today, count: 1, calendar: calendar).first
        )
        let visibleFrame = CGRect(x: 0, y: 58, width: 390, height: 700)

        let todayView = CalendarMonthView(
            month: month,
            schedule: CalendarScheduleIndex(calendar: calendar),
            today: today,
            todayVisibleFrame: visibleFrame
        )
        let tomorrowView = CalendarMonthView(
            month: month,
            schedule: CalendarScheduleIndex(calendar: calendar),
            today: tomorrow,
            todayVisibleFrame: visibleFrame
        )

        #expect(todayView != tomorrowView)
    }
}
