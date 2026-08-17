import SwiftUI

struct PhotoPreviewTransitionImage: View {
    let attachment: Attachment
    let sourceFrame: CGRect
    let progress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let containerFrame = proxy.frame(
                in: .named(PhotoPreviewContext.coordinateSpaceName)
            )
            let localSourceFrame = sourceFrame.offsetBy(
                dx: -containerFrame.minX,
                dy: -containerFrame.minY
            )
            let destinationFrame = fittedImageFrame(in: proxy.size)
            let imageFrame = interpolatedFrame(
                from: localSourceFrame,
                to: destinationFrame
            )

            AttachmentImage(attachment: attachment, contentMode: .fit)
                .frame(width: imageFrame.width, height: imageFrame.height)
                .position(x: imageFrame.midX, y: imageFrame.midY)
        }
        .ignoresSafeArea(.container, edges: .all)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func fittedImageFrame(in containerSize: CGSize) -> CGRect {
        guard containerSize.width > 0,
              containerSize.height > 0,
              attachment.aspectRatio > 0 else { return .zero }

        let containerAspectRatio = containerSize.width / containerSize.height
        let imageSize: CGSize
        if attachment.aspectRatio > containerAspectRatio {
            imageSize = CGSize(
                width: containerSize.width,
                height: containerSize.width / attachment.aspectRatio
            )
        } else {
            imageSize = CGSize(
                width: containerSize.height * attachment.aspectRatio,
                height: containerSize.height
            )
        }

        return CGRect(
            x: (containerSize.width - imageSize.width) / 2,
            y: (containerSize.height - imageSize.height) / 2,
            width: imageSize.width,
            height: imageSize.height
        )
    }

    private func interpolatedFrame(from start: CGRect, to end: CGRect) -> CGRect {
        let clampedProgress = min(max(progress, 0), 1)
        return CGRect(
            x: start.minX + (end.minX - start.minX) * clampedProgress,
            y: start.minY + (end.minY - start.minY) * clampedProgress,
            width: start.width + (end.width - start.width) * clampedProgress,
            height: start.height + (end.height - start.height) * clampedProgress
        )
    }
}
