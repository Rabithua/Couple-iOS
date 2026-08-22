import SwiftUI

private struct UnsyncedPulseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isUnsynced: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isUnsynced, !reduceMotion {
            content
                .phaseAnimator([false, true]) { view, isDimmed in
                    view.opacity(isDimmed ? 0.62 : 0.92)
                } animation: { _ in
                    .easeInOut(duration: 1.05)
                }
                .accessibilityCustomContent(
                    Text(AppLocalization.string("同步状态")),
                    Text(AppLocalization.string("尚未同步")),
                    importance: .high
                )
        } else if isUnsynced {
            content
                .opacity(0.72)
                .accessibilityCustomContent(
                    Text(AppLocalization.string("同步状态")),
                    Text(AppLocalization.string("尚未同步")),
                    importance: .high
                )
        } else {
            content
        }
    }
}

extension View {
    func unsyncedPulse(_ isUnsynced: Bool) -> some View {
        modifier(UnsyncedPulseModifier(isUnsynced: isUnsynced))
    }
}
