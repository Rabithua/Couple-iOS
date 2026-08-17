import SwiftUI

struct PhotoPreviewHost<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace
    @State private var presentation: PhotoPreviewPresentation?
    @State private var isTransitioning = false
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
                .opacity(isTransitioning ? 0 : 1)
                .allowsHitTesting(!isTransitioning)
                .accessibilityHidden(isTransitioning)
                .transition(reduceMotion ? .opacity : .identity)
                .ignoresSafeArea(.container, edges: .all)
                .zIndex(1)

                if isTransitioning,
                   let attachment = presentation.selectedAttachment {
                    PhotoPreviewTransitionImage(
                        attachment: attachment,
                        transitionID: presentation.transitionID(for: attachment.id),
                        namespace: namespace
                    )
                    .zIndex(2)
                }
            }
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
              ) else { return }

        guard !reduceMotion else {
            withAnimation(transitionAnimation) {
                presentation = nextPresentation
            }
            return
        }

        updateTransitioning(true)
        withAnimation(transitionAnimation) {
            presentation = nextPresentation
        } completion: {
            updateTransitioning(false)
        }
    }

    private func dismissPreview() {
        guard presentation != nil else { return }

        guard !reduceMotion else {
            withAnimation(transitionAnimation) {
                presentation = nil
            }
            return
        }

        updateTransitioning(true)
        Task { @MainActor in
            // Let the static transition image replace the pager before it moves.
            await Task.yield()
            guard isTransitioning, presentation != nil else { return }

            withAnimation(transitionAnimation) {
                presentation = nil
            } completion: {
                updateTransitioning(false)
            }
        }
    }

    private func updateTransitioning(_ value: Bool) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isTransitioning = value
        }
    }
}
