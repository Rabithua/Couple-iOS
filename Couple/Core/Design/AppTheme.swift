import SwiftUI

enum AppTheme {
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 12
    static let homeSectionSpacing: CGFloat = 12
    static let tabBarTopPadding: CGFloat = 6
    static let tabBarBottomPadding: CGFloat = 8
    static let navigationBarHeight: CGFloat = 58
    static let navigationFadeLength: CGFloat = 68
    static let homeTopFadeLength: CGFloat = 16
    static let navigationBackdropOverlap: CGFloat = 112
    static let futureContentBottomPadding: CGFloat = 80
    static let heroPhotoSpacing: CGFloat = 14
    static let heroPhotoScrollMargin: CGFloat = 8
    static let photoGalleryIdealRowHeight: CGFloat = 144
    static let photoGallerySpacing: CGFloat = 8
    static let composePromptBottomPadding: CGFloat = 38
    static let todoControlSize: CGFloat = 44
    static let todoRowSpacing: CGFloat = 0
    static let todoCompletionStrikeDelay: Duration = .milliseconds(140)
    static let todoCompletionHoldDuration: Duration = .milliseconds(1_460)
    static let todoCompletionExitDuration: Duration = .milliseconds(400)
    static let todoCompletionExitOffset: CGFloat = 18
    static let todoCompletionStrikeHeight: CGFloat = 6
    static let todoCompletionStrikeWidth: CGFloat = 2
    static let todoCompletionToggleDuration = 0.42
    static let calendarDayHeight: CGFloat = 50
    static let calendarAgendaCornerRadius: CGFloat = 16
    static let calendarAgendaTabCornerRadius: CGFloat = 12
    static let calendarAgendaJointCornerRadius: CGFloat = 8
    static let calendarAgendaBottomSpacing: CGFloat = 8
    static let calendarBackgroundRevealDuration = 0.14
    static let calendarDateSlideDuration = 0.38
    static let calendarDateSlideBounce = 0.26
    static let calendarExpansionDuration = 0.44
    static let calendarExpansionBounce = 0.2
    static let calendarRowTransferDuration = 0.38
    static let calendarRowTransferBounce = 0.22
    static let calendarAgendaFadeDuration = 0.18
    static let calendarReturnToTodayTravelDuration = 0.44
    static let calendarReturnToTodayFocusDuration = 0.18
    static let contentTop: CGFloat = 75
    static let muted = Color.secondary
    static let faint = Color.primary.opacity(0.08)

    static func titleFont() -> Font {
        .system(.title2, design: .default, weight: .semibold)
    }

    static func roundedNumberFont() -> Font {
        .system(.title2, design: .rounded, weight: .heavy)
    }
}

extension View {
    func screenBackground() -> some View {
        background(Color(.systemBackground).ignoresSafeArea())
    }

    func contentEditorSheetPresentation() -> some View {
        presentationDetents([.medium])
            .presentationDragIndicator(.visible)
    }

    func appProminentButtonStyle() -> some View {
        buttonStyle(.borderedProminent)
            .foregroundStyle(Color(.systemBackground))
    }
}
