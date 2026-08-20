import SwiftUI

struct MainPagerPage<Content: View>: View {
    let isActive: Bool
    let isInteractionEnabled: Bool
    let usesDisabledState: Bool
    let size: CGSize
    @ViewBuilder let content: Content

    init(
        isActive: Bool,
        isInteractionEnabled: Bool = true,
        usesDisabledState: Bool = true,
        size: CGSize,
        @ViewBuilder content: () -> Content
    ) {
        self.isActive = isActive
        self.isInteractionEnabled = isInteractionEnabled
        self.usesDisabledState = usesDisabledState
        self.size = size
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .disabled(usesDisabledState && (!isActive || !isInteractionEnabled))
            .allowsHitTesting(isActive && isInteractionEnabled)
            .accessibilityHidden(!isActive)
    }
}
