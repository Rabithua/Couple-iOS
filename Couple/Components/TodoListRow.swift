import SwiftUI

struct TodoListRow: View {
    let todo: Todo
    let disabled: Bool
    let setCompletion: @MainActor (Bool) async -> Bool
    let open: @MainActor () -> Void

    init(
        todo: Todo,
        disabled: Bool,
        setCompletion: @escaping @MainActor (Bool) async -> Bool,
        open: @escaping @MainActor () -> Void
    ) {
        self.todo = todo
        self.disabled = disabled
        self.setCompletion = setCompletion
        self.open = open
    }

    var body: some View {
        TodoCompletionInteraction(
            todo: todo,
            disabled: disabled,
            setCompletion: setCompletion
        ) { completion in
            HStack(spacing: 4) {
                TodoCheckButton(
                    todo: todo,
                    isChecked: completion.isCompleted,
                    action: completion.toggle
                )
                .disabled(completion.isDisabled)

                Button(action: open) {
                    TodoCompletionTitle(
                        title: todo.title,
                        isCompleted: completion.isCompleted,
                        font: AppTheme.titleFont()
                    )
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppLocalization.string("编辑清单"))
                .accessibilityIdentifier("todoTitleButton-\(todo.id)")
            }
        }
    }
}
