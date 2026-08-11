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
    let selectMode: (FutureMode) -> Void
    let shouldSuppressPresentation: () -> Bool
    @State private var showingNewTodo = false
    @State private var selectedEventDate: SelectedEventDate?

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
                .offset(x: -CGFloat(mode.pageIndex) * proxy.size.width)
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
                Button(action: presentNewItem) {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TapOnlyPrimitiveButtonStyle())
                .font(.title2.bold())
                .foregroundStyle(AppTheme.muted)
                .accessibilityLabel(mode == .list ? "添加清单" : "添加日程")
                .accessibilityIdentifier("futureAddButton")
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
        }
        .screenBackground()
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
                        selectDate: selectCalendarDate
                    )
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.top, AppTheme.navigationBarHeight, for: .scrollContent)
        .refreshable { await store.refreshContent() }
        .accessibilityIdentifier("futureCalendarScroll")
    }

    private var todoContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.todoRowSpacing) {
                ForEach(store.todos.filter { !$0.completed }) { todo in
                    HStack(spacing: 4) {
                        TodoCheckButton(todo: todo) {
                            Task { await store.toggleTodo(todo) }
                        }
                        .disabled(store.pendingTodoIDs.contains(todo.id))
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
        .contentMargins(.top, AppTheme.navigationBarHeight, for: .scrollContent)
        .refreshable { await store.refreshContent() }
        .accessibilityIdentifier("futureListScroll")
    }

    private var pageAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.32)
    }

    private func presentNewItem() {
        guard !shouldSuppressPresentation() else { return }
        haptics.play(.tap)
        if mode == .list {
            showingNewTodo = true
        } else {
            selectedEventDate = SelectedEventDate(date: Date())
        }
    }

    private func selectCalendarDate(_ date: Date) {
        guard !shouldSuppressPresentation() else { return }
        haptics.play(.tap)
        selectedEventDate = SelectedEventDate(date: date)
    }
}

private struct SelectedEventDate: Identifiable {
    let id = UUID()
    let date: Date
}

private struct TapOnlyPrimitiveButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onTapGesture { configuration.trigger() }
    }
}
