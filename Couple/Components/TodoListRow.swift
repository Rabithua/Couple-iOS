import SwiftUI

struct TodoListRow: View {
    let todo: Todo
    let disabled: Bool
    let setCompletion: @MainActor (Bool) async -> Bool

    init(
        todo: Todo,
        disabled: Bool,
        setCompletion: @escaping @MainActor (Bool) async -> Bool
    ) {
        self.todo = todo
        self.disabled = disabled
        self.setCompletion = setCompletion
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

                TodoCompletionTitle(
                    title: todo.title,
                    isCompleted: completion.isCompleted,
                    font: AppTheme.titleFont()
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
