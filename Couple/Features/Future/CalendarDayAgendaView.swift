import SwiftUI

struct CalendarDayAgendaView: View {
    @Environment(AppHaptics.self) private var haptics

    let date: Date
    let isContentVisible: Bool
    let isInteractionDisabled: Bool
    let events: [CalendarEvent]
    let todos: [Todo]
    let createEvent: @MainActor (Date) -> Void
    let editEvent: @MainActor (CalendarEvent) -> Void
    let editTodo: @MainActor (Todo) -> Void
    let setTodoCompletion: @MainActor (Todo, Bool) async -> Bool
    let deleteEvent: @MainActor (CalendarEvent) async throws -> Void
    let deleteTodo: @MainActor (Todo) async throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(date, format: .dateTime.month(.wide).day().weekday(.wide))
                .font(.headline)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

            if events.isEmpty, todos.isEmpty {
                Label("这天还没有安排", systemImage: "calendar.badge.plus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }

            ForEach(events) { event in
                Button(action: { open(event) }) {
                    LabeledContent {
                        Text(eventTime(event))
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(event.title, systemImage: "calendar")
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .editableContentActions(
                    deletionTitle: AppLocalization.string("deleteEventConfirmation",
                        defaultValue: "删除日程“\(event.title)”？"
                    ),
                    editAction: { editEvent(event) },
                    deleteAction: { try await deleteEvent(event) }
                )
                .accessibilityIdentifier("calendarAgendaEvent-\(event.id)")
            }

            ForEach(todos) { todo in
                CalendarAgendaTodoRow(
                    todo: todo,
                    time: todoTime(todo),
                    disabled: isInteractionDisabled,
                    setCompletion: setTodoCompletion
                )
                .editableContentActions(
                    deletionTitle: AppLocalization.string("deleteTodoConfirmation",
                        defaultValue: "删除清单“\(todo.title)”？"
                    ),
                    editAction: { editTodo(todo) },
                    deleteAction: { try await deleteTodo(todo) }
                )
                .accessibilityIdentifier("calendarAgendaTodo-\(todo.id)")
            }

            Button(action: beginCreatingEvent) {
                Label("新建日程", systemImage: "plus")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.muted)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("calendarAgendaNewEventButton")
        }
        .padding(10)
        .opacity(isContentVisible ? 1 : 0)
        .allowsHitTesting(isContentVisible)
        .transition(.identity)
        .accessibilityElement(children: .contain)
        .accessibilityHidden(!isContentVisible)
        .accessibilityIdentifier("calendarAgenda-\(date.dateOnlyString)")
    }

    private func eventTime(_ event: CalendarEvent) -> String {
        if event.allDay { return AppLocalization.string("全天") }
        let start = event.startTime.formatted(date: .omitted, time: .shortened)
        guard let endTime = event.endTime else { return start }
        return "\(start)–\(endTime.formatted(date: .omitted, time: .shortened))"
    }

    private func todoTime(_ todo: Todo) -> String {
        todo.dueTime?.formatted(date: .omitted, time: .shortened) ?? AppLocalization.string("清单")
    }

    private func beginCreatingEvent() {
        haptics.play(.tap)
        createEvent(date)
    }

    private func open(_ event: CalendarEvent) {
        haptics.play(.tap)
        editEvent(event)
    }
}

private struct CalendarAgendaTodoRow: View {
    @Environment(AppHaptics.self) private var haptics

    let todo: Todo
    let time: String
    let disabled: Bool
    let setCompletion: @MainActor (Todo, Bool) async -> Bool

    var body: some View {
        TodoCompletionInteraction(
            todo: todo,
            disabled: disabled,
            setCompletion: commitCompletion
        ) { completion in
            Button {
                haptics.playTodoCompletionChange(
                    isCompleted: completion.isCompleted
                )
                completion.toggle()
            } label: {
                LabeledContent {
                    Text(time)
                        .foregroundStyle(.secondary)
                } label: {
                    Label {
                        TodoCompletionTitle(
                            title: todo.title,
                            isCompleted: completion.isCompleted,
                            lineLimit: 1
                        )
                    } icon: {
                        TodoCheckboxSymbol(isChecked: completion.isCompleted)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(completion.isDisabled)
            .accessibilityLabel(accessibilityLabel(completion.isCompleted))
            .accessibilityHint(AppLocalization.string("长按可以编辑或删除"))
        }
    }

    private func commitCompletion(_ completed: Bool) async -> Bool {
        await setCompletion(todo, completed)
    }

    private func accessibilityLabel(_ isCompleted: Bool) -> String {
        isCompleted
            ? AppLocalization.string("reopenTodoAccessibilityLabel",
                defaultValue: "重新打开\(todo.title)"
            )
            : AppLocalization.string("completeTodoAccessibilityLabel",
                defaultValue: "完成\(todo.title)"
            )
    }
}
