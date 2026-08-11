import SwiftUI

struct CalendarMonthView: View {
    let month: CalendarMonth
    let events: [CalendarEvent]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(month.title)
                .font(AppTheme.titleFont())

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.muted)
                        .frame(height: 22)
                }

                ForEach(Array(month.days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        VStack(spacing: 2) {
                            Text("\(Calendar.current.component(.day, from: day))")
                                .font(.body.bold())
                            Circle()
                                .fill(hasEvent(on: day) ? Color.primary.opacity(0.45) : .clear)
                                .frame(width: 3, height: 3)
                        }
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    } else {
                        Color.clear.frame(height: 50)
                    }
                }
            }
        }
    }

    private func hasEvent(on date: Date) -> Bool {
        events.contains { Calendar.current.isDate($0.startTime, inSameDayAs: date) }
    }
}
