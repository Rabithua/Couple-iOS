import SwiftUI

struct CalendarDayCell: View {
    @Environment(AppHaptics.self) private var haptics
    let date: Date
    let events: [CalendarEvent]
    let todos: [Todo]
    let editEvent: @MainActor (CalendarEvent) -> Void
    let editTodo: @MainActor (Todo) -> Void
    let deleteEvent: @MainActor (CalendarEvent) async throws -> Void
    let deleteTodo: @MainActor (Todo) async throws -> Void

    @State private var pendingDeletion: PendingDeletion?
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var isDeleting = false

    var body: some View {
        let hasScheduledItem = !events.isEmpty || !todos.isEmpty

        VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.body.bold())
            Circle()
                .fill(hasScheduledItem ? Color.primary.opacity(0.45) : .clear)
                .frame(width: 3, height: 3)
        }
        .foregroundStyle(AppTheme.muted)
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(.rect)
        .contextMenu {
            ForEach(events) { event in
                Button("编辑日程：\(event.title)", systemImage: "pencil") {
                    beginEditing(event)
                }
                Button(role: .destructive) {
                    requestDeletion(.event(event))
                } label: {
                    Label("删除日程：\(event.title)", systemImage: "trash")
                }
            }

            if !events.isEmpty, !todos.isEmpty { Divider() }

            ForEach(todos) { todo in
                Button("编辑清单：\(todo.title)", systemImage: "pencil") {
                    beginEditing(todo)
                }
                Button(role: .destructive) {
                    requestDeletion(.todo(todo))
                } label: {
                    Label("删除清单：\(todo.title)", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            pendingDeletion?.confirmationTitle ?? "确认删除？",
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
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(hasScheduledItem ? "有安排" : "无安排")
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
            deleteErrorMessage = message.isEmpty ? "操作失败，请稍后重试" : message
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
        case .event(let event): "删除日程“\(event.title)”？"
        case .todo(let todo): "删除清单“\(todo.title)”？"
        }
    }
}
