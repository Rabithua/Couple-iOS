import SwiftUI

struct TodoCheckboxSymbol: View {
    let isChecked: Bool

    var body: some View {
        Image(systemName: isChecked ? "checkmark.square" : "square")
            .font(.title2)
            .foregroundStyle(isChecked ? AppTheme.accent : Color.primary)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}
