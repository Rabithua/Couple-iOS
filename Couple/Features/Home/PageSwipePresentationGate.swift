import Foundation

@MainActor
final class PageSwipePresentationGate {
    private var isTrackingHorizontalDrag = false
    private var suppressionEnd = Date.distantPast

    var suppressesPresentation: Bool {
        isTrackingHorizontalDrag || Date.now < suppressionEnd
    }

    func update(horizontal: CGFloat, vertical: CGFloat) {
        guard abs(horizontal) >= 12 else { return }
        guard abs(horizontal) > abs(vertical) * 1.2 else { return }
        isTrackingHorizontalDrag = true
    }

    func finish() {
        if isTrackingHorizontalDrag {
            suppressionEnd = Date.now.addingTimeInterval(0.3)
        }
        isTrackingHorizontalDrag = false
    }
}
