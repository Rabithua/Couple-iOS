import SwiftUI

struct PhotoPreviewHost<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentation: PhotoPreviewPresentation?
    @State private var isTransitioning = false
    @State private var transitionProgress: CGFloat = 0
    @State private var transitionSourceFrame = CGRect.zero
    @State private var transitionStyle = PhotoPreviewTransitionStyle.plain
    @State private var sourceFrames: [PhotoPreviewTransitionID: CGRect] = [:]
    let canPresent: @MainActor () -> Bool
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            content
                .environment(\.photoPreviewContext, previewContext)
                .allowsHitTesting(presentation == nil)
                .accessibilityHidden(presentation != nil)

            Color.black
                .opacity(
                    presentation == nil
                        ? 0
                        : Double(min(transitionProgress * 2, 1))
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if let presentation {
                PhotoPreviewView(
                    presentation: presentation,
                    dismiss: dismissPreview
                )
                .id(ObjectIdentifier(presentation))
                .opacity(previewOpacity)
                .allowsHitTesting(!isTransitioning)
                .accessibilityHidden(isTransitioning)
                .transition(reduceMotion ? .opacity : .identity)
                .ignoresSafeArea(.container, edges: .all)
                .zIndex(1)

                if isTransitioning,
                   let attachment = presentation.selectedAttachment {
                    PhotoPreviewTransitionImage(
                        attachment: attachment,
                        sourceFrame: transitionSourceFrame,
                        progress: transitionProgress,
                        style: transitionStyle
                    )
                    .zIndex(2)
                }
            }
        }
        .coordinateSpace(name: PhotoPreviewContext.coordinateSpaceName)
    }

    private var previewContext: PhotoPreviewContext {
        PhotoPreviewContext(
            activeTransitionID: presentation?.selectedTransitionID,
            updateSourceFrame: updateSourceFrame,
            present: presentPreview
        )
    }

    private var previewOpacity: Double {
        if isTransitioning { return 0 }
        return reduceMotion ? Double(transitionProgress) : 1
    }

    private var transitionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.48)
    }

    private func presentPreview(
        groupID: String,
        attachments: [Attachment],
        selectedAttachmentID: String,
        sourceFrame: CGRect,
        style: PhotoPreviewTransitionStyle
    ) {
        guard canPresent(),
              presentation == nil,
              let nextPresentation = PhotoPreviewPresentation(
                groupID: groupID,
                attachments: attachments,
                selectedAttachmentID: selectedAttachmentID
              ) else { return }

        let transitionID = nextPresentation.transitionID(for: selectedAttachmentID)
        let resolvedSourceFrame = sourceFrames[transitionID] ?? sourceFrame
        guard reduceMotion || isUsable(resolvedSourceFrame) else { return }

        withoutAnimation {
            transitionSourceFrame = resolvedSourceFrame
            transitionStyle = style
            transitionProgress = 0
            isTransitioning = !reduceMotion
            presentation = nextPresentation
        }

        Task { @MainActor in
            await Task.yield()
            guard presentation === nextPresentation else { return }

            withAnimation(transitionAnimation) {
                transitionProgress = 1
            } completion: {
                guard presentation === nextPresentation else { return }
                withoutAnimation {
                    isTransitioning = false
                }
            }
        }
    }

    private func dismissPreview() {
        guard let currentPresentation = presentation else { return }

        let destinationFrame = currentPresentation.selectedTransitionID
            .flatMap { sourceFrames[$0] }
        let resolvedSourceFrame = destinationFrame ?? transitionSourceFrame

        withoutAnimation {
            if isUsable(resolvedSourceFrame) {
                transitionSourceFrame = resolvedSourceFrame
            }
            transitionProgress = 1
            isTransitioning = !reduceMotion
        }
        Task { @MainActor in
            await Task.yield()
            guard presentation === currentPresentation else { return }

            withAnimation(transitionAnimation) {
                transitionProgress = 0
            } completion: {
                guard presentation === currentPresentation else { return }
                withoutAnimation {
                    presentation = nil
                    isTransitioning = false
                    transitionProgress = 0
                    transitionSourceFrame = .zero
                    transitionStyle = .plain
                }
            }
        }
    }

    private func updateSourceFrame(
        _ transitionID: PhotoPreviewTransitionID,
        _ frame: CGRect
    ) {
        guard isUsable(frame), sourceFrames[transitionID] != frame else { return }
        sourceFrames[transitionID] = frame
    }

    private func isUsable(_ frame: CGRect) -> Bool {
        frame.width > 0
            && frame.height > 0
            && frame.minX.isFinite
            && frame.minY.isFinite
    }

    private func withoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }
}
