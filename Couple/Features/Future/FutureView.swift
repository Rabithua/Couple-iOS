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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    let mode: FutureMode
    let pageDragOffset: CGFloat
    let verticalScrollingDisabled: Bool
    let calendarSelectionDisabled: Bool
    let notificationDestination: NotificationDestination?
    let selectMode: (FutureMode) -> Void
    @State private var showingNewTodo = false
    @State private var selectedEventDate: SelectedCreationDate?
    @State private var selectedAnniversaryDate: SelectedCreationDate?
    @State private var editingTodo: Todo?
    @State private var editingEvent: CalendarEvent?
    @State private var editingAnniversary: Anniversary?
    @State private var selectedCalendarDate: Date?
    @State private var expandedCalendarDate: Date?
    @State private var visibleCalendarAgendaDate: Date?
    @State private var calendarTransitionID = UUID()
    @State private var calendarMonthCache = CalendarMonthCache()
    @State private var hasPositionedCalendar = false
    @State private var visibleCalendarMonth: Date?
    @State private var calendarViewportSize = CGSize.zero
    @State private var isTodayVisible: Bool?
    @State private var currentCalendarDayStart = Calendar.autoupdatingCurrent
        .startOfDay(for: .now)
    @State private var scrollToTodayRequest = 0
    @State private var scrollToNotificationRequest = 0
    @State private var calendarTargetDate: Date?
    @State private var highlightedAnniversaryID: String?

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
                    select: selectNavigationMode,
                    reselect: reselectNavigationMode
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
        .sheet(item: $selectedAnniversaryDate) { selection in
            NewAnniversaryView(initialDate: selection.date)
        }
        .sheet(item: $editingTodo) { todo in
            NewTodoView(editing: todo)
        }
        .sheet(item: $editingEvent) { event in
            NewCalendarEventView(editing: event)
        }
        .sheet(item: $editingAnniversary) { anniversary in
            NewAnniversaryView(editing: anniversary)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshCurrentCalendarDay()
        }
        .task(observeCalendarDayChanges)
        .task(observeSystemTimeZoneChanges)
    }

    private var calendarContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 28,
                    pinnedViews: [.sectionHeaders]
                ) {
                    ForEach(calendarMonths) { month in
                        Section {
                            CalendarMonthView(
                                month: month,
                                schedule: store.calendarScheduleIndex,
                                today: currentCalendarDayStart,
                                todayVisibleFrame: calendarVisibleFrame,
                                editEvent: editCalendarEvent,
                                editTodo: editTodo,
                                editAnniversary: editAnniversary,
                                setTodoCompletion: setCalendarTodoCompletion,
                                deleteEvent: deleteCalendarEvent,
                                deleteTodo: deleteTodo,
                                deleteAnniversary: deleteAnniversary,
                                selectDate: selectCalendarDate,
                                createEvent: presentCalendarEvent,
                                createAnniversary: presentAnniversary,
                                selectedDate: selectedCalendarDate,
                                expandedAgendaDate: expandedCalendarDate,
                                visibleAgendaDate: visibleCalendarAgendaDate,
                                highlightedAnniversaryID: highlightedAnniversaryID,
                                selectionDisabled: calendarSelectionDisabled,
                                updateTodayVisibility: updateTodayVisibility
                            )
                            .equatable()
                        } header: {
                            Text(month.title(locale: locale))
                                .font(AppTheme.titleFont())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 10)
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: CalendarMonthHeaderPositionsPreferenceKey.self,
                                            value: [
                                                month.id: proxy.frame(
                                                    in: .named(CalendarMonthView.scrollCoordinateSpace)
                                                ).minY
                                            ]
                                        )
                                    }
                                }
                                .accessibilityIdentifier(
                                    "calendarMonthTitle-\(month.start.dateOnlyString)"
                                )
                        }
                        .id(CalendarScrollTarget.month(month.id))
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.bottom, AppTheme.futureContentBottomPadding)
            }
            .coordinateSpace(name: CalendarMonthView.scrollCoordinateSpace)
            .scrollIndicators(.hidden)
            .scrollDisabled(verticalScrollingDisabled)
            .contentMargins(.top, AppTheme.navigationBarHeight, for: .scrollContent)
            .refreshable { await store.refreshContent() }
            .accessibilityIdentifier("futureCalendarScroll")
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                calendarViewportSize = size
            }
            .onPreferenceChange(
                CalendarMonthHeaderPositionsPreferenceKey.self,
                perform: updateVisibleCalendarMonth
            )
            .task(id: currentCalendarMonthStart) {
                guard hasPositionedCalendar == false else { return }
                await Task.yield()
                scrollProxy.scrollTo(
                    CalendarScrollTarget.month(currentCalendarMonthStart),
                    anchor: .top
                )
                visibleCalendarMonth = currentCalendarMonthStart
                hasPositionedCalendar = true
            }
            .onChange(of: scrollToTodayRequest) { _, request in
                scrollToToday(using: scrollProxy, request: request)
            }
            .onChange(of: scrollToNotificationRequest) { _, request in
                scrollToNotification(using: scrollProxy, request: request)
            }
            .task(id: notificationDestination?.id) {
                await Task.yield()
                handleNotificationDestination()
            }
            .appHapticFeedback(
                .selection,
                trigger: visibleCalendarMonth,
                condition: AppHaptics.changedBetweenPresentValues
            )
            .overlay(alignment: .bottomTrailing) {
                if shouldShowTodayButton {
                    Button(
                        "今天",
                        systemImage: "calendar",
                        action: requestScrollToTodayWithFeedback
                    )
                    .font(.headline)
                    .controlSize(.large)
                    .appProminentButtonStyle()
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    .accessibilityIdentifier("calendarTodayButton")
                    .padding(.trailing, AppTheme.horizontalPadding)
                    .padding(.bottom, AppTheme.composePromptBottomPadding)
                }
            }
        }
    }

    private var todoContent: some View {
        let orderedTodos = store.todos.todosOrderedForList()

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.todoRowSpacing) {
                ForEach(orderedTodos) { todo in
                    TodoListRow(
                        todo: todo,
                        disabled: store.pendingTodoIDs.contains(todo.id),
                        setCompletion: { completed in
                            await store.setTodoCompletion(todo, completed: completed)
                        },
                        open: {
                            haptics.play(.tap)
                            editTodo(todo)
                        }
                    )
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
        calendarMonthCache.months(
            locale: locale,
            now: currentCalendarDayStart,
            historyStart: calendarHistoryStartDate,
            targetDate: calendarTargetDate
        )
    }

    private var currentCalendarMonthStart: Date {
        calendar.date(
            from: calendar.dateComponents(
                [.year, .month],
                from: currentCalendarDayStart
            )
        ) ?? currentCalendarDayStart
    }

    private var calendarVisibleFrame: CGRect {
        CGRect(
            x: 0,
            y: AppTheme.navigationBarHeight,
            width: calendarViewportSize.width,
            height: max(
                calendarViewportSize.height - AppTheme.navigationBarHeight,
                0
            )
        )
    }

    private var shouldShowTodayButton: Bool {
        guard mode == .calendar,
              hasPositionedCalendar,
              let isTodayVisible
        else { return false }
        return !isTodayVisible
    }

    private var calendarHistoryStartDate: Date? {
        let relationshipStart = store.relationship?.couple?.startedOn
            .flatMap(Date.fromDateOnly)
        return [relationshipStart, store.calendarScheduleIndex.earliestScheduledDate]
            .compactMap { $0 }
            .min()
    }

    private func updateVisibleCalendarMonth(_ headerPositions: [Date: CGFloat]) {
        guard mode == .calendar, hasPositionedCalendar else { return }
        let pinnedHeaderY = AppTheme.navigationBarHeight + 1
        guard let visibleMonth = headerPositions
            .filter({ $0.value <= pinnedHeaderY })
            .max(by: { $0.value < $1.value })?
            .key,
              visibleMonth != visibleCalendarMonth
        else { return }
        visibleCalendarMonth = visibleMonth
    }

    private func updateTodayVisibility(_ isVisible: Bool?) {
        guard isVisible != isTodayVisible else { return }
        isTodayVisible = isVisible
    }

    private func selectNavigationMode(_ selectedMode: FutureMode) {
        selectMode(selectedMode)
        if selectedMode == .calendar {
            requestScrollToToday()
        }
    }

    private func reselectNavigationMode(_ selectedMode: FutureMode) {
        guard selectedMode == .calendar else { return }
        requestScrollToTodayWithFeedback()
    }

    private func requestScrollToTodayWithFeedback() {
        haptics.play(.tap)
        requestScrollToToday()
    }

    private func requestScrollToToday() {
        scrollToTodayRequest &+= 1
    }

    private func scrollToToday(using proxy: ScrollViewProxy, request: Int) {
        proxy.scrollTo(
            CalendarScrollTarget.month(currentCalendarMonthStart),
            anchor: .top
        )

        Task { @MainActor in
            await Task.yield()
            guard scrollToTodayRequest == request else { return }
            if reduceMotion {
                proxy.scrollTo(
                    CalendarScrollTarget.today(currentCalendarDayStart),
                    anchor: .center
                )
            } else {
                withAnimation(.smooth(duration: 0.32)) {
                    proxy.scrollTo(
                        CalendarScrollTarget.today(currentCalendarDayStart),
                        anchor: .center
                    )
                }
            }
        }
    }

    private func handleNotificationDestination() {
        guard let destination = notificationDestination,
              destination.route == .futureCalendar,
              let date = destination.occurrenceDate
        else { return }
        store.ensureCalendarEvents(including: date)
        calendarTargetDate = date
        selectedCalendarDate = date
        expandedCalendarDate = date
        visibleCalendarAgendaDate = date
        highlightedAnniversaryID = destination.entityType == "anniversary"
            ? destination.entityId
            : nil
        scrollToNotificationRequest &+= 1
        let destinationID = destination.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard notificationDestination?.id == destinationID else { return }
            highlightedAnniversaryID = nil
        }
    }

    private func scrollToNotification(using proxy: ScrollViewProxy, request: Int) {
        guard let target = calendarTargetDate,
              let month = calendar.date(
                  from: calendar.dateComponents([.year, .month], from: target)
              )
        else { return }
        proxy.scrollTo(CalendarScrollTarget.month(month), anchor: .top)
        Task { @MainActor in
            await Task.yield()
            guard scrollToNotificationRequest == request else { return }
            if reduceMotion {
                proxy.scrollTo(CalendarScrollTarget.day(target), anchor: .center)
            } else {
                withAnimation(.smooth(duration: 0.32)) {
                    proxy.scrollTo(CalendarScrollTarget.day(target), anchor: .center)
                }
            }
        }
    }

    private func observeCalendarDayChanges() async {
        for await _ in NotificationCenter.default.notifications(
            named: .NSCalendarDayChanged
        ) {
            guard !Task.isCancelled else { return }
            refreshCurrentCalendarDay()
        }
    }

    private func observeSystemTimeZoneChanges() async {
        for await _ in NotificationCenter.default.notifications(
            named: .NSSystemTimeZoneDidChange
        ) {
            guard !Task.isCancelled else { return }
            store.refreshCalendarScheduleIndexForSystemTimeZoneChange()
            refreshCurrentCalendarDay()
        }
    }

    private func refreshCurrentCalendarDay() {
        let refreshedDay = calendar.startOfDay(for: .now)
        guard refreshedDay != currentCalendarDayStart else { return }
        currentCalendarDayStart = refreshedDay
        if isTodayVisible == true {
            isTodayVisible = nil
        }
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
        selectedEventDate = SelectedCreationDate(date: eventStart(on: date))
    }

    private func presentAnniversary(on date: Date) {
        selectedAnniversaryDate = SelectedCreationDate(date: date)
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

    private func editAnniversary(_ anniversary: Anniversary) {
        editingAnniversary = anniversary
    }

    private func deleteTodo(_ todo: Todo) async throws {
        try await store.deleteTodo(todo)
    }

    private func deleteCalendarEvent(_ event: CalendarEvent) async throws {
        try await store.deleteCalendarEvent(event)
    }

    private func deleteAnniversary(_ anniversary: Anniversary) async throws {
        try await store.deleteAnniversary(anniversary)
    }
}

