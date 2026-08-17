import SwiftUI

struct PhotoPreviewTransitionImage: View {
    let attachment: Attachment

    var body: some View {
        ZStack {
            Color.clear
            AttachmentImage(attachment: attachment, contentMode: .fit)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .all)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
