import SwiftUI

enum FutureMode: String, CaseIterable, Hashable {
    case calendar = "日历"
    case list = "清单"

    var pageIndex: Int {
        self == .calendar ? 0 : 1
    }
}

struct FutureView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    let mode: FutureMode
    let pageDragOffset: CGFloat
    let verticalScrollingDisabled: Bool
    let selectMode: (FutureMode) -> Void
    @State private var showingNewTodo = false
    @State private var selectedEventDate: SelectedEventDate?
    @State private var editingTodo: Todo?
    @State private var editingEvent: CalendarEvent?

    private let months = CalendarMonth.make(startingAt: Date(), count: 12)

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
                    items: FutureMode.allCases.map { ($0, $0.rawValue) },
                    selection: mode,
                    select: selectMode
                )

                Button(
                    mode == .list ? "添加清单" : "添加日程",
                    systemImage: "plus",
                    action: presentNewItem
                )
                .labelStyle(.iconOnly)
                .font(.title2.bold())
                .foregroundStyle(AppTheme.muted)
                .frame(width: 44, height: 44)
                .accessibilityIdentifier("futureAddButton")
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
                ForEach(months) { month in
                    CalendarMonthView(
                        month: month,
                        events: store.calendarEvents,
                        todos: store.todos,
                        editEvent: editCalendarEvent,
                        editTodo: editTodo,
                        deleteEvent: deleteCalendarEvent,
                        deleteTodo: deleteTodo
                    )
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.bottom, 80)
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
                        deletionTitle: "删除清单“\(todo.title)”？",
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
            .padding(.bottom, 80)
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

    private func presentNewItem() {
        haptics.play(.tap)
        if mode == .list {
            showingNewTodo = true
        } else {
            selectedEventDate = SelectedEventDate(date: Date())
        }
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
