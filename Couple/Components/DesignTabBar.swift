import SwiftUI

struct DesignTabBar<Selection: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let items: [(Selection, String)]
    let selection: Selection
    let select: (Selection) -> Void
    let reselect: ((Selection) -> Void)?

    init(
        items: [(Selection, String)],
        selection: Selection,
        select: @escaping (Selection) -> Void,
        reselect: ((Selection) -> Void)? = nil
    ) {
        self.items = items
        self.selection = selection
        self.select = select
        self.reselect = reselect
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        let isSelected = selection == item.0

                        Button {
                            activate(item.0, isSelected: isSelected)
                        } label: {
                            Text(item.1)
                                .font(.title.bold())
                                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                .blur(radius: isSelected || reduceTransparency ? 0 : 3)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(item.0)
                    }
                }
                .animation(.smooth(duration: 0.32), value: selection)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .onAppear {
                proxy.scrollTo(selection, anchor: .center)
            }
            .onChange(of: selection) { _, newSelection in
                if reduceMotion {
                    proxy.scrollTo(newSelection, anchor: .center)
                } else {
                    withAnimation(.smooth(duration: 0.32)) {
                        proxy.scrollTo(newSelection, anchor: .center)
                    }
                }
            }
        }
        .frame(minHeight: 44)
    }

    private func activate(_ item: Selection, isSelected: Bool) {
        if isSelected {
            reselect?(item)
        } else {
            select(item)
        }
    }
}
