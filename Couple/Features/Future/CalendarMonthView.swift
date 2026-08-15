import SwiftUI

struct CalendarMonthView: View {
    let month: CalendarMonth
    let events: [CalendarEvent]
    let todos: [Todo]
    var editEvent: @MainActor (CalendarEvent) -> Void = { _ in }
    var editTodo: @MainActor (Todo) -> Void = { _ in }
    var deleteEvent: @MainActor (CalendarEvent) async throws -> Void = { _ in }
    var deleteTodo: @MainActor (Todo) async throws -> Void = { _ in }

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
                        CalendarDayCell(
                            date: day,
                            events: scheduledEvents(on: day),
                            todos: scheduledTodos(on: day),
                            editEvent: editEvent,
                            editTodo: editTodo,
                            deleteEvent: deleteEvent,
                            deleteTodo: deleteTodo
                        )
                    } else {
                        Color.clear.frame(height: 50)
                    }
                }
            }
        }
    }

    func hasScheduledItem(on date: Date, calendar: Calendar = .current) -> Bool {
        events.contains { calendar.isDate($0.startTime, inSameDayAs: date) }
            || todos.contains { todo in
                todo.dueTime.map { calendar.isDate($0, inSameDayAs: date) } ?? false
            }
    }

    private func scheduledEvents(on date: Date) -> [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.startTime, inSameDayAs: date) }
    }

    private func scheduledTodos(on date: Date) -> [Todo] {
        todos.filter { todo in
            todo.dueTime.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
        }
    }
}
