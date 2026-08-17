import SwiftUI

struct PhotoPreviewHost<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace
    @State private var presentation: PhotoPreviewPresentation?
    @State private var transitionState = PhotoPreviewTransitionState()
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
                .opacity(transitionState.showsInteractivePreview ? 1 : 0)
                .allowsHitTesting(transitionState.showsInteractivePreview)
                .accessibilityHidden(!transitionState.showsInteractivePreview)
                .ignoresSafeArea(.container, edges: .all)
                .zIndex(1)

                if transitionState.showsTransitionImage,
                   let attachment = presentation.selectedAttachment {
                    PhotoPreviewTransitionImage(attachment: attachment)
                        .photoPreviewMatchedGeometry(
                            id: presentation.transitionID(for: attachment.id),
                            namespace: namespace,
                            enabled: reduceMotion == false
                        )
                        .transition(reduceMotion ? .opacity : .identity)
                        .zIndex(2)
                }
            }
        }
        .task(id: transitionState.phase) {
            await continueDismissalAfterLayout()
        }
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
              ),
              transitionState.beginPresentation() else { return }

        withAnimation(transitionAnimation) {
            presentation = nextPresentation
        } completion: {
            withoutAnimation {
                transitionState.finishPresentation()
            }
        }
    }

    private func dismissPreview() {
        guard presentation != nil else { return }
        withoutAnimation {
            _ = transitionState.prepareDismissal()
        }
    }

    private func continueDismissalAfterLayout() async {
        guard transitionState.phase == .preparingDismissal else { return }

        // Give the dedicated transition image one layout pass before it replaces
        // the interactive pager and starts animating back to the source.
        await Task.yield()

        guard !Task.isCancelled,
              transitionState.beginDismissal() else { return }
        withAnimation(transitionAnimation) {
            presentation = nil
        } completion: {
            transitionState.finishDismissal()
        }
    }

    private func withoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }
}
