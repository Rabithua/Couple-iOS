import SwiftUI

struct DesignTabBar<Selection: Hashable>: View {
    let items: [(Selection, String)]
    @Binding var selection: Selection

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button {
                        withAnimation(.snappy(duration: 0.3)) { selection = item.0 }
                    } label: {
                        Text(item.1)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(selection == item.0 ? Color.primary : Color.primary.opacity(0.5))
                            .blur(radius: selection == item.0 ? 0 : 3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == item.0 ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: 39)
    }
}

