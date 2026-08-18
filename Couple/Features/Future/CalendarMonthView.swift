import SwiftUI

struct CalendarMonthView: View {
    let month: CalendarMonth
    let events: [CalendarEvent]
    let todos: [Todo]
    var editEvent: @MainActor (CalendarEvent) -> Void = { _ in }
    var editTodo: @MainActor (Todo) -> Void = { _ in }
    var deleteEvent: @MainActor (CalendarEvent) async throws -> Void = { _ in }
    var deleteTodo: @MainActor (Todo) async throws -> Void = { _ in }
    var selectDate: @MainActor (Date) -> Void = { _ in }
    var createEvent: @MainActor (Date) -> Void = { _ in }
    var selectedDate: Date? = nil
    var expandedAgendaDate: Date? = nil
    var visibleAgendaDate: Date? = nil
    var selectionDisabled = false

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
            }

            VStack(spacing: 0) {
                ForEach(Array(weekRows.enumerated()), id: \.offset) { _, week in
                    let backgroundSelection = selectedSelection(in: week)
                    let agendaDate = agendaDate(in: week)

                    VStack(spacing: 0) {
                        LazyVGrid(columns: columns, spacing: 0) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                if let day {
                                    CalendarDayCell(
                                        date: day,
                                        events: scheduledEvents(on: day),
                                        todos: scheduledTodos(on: day),
                                        editEvent: editEvent,
                                        editTodo: editTodo,
                                        deleteEvent: deleteEvent,
                                        deleteTodo: deleteTodo,
                                        selectDate: selectDate,
                                        isSelected: isSelected(day),
                                        isSelectionDisabled: selectionDisabled
                                    )
                                } else {
                                    Color.clear
                                        .frame(height: AppTheme.calendarDayHeight)
                                        .accessibilityHidden(true)
                                }
                            }
                        }

                        if let agendaDate {
                            CalendarDayAgendaView(
                                date: agendaDate,
                                isContentVisible: isAgendaVisible(on: agendaDate),
                                events: scheduledEvents(on: agendaDate),
                                todos: scheduledTodos(on: agendaDate),
                                createEvent: createEvent,
                                editEvent: editEvent,
                                editTodo: editTodo,
                                deleteEvent: deleteEvent,
                                deleteTodo: deleteTodo
                            )
                            .id(agendaDate)
                            .padding(.bottom, AppTheme.calendarAgendaBottomSpacing)
                        }
                    }
                    .background {
                        if let backgroundSelection {
                            CalendarAgendaBackgroundShape(
                                selectedColumn: CGFloat(backgroundSelection.column)
                            )
                            .fill(AppTheme.faint)
                            .transition(.opacity)
                        }
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
        events
            .filter { Calendar.current.isDate($0.startTime, inSameDayAs: date) }
            .sorted { $0.startTime < $1.startTime }
    }

    private func scheduledTodos(on date: Date) -> [Todo] {
        todos
            .filter { todo in
                todo.dueTime.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
            }
            .sorted { ($0.dueTime ?? .distantFuture) < ($1.dueTime ?? .distantFuture) }
    }

    private var weekRows: [[Date?]] {
        stride(from: 0, to: month.days.count, by: 7).map { startIndex in
            Array(month.days[startIndex..<min(startIndex + 7, month.days.count)])
        }
    }

    private func selectedSelection(in week: [Date?]) -> (date: Date, column: Int)? {
        guard let selectedDate,
              let column = week.firstIndex(where: { day in
                  day.map { Calendar.current.isDate($0, inSameDayAs: selectedDate) } ?? false
              }) else { return nil }
        return (selectedDate, column)
    }

    private func agendaDate(in week: [Date?]) -> Date? {
        guard let expandedAgendaDate,
              week.contains(where: { day in
                  day.map {
                      Calendar.current.isDate($0, inSameDayAs: expandedAgendaDate)
                  } ?? false
              }) else { return nil }
        return expandedAgendaDate
    }

    private func isSelected(_ date: Date) -> Bool {
        selectedDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
    }

    private func isAgendaVisible(on date: Date) -> Bool {
        visibleAgendaDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
    }
}
