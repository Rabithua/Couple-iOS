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

    var chineseDateTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: self)
    }

    var chineseMonthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: self)
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

struct CalendarMonth: Identifiable, Hashable, Sendable {
    let start: Date
    let days: [Date?]

    var id: Date { start }
    var title: String { start.chineseMonthTitle }

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
