import SwiftUI

struct CalendarMonthHeaderPositionsPreferenceKey: PreferenceKey {
    static let defaultValue: [Date: CGFloat] = [:]

    static func reduce(
        value: inout [Date: CGFloat],
        nextValue: () -> [Date: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
