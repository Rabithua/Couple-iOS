import SwiftUI

struct PhotoPreviewView: View {
    @Bindable var presentation: PhotoPreviewPresentation
    let hidesSystemOverlays: Bool
    let dismiss: () -> Void

    var body: some View {
        TabView(selection: $presentation.selectedAttachmentID) {
            ForEach(presentation.attachments) { attachment in
                PhotoPreviewPage(
                    attachment: attachment,
                    position: presentation.position(for: attachment.id),
                    total: presentation.attachments.count,
                    dismiss: dismiss
                )
                .tag(attachment.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .accessibilityIdentifier("photoPreviewPager")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .all)
        .persistentSystemOverlays(hidesSystemOverlays ? .hidden : .automatic)
        .accessibilityAction(.escape, dismiss)
    }
}
