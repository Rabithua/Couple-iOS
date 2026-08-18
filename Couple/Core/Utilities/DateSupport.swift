import Foundation

extension Date {
    var apiISOString: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }

    var dateOnlyString: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }

    var localizedDateTime: String {
        formatted(date: .long, time: .shortened)
    }

    var localizedMonthTitle: String {
        formatted(.dateTime.year().month(.wide))
    }

    static func fromDateOnly(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

extension Anniversary {
    func upcomingOccurrence(
        onOrAfter reference: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        let referenceDay = calendar.startOfDay(for: reference)
        if let nextOccurrence,
           let serverDate = Self.dateOnly(nextOccurrence, calendar: calendar),
           calendar.startOfDay(for: serverDate) >= referenceDay {
            return serverDate
        }
        guard let sourceDate = Self.dateOnly(date, calendar: calendar) else { return nil }
        guard annual else {
            return calendar.startOfDay(for: sourceDate) >= referenceDay ? sourceDate : nil
        }
        let source = calendar.dateComponents([.month, .day], from: sourceDate)
        guard let month = source.month, let day = source.day else { return nil }
        let referenceYear = calendar.component(.year, from: referenceDay)
        guard let thisYear = Self.annualOccurrence(
            year: referenceYear,
            month: month,
            day: day,
            calendar: calendar
        ) else { return nil }
        if thisYear >= referenceDay { return thisYear }
        return Self.annualOccurrence(
            year: referenceYear + 1,
            month: month,
            day: day,
            calendar: calendar
        )
    }

    private static func annualOccurrence(
        year: Int,
        month: Int,
        day: Int,
        calendar: Calendar
    ) -> Date? {
        var components = DateComponents(year: year, month: month, day: day)
        if month == 2, day == 29,
           calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: year, month: 2, day: 1)) ?? .distantPast)?.contains(29) == false {
            components.day = 28
        }
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
    }

    private static func dateOnly(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ))
    }
}

extension Collection where Element == Anniversary {
    func nextUpcomingAnniversary(
        onOrAfter reference: Date = .now,
        calendar: Calendar = .current
    ) -> Anniversary? {
        compactMap { anniversary in
            anniversary.upcomingOccurrence(onOrAfter: reference, calendar: calendar)
                .map { (anniversary, $0) }
        }
        .min { $0.1 < $1.1 }?
        .0
    }
}

struct CalendarMonth: Identifiable, Hashable, Sendable {
    let start: Date
    let days: [Date?]
    let weeks: [[Date?]]

    init(start: Date, days: [Date?]) {
        self.start = start
        self.days = days
        weeks = stride(from: 0, to: days.count, by: 7).map { startIndex in
            Array(days[startIndex..<min(startIndex + 7, days.count)])
        }
    }

    var id: Date { start }
    var title: String { start.localizedMonthTitle }

    static func make(startingAt date: Date, count: Int, calendar: Calendar = .current) -> [CalendarMonth] {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else {
            return []
        }
        return (0..<count).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: first),
                  let range = calendar.range(of: .day, in: .month, for: month) else { return nil }
            let weekday = calendar.component(.weekday, from: month)
            var days = Array<Date?>(repeating: nil, count: weekday - 1)
            days.append(contentsOf: range.compactMap { day in
                calendar.date(byAdding: .day, value: day - 1, to: month)
            })
            while days.count % 7 != 0 { days.append(nil) }
            return CalendarMonth(start: month, days: days)
        }
    }
}
