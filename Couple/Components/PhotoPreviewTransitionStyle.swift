import CoreGraphics

struct PhotoPreviewTransitionStyle: Sendable {
    static let plain = PhotoPreviewTransitionStyle()
    static let featuredPhoto = PhotoPreviewTransitionStyle(
        borderWidth: 3,
        shadowOpacity: 0.2,
        shadowRadius: 14,
        shadowYOffset: 4,
        rotationDegrees: -1
    )

    var borderWidth: CGFloat = 0
    var shadowOpacity: Double = 0
    var shadowRadius: CGFloat = 0
    var shadowYOffset: CGFloat = 0
    var rotationDegrees: Double = 0
}
