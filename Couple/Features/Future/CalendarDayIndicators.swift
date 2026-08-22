import SwiftUI

struct CalendarDayIndicators: View {
    let hasEvents: Bool
    let hasTodos: Bool
    let hasAnniversaries: Bool
    let hasUnsyncedEvents: Bool
    let hasUnsyncedTodos: Bool
    let hasUnsyncedAnniversaries: Bool
    let isPast: Bool

    var body: some View {
        HStack(spacing: 2) {
            if hasAnniversaries {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 4, height: 4)
                    .unsyncedPulse(hasUnsyncedAnniversaries)
            }

            if hasEvents {
                Circle()
                    .fill(.secondary)
                    .frame(width: 4, height: 4)
                    .unsyncedPulse(hasUnsyncedEvents)
            }

            if hasTodos {
                Circle()
                    .stroke(.secondary, lineWidth: 1)
                    .frame(width: 4, height: 4)
                    .unsyncedPulse(hasUnsyncedTodos)
            }
        }
        .frame(height: 4)
        .opacity(isPast ? 0.6 : 1)
        .accessibilityHidden(true)
    }
}
