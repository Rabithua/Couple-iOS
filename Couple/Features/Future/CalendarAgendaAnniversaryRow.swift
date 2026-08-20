import SwiftUI

struct CalendarAgendaAnniversaryRow: View {
    let anniversary: Anniversary
    let isHighlighted: Bool
    let open: @MainActor () -> Void

    var body: some View {
        Button(action: open) {
            LabeledContent {
                Text(anniversary.annual ? "每年" : "纪念日")
                    .foregroundStyle(.secondary)
            } label: {
                Label(anniversary.displayTitle, systemImage: "birthday.cake.fill")
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 6)
            .background(
                isHighlighted ? AppTheme.accentSelectionBackground : .clear,
                in: .rect(cornerRadius: 10)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(AppLocalization.string("编辑纪念日"))
        .accessibilityIdentifier("calendarAgendaAnniversary-\(anniversary.id)")
    }
}
