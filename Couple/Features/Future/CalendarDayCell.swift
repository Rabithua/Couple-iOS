import SwiftUI

struct CalendarDayCell: View {
    @Environment(\.locale) private var locale
    @Environment(AppHaptics.self) private var haptics
    let date: Date
    let events: [CalendarEvent]
    let todos: [Todo]
    let editEvent: @MainActor (CalendarEvent) -> Void
    let editTodo: @MainActor (Todo) -> Void
    let deleteEvent: @MainActor (CalendarEvent) async throws -> Void
    let deleteTodo: @MainActor (Todo) async throws -> Void
    let selectDate: @MainActor (Date) -> Void
    let isSelected: Bool
    let isSelectionDisabled: Bool

    @State private var pendingDeletion: PendingDeletion?
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var isDeleting = false

    var body: some View {
        let calendar = Calendar.localizedGregorian(locale: locale)
        let hasScheduledItem = !events.isEmpty || !todos.isEmpty
        let isToday = calendar.isDateInToday(date)
        let isPast = date < calendar.startOfDay(for: .now)

        Group {
            if hasScheduledItem {
                dayButton(
                    calendar: calendar,
                    isToday: isToday,
                    isPast: isPast,
                    hasScheduledItem: true
                )
                    .contextMenu { scheduledItemMenu }
                    .confirmationDialog(
                        pendingDeletion?.confirmationTitle ?? AppLocalization.string("确认删除？"),
                        isPresented: $isShowingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("删除", role: .destructive, action: beginDeleting)
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("删除后会从双方设备同步移除。")
                    }
                    .alert("删除失败", isPresented: $isShowingDeleteError) {
                    } message: {
                        Text(deleteErrorMessage)
                    }
            } else {
                dayButton(
                    calendar: calendar,
                    isToday: isToday,
                    isPast: isPast,
                    hasScheduledItem: false
                )
            }
        }
        .accessibilityLabel(date.localizedDate(locale: locale, style: .complete))
        .accessibilityValue(accessibilityValue(isToday: isToday))
        .accessibilityHint(accessibilityHint(hasScheduledItem: hasScheduledItem))
        .accessibilityIdentifier("calendarDay-\(date.dateOnlyString)")
    }

    private func dayButton(
        calendar: Calendar,
        isToday: Bool,
        isPast: Bool,
        hasScheduledItem: Bool
    ) -> some View {
        Button(action: selectDay) {
            VStack(spacing: 2) {
                Text(calendar.component(.day, from: date), format: .number)
                    .font(.body.bold())
                    .foregroundStyle(
                        isToday
                            ? Color(.systemBackground)
                            : AppTheme.muted.opacity(isPast ? 0.55 : 1)
                    )
                    .frame(width: 32, height: 32)
                    .background(
                        isToday ? Color.primary : .clear,
                        in: .rect(cornerRadius: AppTheme.calendarTodayCornerRadius)
                    )

                Circle()
                    .fill(hasScheduledItem ? Color.primary.opacity(0.45) : .clear)
                    .frame(width: 3, height: 3)
                    .opacity(isPast ? 0.6 : 1)
            }
            .frame(maxWidth: .infinity, minHeight: AppTheme.calendarDayHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isSelectionDisabled)
    }

    @ViewBuilder
    private var scheduledItemMenu: some View {
        ForEach(events) { event in
            Button(
                AppLocalization.string("editEventAccessibilityLabel",
                    defaultValue: "编辑日程：\(event.title)"
                ),
                systemImage: "pencil"
            ) {
                beginEditing(event)
            }
            Button(role: .destructive) {
                requestDeletion(.event(event))
            } label: {
                Label(
                    AppLocalization.string("deleteEventAccessibilityLabel",
                        defaultValue: "删除日程：\(event.title)"
                    ),
                    systemImage: "trash"
                )
            }
        }

        if !events.isEmpty, !todos.isEmpty { Divider() }

        ForEach(todos) { todo in
            Button(
                AppLocalization.string("editTodoAccessibilityLabel",
                    defaultValue: "编辑清单：\(todo.title)"
                ),
                systemImage: "pencil"
            ) {
                beginEditing(todo)
            }
            Button(role: .destructive) {
                requestDeletion(.todo(todo))
            } label: {
                Label(
                    AppLocalization.string("deleteTodoAccessibilityLabel",
                        defaultValue: "删除清单：\(todo.title)"
                    ),
                    systemImage: "trash"
                )
            }
        }
    }

    private func selectDay() {
        guard !isSelectionDisabled else { return }
        selectDate(date)
    }

    private func accessibilityValue(isToday: Bool) -> String {
        var values: [String] = []
        if isToday { values.append(AppLocalization.string("今天")) }
        if isSelected { values.append(AppLocalization.string("已展开")) }
        if !events.isEmpty {
            values.append(AppLocalization.string("calendarEventCount",
                defaultValue: "\(events.count) 个日程"
            ))
        }
        if !todos.isEmpty {
            values.append(AppLocalization.string("todoCount",
                defaultValue: "\(todos.count) 个清单"
            ))
        }
        return values.isEmpty
            ? AppLocalization.string("无安排")
            : values.formatted(.list(type: .and, width: .short).locale(locale))
    }

    private func accessibilityHint(hasScheduledItem: Bool) -> String {
        if isSelected { return AppLocalization.string("轻点收起当天安排") }
        return hasScheduledItem
            ? AppLocalization.string("轻点展开当天安排，长按管理")
            : AppLocalization.string("轻点展开并新建日程")
    }

    private func beginEditing(_ event: CalendarEvent) {
        haptics.play(.tap)
        editEvent(event)
    }

    private func beginEditing(_ todo: Todo) {
        haptics.play(.tap)
        editTodo(todo)
    }

    private func requestDeletion(_ target: PendingDeletion) {
        guard !isDeleting else { return }
        haptics.play(.warning)
        pendingDeletion = target
        isShowingDeleteConfirmation = true
    }

    private func beginDeleting() {
        guard !isDeleting, pendingDeletion != nil else { return }
        isDeleting = true
        Task { await deletePendingContent() }
    }

    private func deletePendingContent() async {
        defer {
            isDeleting = false
            pendingDeletion = nil
        }
        do {
            switch pendingDeletion {
            case .event(let event): try await deleteEvent(event)
            case .todo(let todo): try await deleteTodo(todo)
            case nil: return
            }
            haptics.play(.success)
        } catch {
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            deleteErrorMessage = message.isEmpty
                ? AppLocalization.string("操作失败，请稍后重试")
                : message
            isShowingDeleteError = true
            haptics.play(.error)
        }
    }
}

private enum PendingDeletion {
    case event(CalendarEvent)
    case todo(Todo)

    var confirmationTitle: String {
        switch self {
        case .event(let event): AppLocalization.string("deleteEventConfirmation",
            defaultValue: "删除日程“\(event.title)”？"
        )
        case .todo(let todo): AppLocalization.string("deleteTodoConfirmation",
            defaultValue: "删除清单“\(todo.title)”？"
        )
        }
    }
}
