import SwiftUI

struct TodoCompletionPresentation {
    let isCompleted: Bool
    let isDisabled: Bool
    let toggle: @MainActor () -> Void
}

struct TodoCompletionInteraction<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let todo: Todo
    let disabled: Bool
    let setCompletion: @MainActor (Bool) async -> Bool
    let content: (TodoCompletionPresentation) -> Content

    @State private var displayedCompleted: Bool
    @State private var isTransitioning = false

    init(
        todo: Todo,
        disabled: Bool,
        setCompletion: @escaping @MainActor (Bool) async -> Bool,
        @ViewBuilder content: @escaping (TodoCompletionPresentation) -> Content
    ) {
        self.todo = todo
        self.disabled = disabled
        self.setCompletion = setCompletion
        self.content = content
        _displayedCompleted = State(initialValue: todo.completed)
    }

    var body: some View {
        content(
            TodoCompletionPresentation(
                isCompleted: displayedCompleted,
                isDisabled: disabled || isTransitioning,
                toggle: toggleCompletion
            )
        )
        .onChange(of: todo.completed) { _, completed in
            guard isTransitioning == false else { return }
            withAnimation(strikeAnimation) {
                displayedCompleted = completed
            }
        }
    }

    private var strikeAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: AppTheme.todoCompletionToggleDuration)
    }

    private func toggleCompletion() {
        guard disabled == false, isTransitioning == false else { return }
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
