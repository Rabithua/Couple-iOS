import Testing
import SwiftUI
@testable import Couple

@MainActor
struct PhotoPreviewZoomStateTests {
    private let containerSize = CGSize(width: 300, height: 300)

    @Test("Zoom scale is clamped to the supported range")
    func scaleClampsToSupportedRange() {
        var state = PhotoPreviewZoomState()

        state.settleMagnification(
            10,
            anchor: .center,
            containerSize: containerSize,
            aspectRatio: 1
        )
        #expect(state.scale == PhotoPreviewZoomState.maximumScale)

        state.settleMagnification(
            0.01,
            anchor: .center,
            containerSize: containerSize,
            aspectRatio: 1
        )
        #expect(state.scale == PhotoPreviewZoomState.minimumScale)
        #expect(state.offset == .zero)
    }

    @Test("Live magnification never renders below one times")
    func liveMagnificationDoesNotUndershootMinimumScale() {
        let state = PhotoPreviewZoomState()

        #expect(state.displayScale(for: 0.5) == PhotoPreviewZoomState.minimumScale)
        #expect(
            state.displayOffset(
                for: 0.5,
                anchor: .topLeading,
                translation: .zero,
                containerSize: containerSize,
                aspectRatio: 1
            ) == .zero
        )
    }

    @Test("Pan is constrained to the scaled image bounds")
    func panClampsToImageBounds() {
        var state = PhotoPreviewZoomState()
        state.settleMagnification(
            2,
            anchor: .center,
            containerSize: containerSize,
            aspectRatio: 1
        )

        state.settlePan(
            CGSize(width: 1_000, height: -1_000),
            containerSize: containerSize,
            aspectRatio: 1
        )

        #expect(state.offset == CGSize(width: 150, height: -150))
    }

    @Test("Magnification keeps its starting anchor stable")
    func magnificationPreservesAnchor() {
        var state = PhotoPreviewZoomState()

        state.settleMagnification(
            2,
            anchor: .topLeading,
            containerSize: containerSize,
            aspectRatio: 1
        )

        #expect(state.offset == CGSize(width: 150, height: 150))
    }

    @Test("Double tap zooms around its location and then resets")
    func doubleTapTogglesZoom() {
        var state = PhotoPreviewZoomState()

        state.toggleZoom(
            anchor: .topLeading,
            containerSize: containerSize,
            aspectRatio: 1
        )

        #expect(state.scale == PhotoPreviewZoomState.doubleTapScale)
        #expect(state.offset == CGSize(width: 150, height: 150))

        state.toggleZoom(
            anchor: .bottomTrailing,
            containerSize: containerSize,
            aspectRatio: 1
        )

        #expect(state.scale == PhotoPreviewZoomState.minimumScale)
        #expect(state.offset == .zero)
    }
}
