import SwiftUI

struct PhotoPreviewSource<Content: View>: View {
    @Environment(\.photoPreviewContext) private var previewContext
    let groupID: String
    let attachments: [Attachment]
    let attachment: Attachment
    var transitionStyle = PhotoPreviewTransitionStyle.plain
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
        .onGeometryChange(for: CGRect?.self) { proxy in
            let frame = proxy.frame(in: .named(PhotoPreviewContext.coordinateSpaceName))
            let viewport = CGRect(origin: .zero, size: previewContext.viewportSize)
            return frame.intersects(viewport) ? frame : nil
        } action: { frame in
            if let frame {
                previewContext.updateSourceFrame(transitionID, frame)
            }
        }
    }

    private var transitionID: PhotoPreviewTransitionID {
        PhotoPreviewTransitionID(
            groupID: groupID,
            attachmentID: attachment.id
        )
    }

    private func presentPreview() {
        previewContext.present(
            groupID,
            attachments,
            attachment.id,
            transitionStyle
        )
    }
}
