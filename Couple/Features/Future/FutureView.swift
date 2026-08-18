import SwiftUI

enum FutureMode: String, CaseIterable, Hashable {
    case calendar
    case list
    case settings

    var title: String {
        switch self {
        case .calendar: AppLocalization.string("日历")
        case .list: AppLocalization.string("清单")
        case .settings: AppLocalization.string("设置")
        }
    }

    var pageIndex: Int {
        switch self {
        case .calendar: 0
        case .list: 1
        case .settings: 2
        }
    }
}

struct FutureView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    let mode: FutureMode
    let pageDragOffset: CGFloat
    let verticalScrollingDisabled: Bool
    let calendarSelectionDisabled: Bool
    let selectMode: (FutureMode) -> Void
    @State private var showingNewTodo = false
    @State private var selectedEventDate: SelectedEventDate?
    @State private var editingTodo: Todo?
    @State private var editingEvent: CalendarEvent?
    @State private var selectedCalendarDate: Date?
    @State private var expandedCalendarDate: Date?
    @State private var visibleCalendarAgendaDate: Date?
    @State private var calendarTransitionID = UUID()

    var body: some View {
        DesignNavigationContainer {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    MainPagerPage(isActive: mode == .calendar, size: proxy.size) {
                        calendarContent
                    }

                    MainPagerPage(isActive: mode == .list, size: proxy.size) {
                        todoContent
                    }

                    MainPagerPage(isActive: mode == .settings, size: proxy.size) {
                        SettingsView(scrollingDisabled: verticalScrollingDisabled)
                    }
                }
                .offset(
                    x: -CGFloat(mode.pageIndex) * proxy.size.width
                        + pageDragOffset
                )
                .animation(pageAnimation, value: mode)
            }
            .clipped()
        } navigationBar: {
            ZStack(alignment: .trailing) {
                DesignTabBar(
                    items: FutureMode.allCases.map { ($0, $0.title) },
                    selection: mode,
                    select: selectMode
                )

                if mode != .settings {
                    Button(
                        mode == .list
                            ? AppLocalization.string("添加清单")
                            : AppLocalization.string("添加日程"),
                        systemImage: "plus",
                        action: presentNewItem
                    )
                    .labelStyle(.iconOnly)
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.muted)
                    .frame(width: 44, height: 44)
                    .accessibilityIdentifier("futureAddButton")
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
        }
        .screenBackground()
        .sheet(isPresented: $showingNewTodo) { NewTodoView() }
        .sheet(item: $selectedEventDate) { selection in
            NewCalendarEventView(initialDate: selection.date)
        }
        .sheet(item: $editingTodo) { todo in
            NewTodoView(editing: todo)
        }
        .sheet(item: $editingEvent) { event in
            NewCalendarEventView(editing: event)
        }
    }

    private var calendarContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(calendarMonths) { month in
                    CalendarMonthView(
                        month: month,
                        schedule: store.calendarScheduleIndex,
                        editEvent: editCalendarEvent,
                        editTodo: editTodo,
                        setTodoCompletion: setCalendarTodoCompletion,
                        deleteEvent: deleteCalendarEvent,
                        deleteTodo: deleteTodo,
                        selectDate: selectCalendarDate,
                        createEvent: presentCalendarEvent,
                        selectedDate: selectedCalendarDate,
                        expandedAgendaDate: expandedCalendarDate,
                        visibleAgendaDate: visibleCalendarAgendaDate,
                        selectionDisabled: calendarSelectionDisabled
                    )
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.bottom, AppTheme.futureContentBottomPadding)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(verticalScrollingDisabled)
        .contentMargins(.top, AppTheme.navigationBarHeight, for: .scrollContent)
        .refreshable { await store.refreshContent() }
        .accessibilityIdentifier("futureCalendarScroll")
    }

    private var todoContent: some View {
        let orderedTodos = store.todos.todosOrderedForList()

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.todoRowSpacing) {
                ForEach(orderedTodos) { todo in
                    TodoListRow(
                        todo: todo,
                        disabled: store.pendingTodoIDs.contains(todo.id)
                    ) { completed in
                        await store.setTodoCompletion(todo, completed: completed)
                    }
                    .editableContentActions(
                        deletionTitle: AppLocalization.string("deleteTodoConfirmation",
                            defaultValue: "删除清单“\(todo.title)”？"
                        ),
                        editAction: { editTodo(todo) },
                        deleteAction: { try await deleteTodo(todo) }
                    )
                }

                if orderedTodos.isEmpty {
                    ContentUnavailableView("清单空空的", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                }
            }
            .animation(pageAnimation, value: orderedTodos.map(\.id))
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.bottom, AppTheme.futureContentBottomPadding)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(verticalScrollingDisabled)
        .contentMargins(.top, AppTheme.navigationBarHeight, for: .scrollContent)
        .refreshable { await store.refreshContent() }
        .accessibilityIdentifier("futureListScroll")
    }

    private var pageAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.32)
    }

    private var calendar: Calendar {
        .localizedGregorian(locale: locale)
    }

    private var calendarMonths: [CalendarMonth] {
        CalendarMonth.make(startingAt: .now, count: 12, calendar: calendar)
    }

    private func setCalendarTodoCompletion(_ todo: Todo, completed: Bool) async -> Bool {
        await store.setTodoCompletion(todo, completed: completed)
    }

    private func presentNewItem() {
        haptics.play(.tap)
        if mode == .list {
            showingNewTodo = true
        } else {
            presentCalendarEvent(on: .now)
        }
    }

    private func selectCalendarDate(_ date: Date) {
        guard !calendarSelectionDisabled else { return }
        haptics.play(.selection)
        let transitionID = UUID()
        calendarTransitionID = transitionID

        if isSameDay(selectedCalendarDate, as: date) {
            closeCalendarDate(transitionID: transitionID)
        } else if let selectedCalendarDate {
            if canSlideCalendarSelection(from: selectedCalendarDate, to: date) {
                slideCalendarSelection(to: date, transitionID: transitionID)
            } else {
                transferCalendarSelection(to: date, transitionID: transitionID)
            }
        } else {
            openCalendarDate(date, transitionID: transitionID)
        }
    }

    private func transferCalendarSelection(to date: Date, transitionID: UUID) {
        withAnimation(
            calendarAgendaFadeAnimation,
            completionCriteria: .logicallyComplete
        ) {
            visibleCalendarAgendaDate = nil
            selectedCalendarDate = date
        } completion: {
            guard isCurrentCalendarTransition(transitionID, date: date) else { return }
            transferExpandedAgenda(to: date, transitionID: transitionID)
        }
    }

    private func transferExpandedAgenda(to date: Date, transitionID: UUID) {
        withAnimation(
            calendarRowTransferAnimation,
            completionCriteria: .logicallyComplete
        ) {
            expandedCalendarDate = date
        } completion: {
            guard isCurrentCalendarTransition(transitionID, date: date) else { return }
            revealCalendarAgenda(on: date)
        }
    }

    private func slideCalendarSelection(to date: Date, transitionID: UUID) {
        withAnimation(
            calendarAgendaFadeAnimation,
            completionCriteria: .logicallyComplete
        ) {
            visibleCalendarAgendaDate = nil
        } completion: {
            guard calendarTransitionID == transitionID else { return }
            moveCalendarSelection(to: date, transitionID: transitionID)
        }
    }

    private func moveCalendarSelection(to date: Date, transitionID: UUID) {
        withAnimation(
            calendarDateSlideAnimation,
            completionCriteria: .logicallyComplete
        ) {
            selectedCalendarDate = date
            expandedCalendarDate = date
        } completion: {
            guard isCurrentCalendarTransition(transitionID, date: date) else { return }
            revealCalendarAgenda(on: date)
        }
    }

    private func openCalendarDate(_ date: Date, transitionID: UUID) {
        withAnimation(
            calendarBackgroundRevealAnimation,
            completionCriteria: .logicallyComplete
        ) {
            selectedCalendarDate = date
        } completion: {
            guard isCurrentCalendarTransition(transitionID, date: date) else { return }
            expandCalendarBackground(for: date, transitionID: transitionID)
        }
    }

    private func expandCalendarBackground(for date: Date, transitionID: UUID) {
        withAnimation(
            calendarExpansionAnimation,
            completionCriteria: .logicallyComplete
        ) {
            expandedCalendarDate = date
        } completion: {
            guard isCurrentCalendarTransition(transitionID, date: date) else { return }
            revealCalendarAgenda(on: date)
        }
    }

    private func revealCalendarAgenda(on date: Date) {
        withAnimation(calendarAgendaFadeAnimation) {
            visibleCalendarAgendaDate = date
        }
    }

    private func closeCalendarDate(transitionID: UUID) {
        withAnimation(
            calendarAgendaFadeAnimation,
            completionCriteria: .logicallyComplete
        ) {
            visibleCalendarAgendaDate = nil
        } completion: {
            guard calendarTransitionID == transitionID else { return }
            retractCalendarBackground(transitionID: transitionID)
        }
    }

    private func retractCalendarBackground(transitionID: UUID) {
        withAnimation(
            calendarExpansionAnimation,
            completionCriteria: .logicallyComplete
        ) {
            expandedCalendarDate = nil
        } completion: {
            guard calendarTransitionID == transitionID else { return }
            hideCalendarBackground(transitionID: transitionID)
        }
    }

    private func hideCalendarBackground(transitionID: UUID) {
        guard calendarTransitionID == transitionID else { return }
        withAnimation(calendarBackgroundRevealAnimation) {
            selectedCalendarDate = nil
        }
    }

    private func isCurrentCalendarTransition(_ transitionID: UUID, date: Date) -> Bool {
        calendarTransitionID == transitionID
            && isSameDay(selectedCalendarDate, as: date)
    }

    private func isSameDay(_ lhs: Date?, as rhs: Date) -> Bool {
        lhs.map { calendar.isDate($0, inSameDayAs: rhs) } ?? false
    }

    private func canSlideCalendarSelection(from currentDate: Date, to nextDate: Date) -> Bool {
        return isSameDay(expandedCalendarDate, as: currentDate)
            && calendar.isDate(currentDate, equalTo: nextDate, toGranularity: .month)
            && calendarRow(for: currentDate, calendar: calendar)
                == calendarRow(for: nextDate, calendar: calendar)
    }

    private func calendarRow(for date: Date, calendar: Calendar) -> Int? {
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ) else { return nil }
        let leadingEmptyDays = calendar.component(.weekday, from: monthStart) - 1
        let day = calendar.component(.day, from: date)
        return (leadingEmptyDays + day - 1) / 7
    }

    private func presentCalendarEvent(on date: Date) {
        selectedEventDate = SelectedEventDate(date: eventStart(on: date))
    }

    private func eventStart(on date: Date) -> Date {
        let currentTime = calendar.dateComponents([.hour, .minute], from: .now)
        var selectedDate = calendar.dateComponents([.year, .month, .day], from: date)
        selectedDate.hour = currentTime.hour
        selectedDate.minute = currentTime.minute
        return calendar.date(from: selectedDate) ?? date
    }

    private var calendarExpansionAnimation: Animation? {
        reduceMotion
            ? nil
            : .spring(
                duration: AppTheme.calendarExpansionDuration,
                bounce: AppTheme.calendarExpansionBounce
            )
    }

    private var calendarBackgroundRevealAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: AppTheme.calendarBackgroundRevealDuration)
    }

    private var calendarDateSlideAnimation: Animation? {
        reduceMotion
            ? nil
            : .spring(
                duration: AppTheme.calendarDateSlideDuration,
                bounce: AppTheme.calendarDateSlideBounce
            )
    }

    private var calendarRowTransferAnimation: Animation? {
        reduceMotion
            ? nil
            : .spring(
                duration: AppTheme.calendarRowTransferDuration,
                bounce: AppTheme.calendarRowTransferBounce
            )
    }

    private var calendarAgendaFadeAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: AppTheme.calendarAgendaFadeDuration)
    }

    private func editTodo(_ todo: Todo) {
        editingTodo = todo
    }

    private func editCalendarEvent(_ event: CalendarEvent) {
        editingEvent = event
    }

    private func deleteTodo(_ todo: Todo) async throws {
        try await store.deleteTodo(todo)
    }

    private func deleteCalendarEvent(_ event: CalendarEvent) async throws {
        try await store.deleteCalendarEvent(event)
    }
}

private struct SelectedEventDate: Identifiable {
    let id = UUID()
    let date: Date
}