private final class CalendarMonthCache {
    private struct Key: Equatable {
        let localeIdentifier: String
        let timeZoneIdentifier: String
        let year: Int
        let month: Int
        let historyStartYear: Int
        let historyStartMonth: Int
        let targetYear: Int
        let targetMonth: Int
    }

    private var key: Key?
    private var cachedMonths: [CalendarMonth] = []

    func months(
        locale: Locale,
        now: Date = .now,
        historyStart: Date? = nil,
        targetDate: Date? = nil
    ) -> [CalendarMonth] {
        let calendar = Calendar.localizedGregorian(locale: locale)
        guard let currentMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ), let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: currentMonth),
           let defaultLastMonth = calendar.date(byAdding: .month, value: 11, to: currentMonth)
        else { return [] }

        let requestedHistoryStart = [historyStart, targetDate, oneYearAgo]
            .compactMap { $0 }
            .min() ?? oneYearAgo
        let requestedLastMonth = max(defaultLastMonth, targetDate ?? defaultLastMonth)
        guard let firstMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: requestedHistoryStart)
        ), let lastMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: requestedLastMonth)
        ) else { return [] }

        let nextKey = Key(
            localeIdentifier: locale.identifier,
            timeZoneIdentifier: calendar.timeZone.identifier,
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now),
            historyStartYear: calendar.component(.year, from: firstMonth),
            historyStartMonth: calendar.component(.month, from: firstMonth),
            targetYear: calendar.component(.year, from: lastMonth),
            targetMonth: calendar.component(.month, from: lastMonth)
        )
        if key != nextKey {
            key = nextKey
            let monthCount = calendar.dateComponents(
                [.month],
                from: firstMonth,
                to: lastMonth
            ).month.map { $0 + 1 } ?? 24
            cachedMonths = CalendarMonth.make(
                startingAt: firstMonth,
                count: monthCount,
                calendar: calendar
            )
        }
        return cachedMonths
    }
}

private struct SelectedCreationDate: Identifiable {
    let id = UUID()
    let date: Date
}
