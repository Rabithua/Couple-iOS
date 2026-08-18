import SwiftUI

struct PhotoPreviewPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let attachment: Attachment
    let position: Int
    let total: Int
    let dismiss: () -> Void
    @State private var zoomState = PhotoPreviewZoomState()
    @GestureState private var transientMagnification: CGFloat = 1
    @GestureState private var transientMagnifyAnchor = UnitPoint.center
    @GestureState private var transientPan = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            let displayScale = zoomState.displayScale(for: transientMagnification)
            let displayOffset = zoomState.displayOffset(
                for: transientMagnification,
                anchor: transientMagnifyAnchor,
                translation: transientPan,
                containerSize: proxy.size,
                aspectRatio: attachment.aspectRatio
            )

            ZStack {
                Color.black
                AttachmentImage(
                    attachment: attachment,
                    contentMode: .fit,
                    placeholderColor: .black
                )
                    .scaleEffect(displayScale)
                    .offset(displayOffset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(.rect)
            .clipped()
            .highPriorityGesture(
                tapGesture(
                    in: proxy.size,
                    aspectRatio: attachment.aspectRatio
                )
            )
            .highPriorityGesture(
                panGesture(
                    in: proxy.size,
                    aspectRatio: attachment.aspectRatio
                ),
                including: zoomState.isZoomed ? .all : .subviews
            )
            .simultaneousGesture(
                magnifyGesture(
                    in: proxy.size,
                    aspectRatio: attachment.aspectRatio
                )
            )
            .accessibilityLabel(attachment.filename)
            .accessibilityValue(AppLocalization.string("photoPreviewPositionAndZoom",
                defaultValue: "第 \(position) 张，共 \(total) 张，缩放 \(Int((displayScale * 100).rounded()))%"
            ))
            .accessibilityHint("激活退出全屏预览，上下轻扫调整缩放")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                dismissPreview()
            }
            .accessibilityAction(
                named: Text(
                    zoomState.isZoomed
                        ? AppLocalization.string("复原图片")
                        : AppLocalization.string("放大图片")
                )
            ) {
                toggleZoom(
                    at: .center,
                    containerSize: proxy.size,
                    aspectRatio: attachment.aspectRatio
                )
            }
            .accessibilityAdjustableAction { direction in
                adjustZoom(
                    direction,
                    containerSize: proxy.size,
                    aspectRatio: attachment.aspectRatio
                )
            }
            .accessibilityIdentifier("photoPreviewPage-\(attachment.id)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .all)
    }

    private func tapGesture(
        in containerSize: CGSize,
        aspectRatio: CGFloat
    ) -> some Gesture {
        SpatialTapGesture(count: 2)
            .exclusively(before: SpatialTapGesture(count: 1))
            .onEnded { value in
                switch value {
                case .first(let doubleTap):
                    toggleZoom(
                        at: UnitPoint(
                            x: doubleTap.location.x / containerSize.width,
                            y: doubleTap.location.y / containerSize.height
                        ),
                        containerSize: containerSize,
                        aspectRatio: aspectRatio
                    )
                case .second:
                    dismissPreview()
                }
            }
    }

    private func magnifyGesture(
        in containerSize: CGSize,
        aspectRatio: CGFloat
    ) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .updating($transientMagnification) { value, state, _ in
                state = value.magnification
            }
            .updating($transientMagnifyAnchor) { value, state, _ in
                state = value.startAnchor
            }
            .onEnded { value in
                withAnimation(settleAnimation) {
                    zoomState.settleMagnification(
                        value.magnification,
                        anchor: value.startAnchor,
                        containerSize: containerSize,
                        aspectRatio: aspectRatio
                    )
                }
            }
    }

    private func panGesture(
        in containerSize: CGSize,
        aspectRatio: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($transientPan) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                zoomState.settlePan(
                    value.translation,
                    containerSize: containerSize,
                    aspectRatio: aspectRatio
                )
            }
    }

    private var settleAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.2)
    }

    private func adjustZoom(
        _ direction: AccessibilityAdjustmentDirection,
        containerSize: CGSize,
        aspectRatio: CGFloat
    ) {
        let factor: CGFloat
        switch direction {
        case .increment:
            factor = 1.5
        case .decrement:
            factor = 1 / 1.5
        @unknown default:
            return
        }
        withAnimation(settleAnimation) {
            zoomState.adjustScale(
                by: factor,
                containerSize: containerSize,
                aspectRatio: aspectRatio
            )
        }
    }

    private func toggleZoom(
        at anchor: UnitPoint,
        containerSize: CGSize,
        aspectRatio: CGFloat
    ) {
        withAnimation(settleAnimation) {
            zoomState.toggleZoom(
                anchor: anchor,
                containerSize: containerSize,
                aspectRatio: aspectRatio
            )
        }
    }

    private func dismissPreview() {
        zoomState.reset()
        dismiss()
    }
}
