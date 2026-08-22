import Foundation

enum APIISO8601Instant {
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let regular = ISO8601DateFormatter()
        regular.formatOptions = [.withInternetDateTime]
        return regular.date(from: value)
    }
}

extension Date {
    var apiISOString: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }

    var dateOnlyString: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: self)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    func localizedDate(
        locale: Locale,
        style: Date.FormatStyle.DateStyle = .long
    ) -> String {
        formatted(Date.FormatStyle(date: style, time: .omitted, locale: locale))
    }

    func localizedDateTime(
        locale: Locale,
        dateStyle: Date.FormatStyle.DateStyle = .long,
        timeStyle: Date.FormatStyle.TimeStyle = .shortened
    ) -> String {
        formatted(Date.FormatStyle(date: dateStyle, time: timeStyle, locale: locale))
    }

    func localizedTime(locale: Locale) -> String {
        formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
    }

    func localizedMonthTitle(locale: Locale) -> String {
        formatted(Date.FormatStyle().year().month(.wide).locale(locale))
    }

    static func fromDateOnly(_ value: String) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let date = calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year,
              resolved.month == month,
              resolved.day == day else { return nil }
        return date
    }
}

extension Calendar {
    static func localizedGregorian(
        locale: Locale,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        return calendar
    }

    var localizedVeryShortStandaloneWeekdaySymbols: [String] {
        let symbols = veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let firstIndex = max(min(firstWeekday - 1, symbols.count - 1), 0)
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }
}

extension Anniversary {
    func occurrence(
        on date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard let sourceDate = Self.dateOnly(self.date, calendar: calendar) else { return nil }
        let targetDay = calendar.startOfDay(for: date)
        guard annual else {
            return calendar.isDate(sourceDate, inSameDayAs: targetDay) ? targetDay : nil
        }
        let sourceComponents = calendar.dateComponents([.year, .month, .day], from: sourceDate)
        let targetYear = calendar.component(.year, from: targetDay)
        guard let sourceYear = sourceComponents.year,
              let month = sourceComponents.month,
              let day = sourceComponents.day,
              targetYear >= sourceYear,
              let occurrence = Self.annualOccurrence(
                  year: targetYear,
                  month: month,
                  day: day,
                  calendar: calendar
              ),
              calendar.isDate(occurrence, inSameDayAs: targetDay)
        else { return nil }
        return occurrence
    }

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

    static func annualOccurrence(
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

    static func dateOnly(_ value: String, calendar: Calendar) -> Date? {
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
    func title(locale: Locale) -> String {
        start.localizedMonthTitle(locale: locale)
    }

    static func make(startingAt date: Date, count: Int, calendar: Calendar = .current) -> [CalendarMonth] {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else {
            return []
        }
        return (0..<count).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: first),
                  let range = calendar.range(of: .day, in: .month, for: month) else { return nil }
            let weekday = calendar.component(.weekday, from: month)
            let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7
            var days = Array<Date?>(repeating: nil, count: leadingEmptyDays)
            days.append(contentsOf: range.compactMap { day in
                calendar.date(byAdding: .day, value: day - 1, to: month)
            })
            while days.count % 7 != 0 { days.append(nil) }
            return CalendarMonth(start: month, days: days)
        }
    }
}
