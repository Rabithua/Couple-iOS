import CoreGraphics

@MainActor
final class ViewFrameStore {
    private(set) var frame = CGRect.null

    func update(_ frame: CGRect) {
        guard self.frame != frame else { return }
        self.frame = frame
    }
}
