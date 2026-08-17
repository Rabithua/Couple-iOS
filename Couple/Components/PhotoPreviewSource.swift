import SwiftUI

struct PhotoPreviewSource<Content: View>: View {
    @Environment(\.photoPreviewContext) private var previewContext
    let groupID: String
    let attachments: [Attachment]
    let attachment: Attachment
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: presentPreview) {
            if previewContext.activeTransitionID == transitionID {
                // The source must leave the namespace in the same transaction
                // that inserts the dedicated full-screen transition image.
                content.opacity(0)
            } else {
                content.photoPreviewMatchedGeometry(
                    id: transitionID,
                    namespace: previewContext.namespace,
                    enabled: previewContext.sharedTransitionEnabled
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(attachment.filename)
        .accessibilityHint("全屏查看照片")
        .accessibilityIdentifier(
            "photoPreviewSource-\(groupID)-\(attachment.id)"
        )
    }

    private var transitionID: PhotoPreviewTransitionID {
        PhotoPreviewTransitionID(
            groupID: groupID,
            attachmentID: attachment.id
        )
    }

    private func presentPreview() {
        previewContext.present(groupID, attachments, attachment.id)
    }
}
