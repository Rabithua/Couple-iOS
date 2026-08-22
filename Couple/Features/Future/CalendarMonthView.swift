import SwiftUI

struct CalendarMonthView: View, @MainActor Equatable {
    static let scrollCoordinateSpace = "futureCalendarScrollSpace"

    @Environment(\.locale) private var locale
    let month: CalendarMonth
    let schedule: CalendarScheduleIndex
    var unsyncedContent = UnsyncedContentIDs.empty
    let today: Date
    let todayVisibleFrame: CGRect
    var editEvent: @MainActor (CalendarEvent) -> Void = { _ in }
    var editTodo: @MainActor (Todo) -> Void = { _ in }
    var editAnniversary: @MainActor (Anniversary) -> Void = { _ in }
    var setTodoCompletion: @MainActor (Todo, Bool) async -> Bool = { _, _ in false }
    var deleteEvent: @MainActor (CalendarEvent) async throws -> Void = { _ in }
    var deleteTodo: @MainActor (Todo) async throws -> Void = { _ in }
    var deleteAnniversary: @MainActor (Anniversary) async throws -> Void = { _ in }
    var selectDate: @MainActor (Date) -> Void = { _ in }
    var createEvent: @MainActor (Date) -> Void = { _ in }
    var createAnniversary: @MainActor (Date) -> Void = { _ in }
    var selectedDate: Date? = nil
    var expandedAgendaDate: Date? = nil
    var visibleAgendaDate: Date? = nil
    var highlightedAnniversaryID: String? = nil
    var selectionDisabled = false
    var updateTodayVisibility: @MainActor (Bool?) -> Void = { _ in }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.month == rhs.month
            && lhs.schedule == rhs.schedule
            && lhs.unsyncedContent == rhs.unsyncedContent
            && lhs.today == rhs.today
            && lhs.todayVisibleFrame == rhs.todayVisibleFrame
            && lhs.selectedDate == rhs.selectedDate
            && lhs.expandedAgendaDate == rhs.expandedAgendaDate
            && lhs.visibleAgendaDate == rhs.visibleAgendaDate
            && lhs.highlightedAnniversaryID == rhs.highlightedAnniversaryID
            && lhs.selectionDisabled == rhs.selectionDisabled
    }

    var body: some View {
        let weekdaySymbols = calendar.localizedVeryShortStandaloneWeekdaySymbols

        VStack(alignment: .leading, spacing: 10) {
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
                                    let dayCell = CalendarDayCell(
                                        date: day,
                                        events: scheduledEvents(on: day),
                                        todos: scheduledTodos(on: day),
                                        anniversaries: scheduledAnniversaries(on: day),
                                        unsyncedContent: unsyncedContent,
                                        editEvent: editEvent,
                                        editTodo: editTodo,
                                        editAnniversary: editAnniversary,
                                        deleteEvent: deleteEvent,
                                        deleteTodo: deleteTodo,
                                        deleteAnniversary: deleteAnniversary,
                                        selectDate: selectDate,
                                        isSelected: isSelected(day),
                                        isSelectionDisabled: selectionDisabled
                                    )

                                    if calendar.isDate(day, inSameDayAs: today) {
                                        dayCell
                                            .id(CalendarScrollTarget.today(day))
                                            .onGeometryChange(for: Bool?.self) { proxy in
                                                guard !todayVisibleFrame.isEmpty else { return nil }
                                                return proxy.frame(
                                                    in: .named(Self.scrollCoordinateSpace)
                                                ).intersects(todayVisibleFrame)
                                            } action: { isVisible in
                                                updateTodayVisibility(isVisible)
                                            }
                                    } else {
                                        dayCell
                                    }
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
                                anniversaries: scheduledAnniversaries(on: agendaDate),
                                unsyncedContent: unsyncedContent,
                                highlightedAnniversaryID: highlightedAnniversaryID,
                                createEvent: createEvent,
                                createAnniversary: createAnniversary,
                                editEvent: editEvent,
                                editTodo: editTodo,
                                editAnniversary: editAnniversary,
                                setTodoCompletion: setTodoCompletion,
                                deleteEvent: deleteEvent,
                                deleteTodo: deleteTodo,
                                deleteAnniversary: deleteAnniversary
                            )
                            .id(CalendarScrollTarget.day(agendaDate))
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

    private func scheduledAnniversaries(on date: Date) -> [Anniversary] {
        schedule.anniversaries(on: date)
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
