import SwiftUI

struct JustifiedPhotoTile: View {
    let attachment: Attachment
    let attachments: [Attachment]
    let previewGroupID: String?

    var body: some View {
        Group {
            if let previewGroupID, attachment.isImage {
                PhotoPreviewSource(
                    groupID: previewGroupID,
                    attachments: attachments,
                    attachment: attachment
                ) {
                    AttachmentImage(attachment: attachment, contentMode: .fill)
                }
            } else {
                AttachmentImage(attachment: attachment, contentMode: .fill)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
