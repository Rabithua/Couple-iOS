import SwiftUI

enum AppTheme {
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 18
    static let contentTop: CGFloat = 75
    static let muted = Color.primary.opacity(0.2)
    static let faint = Color.primary.opacity(0.08)

    static func titleFont(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .semibold)
    }

    static func roundedNumberFont(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
}

extension View {
    func screenBackground() -> some View {
        background(Color(.systemBackground).ignoresSafeArea())
    }
}

