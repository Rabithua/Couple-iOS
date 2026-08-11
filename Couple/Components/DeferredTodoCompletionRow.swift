import SwiftUI

struct DeferredTodoCompletionRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let todo: Todo
    let disabled: Bool
    let commitCompletion: @MainActor () async -> Bool

    @State private var isCompleting = false
    @State private var strikeProgress: CGFloat = 0
    @State private var dismissalProgress: CGFloat = 0
    @State private var completionTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 4) {
            TodoCheckButton(
                todo: todo,
                isChecked: isCompleting,
                action: toggleCompletion
            )
            .disabled(disabled)

            Text(todo.title)
                .font(AppTheme.titleFont())
                .lineLimit(1)
                .foregroundStyle(isCompleting ? Color.secondary : Color.primary)
                .overlay {
                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(height: 1.5)
                        .scaleEffect(x: displayedStrikeProgress, anchor: .leading)
                        .opacity(isCompleting ? 1 : 0)
                        .accessibilityHidden(true)
                }
        }
        .opacity(1 - dismissalProgress)
        .offset(x: reduceMotion ? 0 : AppTheme.todoCompletionExitOffset * dismissalProgress)
        .onDisappear {
            completionTask?.cancel()
        }
    }

    private var displayedStrikeProgress: CGFloat {
        reduceMotion && isCompleting ? 1 : strikeProgress
    }

    private func toggleCompletion() {
        if isCompleting {
            cancelCompletion()
        } else {
            beginCompletion()
        }
    }

    private func beginCompletion() {
        completionTask?.cancel()
        withAnimation(iconAnimation) {
            isCompleting = true
            dismissalProgress = 0
        }

        completionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: AppTheme.todoCompletionStrikeDelay)
                guard Task.isCancelled == false else { return }

                withAnimation(strikeAnimation) {
                    strikeProgress = 1
                }

                try await Task.sleep(for: AppTheme.todoCompletionHoldDuration)
                guard Task.isCancelled == false else { return }

                withAnimation(exitAnimation) {
                    dismissalProgress = 1
                }

                try await Task.sleep(for: AppTheme.todoCompletionExitDuration)
                guard Task.isCancelled == false else { return }

                let committed = await commitCompletion()
                if committed == false {
                    restoreCompletion()
                }
                completionTask = nil
            } catch is CancellationError {
                return
            } catch {
                restoreCompletion()
                completionTask = nil
            }
        }
    }

    private func cancelCompletion() {
        completionTask?.cancel()
        completionTask = nil
        restoreCompletion()
    }

    private func restoreCompletion() {
        withAnimation(restoreAnimation) {
            isCompleting = false
            strikeProgress = 0
            dismissalProgress = 0
        }
    }

    private var iconAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.28)
    }

    private var strikeAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.52)
    }

    private var exitAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.4)
    }

    private var restoreAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.3)
    }
}
