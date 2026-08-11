import SwiftUI

struct MainPagerPage<Content: View>: View {
    let isActive: Bool
    let size: CGSize
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
    }
}
