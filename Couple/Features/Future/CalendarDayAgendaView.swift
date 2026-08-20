import SwiftUI

struct CalendarDayAgendaView: View {
    @Environment(\.locale) private var locale
    @Environment(AppHaptics.self) private var haptics

    let date: Date
    let isContentVisible: Bool
    let isInteractionDisabled: Bool
    let events: [CalendarEvent]
    let todos: [Todo]
    let anniversaries: [Anniversary]
    let highlightedAnniversaryID: String?
    let createEvent: @MainActor (Date) -> Void
    let createAnniversary: @MainActor (Date) -> Void
    let editEvent: @MainActor (CalendarEvent) -> Void
    let editTodo: @MainActor (Todo) -> Void
    let editAnniversary: @MainActor (Anniversary) -> Void
    let setTodoCompletion: @MainActor (Todo, Bool) async -> Bool
    let deleteEvent: @MainActor (CalendarEvent) async throws -> Void
    let deleteTodo: @MainActor (Todo) async throws -> Void
    let deleteAnniversary: @MainActor (Anniversary) async throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(date, format: .dateTime.month(.wide).day().weekday(.wide))
                .font(.headline)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

            if events.isEmpty, todos.isEmpty, anniversaries.isEmpty {
                Text("这天还没有安排")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }

            ForEach(anniversaries) { anniversary in
                CalendarAgendaAnniversaryRow(
                    anniversary: anniversary,
                    isHighlighted: anniversary.id == highlightedAnniversaryID,
                    open: { open(anniversary) }
                )
                .editableContentActions(
                    deletionTitle: AppLocalization.string(
                        "deleteAnniversaryConfirmation",
                        defaultValue: "删除纪念日“\(anniversary.title)”？"
                    ),
                    editAction: { editAnniversary(anniversary) },
                    deleteAction: { try await deleteAnniversary(anniversary) }
                )
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
                    setCompletion: setTodoCompletion,
                    open: { editTodo(todo) }
                )
                .editableContentActions(
                    deletionTitle: AppLocalization.string("deleteTodoConfirmation",
                        defaultValue: "删除清单“\(todo.title)”？"
                    ),
                    editAction: { editTodo(todo) },
                    deleteAction: { try await deleteTodo(todo) }
                )
            }

            HStack(spacing: 8) {
                Button(action: beginCreatingEvent) {
                    Label("新建日程", systemImage: "calendar.badge.plus")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("calendarAgendaNewEventButton")

                Button(action: beginCreatingAnniversary) {
                    Label("新建纪念日", systemImage: "birthday.cake")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("calendarAgendaNewAnniversaryButton")
            }
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
        let start = event.startTime.localizedTime(locale: locale)
        guard let endTime = event.endTime else { return start }
        return "\(start)–\(endTime.localizedTime(locale: locale))"
    }

    private func todoTime(_ todo: Todo) -> String {
        todo.dueTime?.localizedTime(locale: locale) ?? AppLocalization.string("清单")
    }

    private func beginCreatingEvent() {
        haptics.play(.tap)
        createEvent(date)
    }

    private func beginCreatingAnniversary() {
        haptics.play(.tap)
        createAnniversary(date)
    }

    private func open(_ event: CalendarEvent) {
        haptics.play(.tap)
        editEvent(event)
    }

    private func open(_ anniversary: Anniversary) {
        haptics.play(.tap)
        editAnniversary(anniversary)
    }
}

private struct CalendarAgendaTodoRow: View {
    @Environment(AppHaptics.self) private var haptics

    let todo: Todo
    let time: String
    let disabled: Bool
    let setCompletion: @MainActor (Todo, Bool) async -> Bool
    let open: @MainActor () -> Void

    var body: some View {
        TodoCompletionInteraction(
            todo: todo,
            disabled: disabled,
            setCompletion: commitCompletion
        ) { completion in
            HStack(spacing: 4) {
                TodoCheckButton(
                    todo: todo,
                    isChecked: completion.isCompleted,
                    action: completion.toggle
                )
                .disabled(completion.isDisabled)

                Button(action: openTodo) {
                    LabeledContent {
                        Text(time)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    } label: {
                        TodoCompletionTitle(
                            title: todo.title,
                            isCompleted: completion.isCompleted
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppLocalization.string("编辑清单"))
                .accessibilityIdentifier("todoTitleButton-\(todo.id)")
            }
        }
    }

    private func commitCompletion(_ completed: Bool) async -> Bool {
        await setCompletion(todo, completed)
    }

    private func openTodo() {
        haptics.play(.tap)
        open()
    }
}
