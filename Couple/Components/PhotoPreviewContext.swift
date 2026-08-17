import SwiftUI

struct PhotoPreviewContext {
    static let disabled = PhotoPreviewContext(
        namespace: nil,
        activeTransitionID: nil,
        sharedTransitionEnabled: false,
        present: { _, _, _ in }
    )

    let namespace: Namespace.ID?
    let activeTransitionID: PhotoPreviewTransitionID?
    let sharedTransitionEnabled: Bool
    let present: @MainActor (String, [Attachment], String) -> Void
}

extension EnvironmentValues {
    @Entry var photoPreviewContext = PhotoPreviewContext.disabled
}

extension View {
    @ViewBuilder
    func photoPreviewMatchedGeometry(
        id: PhotoPreviewTransitionID,
        namespace: Namespace.ID?,
        enabled: Bool,
        isSource: Bool
    ) -> some View {
        if enabled, let namespace {
            matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                anchor: .center,
                isSource: isSource
            )
        } else {
            self
        }
    }
}
