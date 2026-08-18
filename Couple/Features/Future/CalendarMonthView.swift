import SwiftUI

struct CalendarMonthView: View {
    @Environment(\.locale) private var locale
    let month: CalendarMonth
    let schedule: CalendarScheduleIndex
    var editEvent: @MainActor (CalendarEvent) -> Void = { _ in }
    var editTodo: @MainActor (Todo) -> Void = { _ in }
    var setTodoCompletion: @MainActor (Todo, Bool) async -> Bool = { _, _ in false }
    var deleteEvent: @MainActor (CalendarEvent) async throws -> Void = { _ in }
    var deleteTodo: @MainActor (Todo) async throws -> Void = { _ in }
    var selectDate: @MainActor (Date) -> Void = { _ in }
    var createEvent: @MainActor (Date) -> Void = { _ in }
    var selectedDate: Date? = nil
    var expandedAgendaDate: Date? = nil
    var visibleAgendaDate: Date? = nil
    var selectionDisabled = false

    var body: some View {
        let weekdaySymbols = calendar.localizedVeryShortStandaloneWeekdaySymbols

        VStack(alignment: .leading, spacing: 10) {
            Text(month.title(locale: locale))
                .font(AppTheme.titleFont())
                .accessibilityIdentifier("calendarMonthTitle-\(month.start.dateOnlyString)")

            HStack(spacing: 0) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 22)
                }
            }

            VStack(spacing: 0) {
                ForEach(month.weeks.indices, id: \.self) { rowIndex in
                    let week = month.weeks[rowIndex]
                    let backgroundSelection = selectedSelection(in: week)
                    let agendaDate = agendaDate(in: week)

                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(week.indices, id: \.self) { columnIndex in
                                let day = week[columnIndex]
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
                                        .frame(
                                            maxWidth: .infinity,
                                            minHeight: AppTheme.calendarDayHeight
                                        )
                                        .accessibilityHidden(true)
                                }
                            }
                        }

                        if let agendaDate {
                            CalendarDayAgendaView(
                                date: agendaDate,
                                isContentVisible: isAgendaVisible(on: agendaDate),
                                isInteractionDisabled: selectionDisabled,
                                events: scheduledEvents(on: agendaDate),
                                todos: scheduledTodos(on: agendaDate),
                                createEvent: createEvent,
                                editEvent: editEvent,
                                editTodo: editTodo,
                                setTodoCompletion: setTodoCompletion,
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
        schedule.hasScheduledItem(on: date, calendar: calendar)
    }

    private var calendar: Calendar {
        .localizedGregorian(locale: locale)
    }

    private func scheduledEvents(on date: Date) -> [CalendarEvent] {
        schedule.events(on: date)
    }

    private func scheduledTodos(on date: Date) -> [Todo] {
        schedule.todos(on: date)
    }

    private func selectedSelection(in week: [Date?]) -> (date: Date, column: Int)? {
        guard let selectedDate,
              let column = week.firstIndex(where: { day in
                  day.map { calendar.isDate($0, inSameDayAs: selectedDate) } ?? false
              }) else { return nil }
        return (selectedDate, column)
    }

    private func agendaDate(in week: [Date?]) -> Date? {
        guard let expandedAgendaDate,
              week.contains(where: { day in
                  day.map {
                      calendar.isDate($0, inSameDayAs: expandedAgendaDate)
                  } ?? false
              }) else { return nil }
        return expandedAgendaDate
    }

    private func isSelected(_ date: Date) -> Bool {
        selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    }

    private func isAgendaVisible(on date: Date) -> Bool {
        visibleAgendaDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    }
}
