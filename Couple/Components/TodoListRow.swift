import SwiftUI

struct TodoListRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let todo: Todo
    let disabled: Bool
    let setCompletion: @MainActor (Bool) async -> Bool

    @State private var displayedCompleted: Bool
    @State private var isTransitioning = false

    init(
        todo: Todo,
        disabled: Bool,
        setCompletion: @escaping @MainActor (Bool) async -> Bool
    ) {
        self.todo = todo
        self.disabled = disabled
        self.setCompletion = setCompletion
        _displayedCompleted = State(initialValue: todo.completed)
    }

    var body: some View {
        HStack(spacing: 4) {
            TodoCheckButton(
                todo: todo,
                isChecked: displayedCompleted,
                action: toggleCompletion
            )
            .disabled(disabled || isTransitioning)

            Text(todo.title)
                .font(AppTheme.titleFont())
                .foregroundStyle(displayedCompleted ? AppTheme.muted : Color.primary)
                .overlay {
                    TodoCompletionStrike()
                        .trim(from: 0, to: displayedCompleted ? 1 : 0)
                        .stroke(
                            displayedCompleted ? AppTheme.muted : Color.primary,
                            style: StrokeStyle(
                                lineWidth: AppTheme.todoCompletionStrikeWidth,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .frame(height: AppTheme.todoCompletionStrikeHeight)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: todo.completed) { _, completed in
            guard isTransitioning == false else { return }
            withAnimation(strikeAnimation) {
                displayedCompleted = completed
            }
        }
    }

    private var strikeAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.42)
    }

    private func toggleCompletion() {
        guard isTransitioning == false else { return }
        let targetCompletion = !todo.completed
        isTransitioning = true

        withAnimation(strikeAnimation) {
            displayedCompleted = targetCompletion
        } completion: {
            Task { @MainActor in
                let committed = await setCompletion(targetCompletion)
                if committed == false {
                    withAnimation(strikeAnimation) {
                        displayedCompleted = todo.completed
                    }
                }
                isTransitioning = false
            }
        }
    }
}
