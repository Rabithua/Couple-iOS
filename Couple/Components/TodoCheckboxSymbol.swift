import SwiftUI

struct TodoCheckboxSymbol: View {
    let isChecked: Bool

    var body: some View {
        Image(systemName: isChecked ? "checkmark.square" : "square")
            .font(.title2)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}
