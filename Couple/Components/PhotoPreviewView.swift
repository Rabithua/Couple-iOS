import SwiftUI

struct PhotoPreviewView: View {
    @Bindable var presentation: PhotoPreviewPresentation
    @State private var visibleAttachmentID: String?
    let dismiss: () -> Void

    init(
        presentation: PhotoPreviewPresentation,
        dismiss: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.dismiss = dismiss
        _visibleAttachmentID = State(
            initialValue: presentation.selectedAttachmentID
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(presentation.attachments) { attachment in
                        PhotoPreviewPage(
                            attachment: attachment,
                            position: presentation.position(for: attachment.id),
                            total: presentation.attachments.count,
                            dismiss: dismiss
                        )
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height
                        )
                        .id(attachment.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleAttachmentID)
            .background(Color.black)
            .onChange(of: visibleAttachmentID) { _, attachmentID in
                guard let attachmentID else { return }
                presentation.selectedAttachmentID = attachmentID
            }
        }
        .background(Color.black)
        .accessibilityIdentifier("photoPreviewPager")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .all)
        .accessibilityAction(.escape, dismiss)
    }
}
