import SwiftUI

struct PhotoPreviewContext {
    static let coordinateSpaceName = "photoPreviewHost"

    static let disabled = PhotoPreviewContext(
        activeTransitionID: nil,
        viewportSize: .zero,
        updateSourceFrame: { _, _ in },
        present: { _, _, _, _ in }
    )

    let activeTransitionID: PhotoPreviewTransitionID?
    let viewportSize: CGSize
    let updateSourceFrame: @MainActor (PhotoPreviewTransitionID, CGRect) -> Void
    let present: @MainActor (
        String,
        [Attachment],
        String,
        PhotoPreviewTransitionStyle
    ) -> Void
}

extension EnvironmentValues {
    @Entry var photoPreviewContext = PhotoPreviewContext.disabled
}
