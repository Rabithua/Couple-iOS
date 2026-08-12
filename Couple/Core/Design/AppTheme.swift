import SwiftUI

enum AppTheme {
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 18
    static let tabBarTopPadding: CGFloat = 6
    static let tabBarBottomPadding: CGFloat = 8
    static let navigationBarHeight: CGFloat = 58
    static let navigationFadeLength: CGFloat = 68
    static let homeTopFadeLength: CGFloat = 44
    static let navigationBackdropOverlap: CGFloat = 112
    static let heroPhotoSpacing: CGFloat = 14
    static let heroPhotoScrollMargin: CGFloat = 8
    static let composePromptBottomPadding: CGFloat = 38
    static let todoControlSize: CGFloat = 38
    static let todoRowSpacing: CGFloat = 0
    static let todoCompletionStrikeDelay: Duration = .milliseconds(140)
    static let todoCompletionHoldDuration: Duration = .milliseconds(1_460)
    static let todoCompletionExitDuration: Duration = .milliseconds(400)
    static let todoCompletionExitOffset: CGFloat = 18
    static let todoCompletionStrikeHeight: CGFloat = 6
    static let todoCompletionStrikeWidth: CGFloat = 2
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
}
