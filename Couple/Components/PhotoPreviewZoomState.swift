import SwiftUI

struct PhotoPreviewZoomState: Equatable {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 4
    static let doubleTapScale: CGFloat = 2
    private static let maximumElasticScale: CGFloat = 4.25

    private(set) var scale: CGFloat = minimumScale
    private(set) var offset = CGSize.zero

    var isZoomed: Bool {
        scale > Self.minimumScale + 0.001
    }

    func displayScale(for magnification: CGFloat) -> CGFloat {
        min(
            max(scale * magnification, Self.minimumScale),
            Self.maximumElasticScale
        )
    }

    func displayOffset(
        for magnification: CGFloat,
        anchor: UnitPoint,
        translation: CGSize,
        containerSize: CGSize,
        aspectRatio: CGFloat
    ) -> CGSize {
        let proposedScale = displayScale(for: magnification)
        let anchoredOffset = offsetKeepingAnchorFixed(
            from: scale,
            to: proposedScale,
            anchor: anchor,
            containerSize: containerSize
        )
        let proposedOffset = CGSize(
            width: anchoredOffset.width + translation.width,
            height: anchoredOffset.height + translation.height
        )
        return Self.clampedOffset(
            proposedOffset,
            scale: proposedScale,
            containerSize: containerSize,
            aspectRatio: aspectRatio
        )
    }

    mutating func settleMagnification(
        _ magnification: CGFloat,
        anchor: UnitPoint,
        containerSize: CGSize,
        aspectRatio: CGFloat
    ) {
        let settledScale = min(
            max(scale * magnification, Self.minimumScale),
            Self.maximumScale
        )
        let anchoredOffset = offsetKeepingAnchorFixed(
            from: scale,
            to: settledScale,
            anchor: anchor,
            containerSize: containerSize
        )

        scale = settledScale
        offset = settledScale == Self.minimumScale
            ? .zero
            : Self.clampedOffset(
                anchoredOffset,
                scale: settledScale,
                containerSize: containerSize,
                aspectRatio: aspectRatio
            )
    }

    mutating func settlePan(
        _ translation: CGSize,
        containerSize: CGSize,
        aspectRatio: CGFloat
    ) {
        let proposedOffset = CGSize(
            width: offset.width + translation.width,
            height: offset.height + translation.height
        )
        offset = Self.clampedOffset(
            proposedOffset,
            scale: scale,
            containerSize: containerSize,
            aspectRatio: aspectRatio
        )
    }

    mutating func adjustScale(
        by factor: CGFloat,
        containerSize: CGSize,
        aspectRatio: CGFloat
    ) {
        settleMagnification(
            factor,
            anchor: .center,
            containerSize: containerSize,
            aspectRatio: aspectRatio
        )
    }

    mutating func toggleZoom(
        anchor: UnitPoint,
        containerSize: CGSize,
        aspectRatio: CGFloat
    ) {
        guard !isZoomed else {
            reset()
            return
        }

        settleMagnification(
            Self.doubleTapScale,
            anchor: anchor,
            containerSize: containerSize,
            aspectRatio: aspectRatio
        )
    }

    mutating func reset() {
        scale = Self.minimumScale
        offset = .zero
    }

    private func offsetKeepingAnchorFixed(
        from oldScale: CGFloat,
        to newScale: CGFloat,
        anchor: UnitPoint,
        containerSize: CGSize
    ) -> CGSize {
        let anchorVector = CGSize(
            width: (anchor.x - 0.5) * containerSize.width,
            height: (anchor.y - 0.5) * containerSize.height
        )
        return CGSize(
            width: offset.width + (oldScale - newScale) * anchorVector.width,
            height: offset.height + (oldScale - newScale) * anchorVector.height
        )
    }

    private static func clampedOffset(
        _ offset: CGSize,
        scale: CGFloat,
        containerSize: CGSize,
        aspectRatio: CGFloat
    ) -> CGSize {
        let imageSize = fittedImageSize(
            in: containerSize,
            aspectRatio: aspectRatio
        )
        let horizontalLimit = max(
            (imageSize.width * scale - containerSize.width) / 2,
            0
        )
        let verticalLimit = max(
            (imageSize.height * scale - containerSize.height) / 2,
            0
        )
        return CGSize(
            width: min(max(offset.width, -horizontalLimit), horizontalLimit),
            height: min(max(offset.height, -verticalLimit), verticalLimit)
        )
    }

    private static func fittedImageSize(
        in containerSize: CGSize,
        aspectRatio: CGFloat
    ) -> CGSize {
        guard containerSize.width > 0,
              containerSize.height > 0,
              aspectRatio > 0 else { return .zero }

        let containerAspectRatio = containerSize.width / containerSize.height
        if aspectRatio > containerAspectRatio {
            return CGSize(
                width: containerSize.width,
                height: containerSize.width / aspectRatio
            )
        }
        return CGSize(
            width: containerSize.height * aspectRatio,
            height: containerSize.height
        )
    }
}
