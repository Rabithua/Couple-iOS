import SwiftUI

struct DesignDivider: View {
    var body: some View {
        Image("SectionDivider")
            .resizable(capInsets: EdgeInsets(), resizingMode: .tile)
            .frame(height: 5)
            .foregroundStyle(AppTheme.muted)
            .accessibilityHidden(true)
    }
}

struct AssociationArrow: View {
    var height: CGFloat = 42

    var body: some View {
        Image("AssociationArrow")
            .resizable()
            .scaledToFit()
            .frame(width: 22, height: height, alignment: .top)
            .foregroundStyle(AppTheme.muted)
            .accessibilityHidden(true)
    }
}

struct TodoCheckButton: View {
    @Environment(AppHaptics.self) private var haptics
    let todo: Todo
    let isChecked: Bool
    let action: () -> Void

    init(todo: Todo, isChecked: Bool? = nil, action: @escaping () -> Void) {
        self.todo = todo
        self.isChecked = isChecked ?? todo.completed
        self.action = action
    }

    var body: some View {
        Button(action: toggleTodo) {
            TodoCheckboxSymbol(isChecked: isChecked)
                .frame(width: AppTheme.todoControlSize, height: AppTheme.todoControlSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(
            isChecked && todo.completed == false
                ? AppLocalization.string("再次轻点可取消")
                : ""
        )
    }

    private func toggleTodo() {
        haptics.playTodoCompletionChange(isCompleted: isChecked)
        action()
    }

    private var accessibilityLabel: String {
        if isChecked {
            return todo.completed
                ? AppLocalization.string("reopenTodoAccessibilityLabel",
                    defaultValue: "重新打开\(todo.title)"
                )
                : AppLocalization.string("cancelTodoCompletionAccessibilityLabel",
                    defaultValue: "取消完成\(todo.title)"
                )
        }
        return AppLocalization.string("completeTodoAccessibilityLabel",
            defaultValue: "完成\(todo.title)"
        )
    }
}
