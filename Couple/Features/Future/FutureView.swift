import SwiftUI

enum FutureMode: String, CaseIterable, Hashable {
    case calendar = "日历"
    case list = "清单"
}

struct FutureView: View {
    @Environment(AppStore.self) private var store
    @State private var mode: FutureMode = .calendar
    @State private var showingNewTodo = false
    @State private var selectedEventDate: SelectedEventDate?

    private let months = CalendarMonth.make(startingAt: Date(), count: 12)

    var body: some View {
        VStack(spacing: 23) {
            ZStack(alignment: .trailing) {
                DesignTabBar(
                    items: FutureMode.allCases.map { ($0, $0.rawValue) },
                    selection: $mode
                )
                Button {
                    if mode == .list {
                        showingNewTodo = true
                    } else {
                        selectedEventDate = SelectedEventDate(date: Date())
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("futureAddButton")
            }
            .padding(.horizontal, AppTheme.horizontalPadding)

            Group {
                if mode == .calendar {
                    calendarContent
                } else {
                    todoContent
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.99)))
        }
        .padding(.top, AppTheme.topPadding)
        .screenBackground()
        .sensoryFeedback(.selection, trigger: mode)
        .sheet(isPresented: $showingNewTodo) { NewTodoView() }
        .sheet(item: $selectedEventDate) { selection in
            NewCalendarEventView(initialDate: selection.date)
        }
    }

    private var calendarContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(months) { month in
                    CalendarMonthView(
                        month: month,
                        events: store.calendarEvents,
                        selectDate: { selectedEventDate = SelectedEventDate(date: $0) }
                    )
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refreshContent() }
    }

    private var todoContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(store.todos.filter { !$0.completed }) { todo in
                    HStack(spacing: 4) {
                        TodoCheckButton(todo: todo) {
                            Task { await store.toggleTodo(todo) }
                        }
                        Text(todo.title)
                            .font(AppTheme.titleFont())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if store.todos.allSatisfy(\.completed) {
                    ContentUnavailableView("清单空空的", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refreshContent() }
    }
}

private struct SelectedEventDate: Identifiable {
    let id = UUID()
    let date: Date
}
