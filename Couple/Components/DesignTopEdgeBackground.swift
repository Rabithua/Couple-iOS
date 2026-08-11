import SwiftUI

struct DesignTopEdgeBackground: View {
    let length: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.navigationBackdropOverlap)
                .offset(y: -AppTheme.navigationBackdropOverlap)

            LinearGradient(
                stops: [
                    .init(color: Color(.systemBackground), location: 0),
                    .init(color: Color(.systemBackground).opacity(0.94), location: 0.22),
                    .init(color: Color(.systemBackground).opacity(0.52), location: 0.62),
                    .init(color: Color(.systemBackground).opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: length)
        }
        .frame(maxWidth: .infinity)
        .frame(height: length, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
