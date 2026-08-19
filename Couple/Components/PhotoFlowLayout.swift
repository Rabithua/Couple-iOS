import SwiftUI

struct PhotoFlowLayout: Layout {
    var spacing: CGFloat = 7.5

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct AttachmentFlow: View {
    let attachments: [Attachment]
    var height: CGFloat = 144
    var previewGroupID: String?

    var body: some View {
        PhotoFlowLayout {
            ForEach(attachments) { attachment in
                let itemWidth = Self.itemWidth(
                    height: height,
                    aspectRatio: attachment.aspectRatio
                )
                if let previewGroupID, attachment.isImage {
                    PhotoPreviewSource(
                        groupID: previewGroupID,
                        attachments: attachments,
                        attachment: attachment
                    ) {
                        AttachmentImage(
                            attachment: attachment,
                            contentMode: .fit,
                            maximumDisplayDimension: max(itemWidth, height)
                        )
                            .frame(
                                width: itemWidth,
                                height: height
                            )
                            .clipped()
                    }
                } else {
                    AttachmentImage(
                        attachment: attachment,
                        contentMode: .fit,
                        maximumDisplayDimension: max(itemWidth, height)
                    )
                        .frame(
                            width: itemWidth,
                            height: height
                        )
                        .clipped()
                }
            }
        }
    }

    static func itemWidth(height: CGFloat, aspectRatio: CGFloat) -> CGFloat {
        min(max(height * aspectRatio, 82), 216)
    }
}
