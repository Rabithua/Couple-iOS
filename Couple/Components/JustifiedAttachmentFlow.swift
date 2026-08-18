import SwiftUI

struct JustifiedAttachmentFlow: View {
    let attachments: [Attachment]
    let previewGroupID: String?

    var body: some View {
        JustifiedPhotoLayout(
            idealRowHeight: AppTheme.photoGalleryIdealRowHeight,
            spacing: AppTheme.photoGallerySpacing
        ) {
            ForEach(attachments) { attachment in
                JustifiedPhotoTile(
                    attachment: attachment,
                    attachments: attachments,
                    previewGroupID: previewGroupID
                )
                .layoutValue(
                    key: PhotoAspectRatioLayoutKey.self,
                    value: attachment.aspectRatio
                )
            }
        }
    }
}
