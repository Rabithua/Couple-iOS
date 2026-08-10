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
    let todo: Todo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: todo.completed ? "checkmark.square" : "square")
                .font(.system(size: 24, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(todo.completed ? "重新打开\(todo.title)" : "完成\(todo.title)")
    }
}
