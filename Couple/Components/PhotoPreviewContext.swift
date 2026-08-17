import SwiftUI

struct PhotoPreviewContext {
    static let coordinateSpaceName = "photoPreviewHost"

    static let disabled = PhotoPreviewContext(
        activeTransitionID: nil,
        updateSourceFrame: { _, _ in },
        present: { _, _, _, _ in }
    )

    let activeTransitionID: PhotoPreviewTransitionID?
    let updateSourceFrame: @MainActor (PhotoPreviewTransitionID, CGRect) -> Void
    let present: @MainActor (String, [Attachment], String, CGRect) -> Void
}

extension EnvironmentValues {
    @Entry var photoPreviewContext = PhotoPreviewContext.disabled
}
