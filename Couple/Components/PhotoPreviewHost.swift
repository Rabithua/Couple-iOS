import SwiftUI

struct PhotoPreviewHost<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace
    @State private var presentation: PhotoPreviewPresentation?
    let canPresent: @MainActor () -> Bool
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            content
                .environment(\.photoPreviewContext, previewContext)
                .allowsHitTesting(presentation == nil)
                .accessibilityHidden(presentation != nil)

            Color.black
                .opacity(presentation == nil ? 0 : 1)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(backgroundAnimation, value: presentation != nil)

            if let presentation {
                PhotoPreviewView(
                    presentation: presentation,
                    dismiss: dismissPreview
                )
                // Match the eagerly-created pager container. TabView creates its page
                // contents too late for the opening animation transaction on iOS 17.
                .photoPreviewMatchedGeometry(
                    id: presentation.transitionID(for: presentation.selectedAttachmentID),
                    namespace: namespace,
                    enabled: reduceMotion == false
                )
                .transition(reduceMotion ? .opacity : .identity)
                .ignoresSafeArea(.container, edges: .all)
                .zIndex(1)
            }
        }
        .statusBarHidden(presentation != nil)
    }

    private var previewContext: PhotoPreviewContext {
        PhotoPreviewContext(
            namespace: namespace,
            activeTransitionID: presentation?.selectedTransitionID,
            sharedTransitionEnabled: reduceMotion == false,
            present: presentPreview
        )
    }

    private var transitionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.48)
    }

    private var backgroundAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.24)
    }

    private func presentPreview(
        groupID: String,
        attachments: [Attachment],
        selectedAttachmentID: String
    ) {
        guard canPresent(),
              presentation == nil,
              let nextPresentation = PhotoPreviewPresentation(
                groupID: groupID,
                attachments: attachments,
                selectedAttachmentID: selectedAttachmentID
              ) else { return }

        withAnimation(transitionAnimation) {
            presentation = nextPresentation
        }
    }

    private func dismissPreview() {
        withAnimation(transitionAnimation) {
            presentation = nil
        }
    }
}
