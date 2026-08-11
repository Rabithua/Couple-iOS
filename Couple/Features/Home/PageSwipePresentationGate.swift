import Foundation

@MainActor
final class PageSwipePresentationGate {
    private var isTrackingHorizontalDrag = false

    var suppressesPresentation: Bool {
        isTrackingHorizontalDrag
    }

    func update(horizontal: CGFloat, vertical: CGFloat) {
        guard abs(horizontal) >= 12 else { return }
        guard abs(horizontal) > abs(vertical) * 1.2 else { return }
        isTrackingHorizontalDrag = true
    }

    func finish() {
        isTrackingHorizontalDrag = false
    }
}
