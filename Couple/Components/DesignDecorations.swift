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
    let action: () -> Void

    var body: some View {
        Button(action: toggleTodo) {
            Image(systemName: todo.completed ? "checkmark.square" : "square")
                .font(.title2)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .frame(width: AppTheme.todoControlSize, height: AppTheme.todoControlSize)
        .accessibilityLabel(todo.completed ? "重新打开\(todo.title)" : "完成\(todo.title)")
    }

    private func toggleTodo() {
        haptics.play(todo.completed ? .selection : .success)
        action()
    }
}
