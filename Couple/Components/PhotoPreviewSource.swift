import SwiftUI

struct PhotoPreviewSource<Content: View>: View {
    @Environment(\.photoPreviewContext) private var previewContext
    @State private var sourceFrame = CGRect.zero
    let groupID: String
    let attachments: [Attachment]
    let attachment: Attachment
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: presentPreview) {
            content.opacity(previewContext.activeTransitionID == transitionID ? 0 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(attachment.filename)
        .accessibilityHint("全屏查看照片")
        .accessibilityIdentifier(
            "photoPreviewSource-\(groupID)-\(attachment.id)"
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(PhotoPreviewContext.coordinateSpaceName))
        } action: { frame in
            sourceFrame = frame
            previewContext.updateSourceFrame(transitionID, frame)
        }
    }

    private var transitionID: PhotoPreviewTransitionID {
        PhotoPreviewTransitionID(
            groupID: groupID,
            attachmentID: attachment.id
        )
    }

    private func presentPreview() {
        previewContext.present(groupID, attachments, attachment.id, sourceFrame)
    }
}
