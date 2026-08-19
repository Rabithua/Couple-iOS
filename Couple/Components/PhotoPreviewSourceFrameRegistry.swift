import CoreGraphics

@MainActor
final class PhotoPreviewSourceFrameRegistry {
    private var frames: [PhotoPreviewTransitionID: CGRect] = [:]

    func update(_ transitionID: PhotoPreviewTransitionID, frame: CGRect) {
        guard Self.isUsable(frame), frames[transitionID] != frame else { return }
        frames[transitionID] = frame
    }

    func frame(for transitionID: PhotoPreviewTransitionID) -> CGRect? {
        frames[transitionID]
    }

    private static func isUsable(_ frame: CGRect) -> Bool {
        frame.width > 0
            && frame.height > 0
            && frame.minX.isFinite
            && frame.minY.isFinite
    }
}
