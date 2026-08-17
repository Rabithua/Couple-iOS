import SwiftUI

struct PhotoPreviewTransitionImage: View {
    let attachment: Attachment
    let transitionID: PhotoPreviewTransitionID
    let namespace: Namespace.ID

    var body: some View {
        GeometryReader { proxy in
            let imageSize = fittedImageSize(in: proxy.size)

            ZStack {
                AttachmentImage(attachment: attachment, contentMode: .fit)
                    .frame(width: imageSize.width, height: imageSize.height)
                    .photoPreviewMatchedGeometry(
                        id: transitionID,
                        namespace: namespace,
                        enabled: true
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea(.container, edges: .all)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func fittedImageSize(in containerSize: CGSize) -> CGSize {
        guard containerSize.width > 0,
              containerSize.height > 0,
              attachment.aspectRatio > 0 else { return .zero }

        let containerAspectRatio = containerSize.width / containerSize.height
        if attachment.aspectRatio > containerAspectRatio {
            return CGSize(
                width: containerSize.width,
                height: containerSize.width / attachment.aspectRatio
            )
        }
        return CGSize(
            width: containerSize.height * attachment.aspectRatio,
            height: containerSize.height
        )
    }
}
