import Foundation
import Observation

@MainActor
@Observable
final class PhotoPreviewPresentation {
    let groupID: String
    let attachments: [Attachment]
    var selectedAttachmentID: String

    init?(
        groupID: String,
        attachments: [Attachment],
        selectedAttachmentID: String
    ) {
        let imageAttachments = attachments.filter(\.isImage)
        guard imageAttachments.contains(where: { $0.id == selectedAttachmentID }) else {
            return nil
        }

        self.groupID = groupID
        self.attachments = imageAttachments
        self.selectedAttachmentID = selectedAttachmentID
    }

    var selectedIndex: Int? {
        attachments.firstIndex { $0.id == selectedAttachmentID }
    }

    var selectedTransitionID: PhotoPreviewTransitionID? {
        guard attachments.contains(where: { $0.id == selectedAttachmentID }) else {
            return nil
        }
        return transitionID(for: selectedAttachmentID)
    }

    func position(for attachmentID: String) -> Int {
        (attachments.firstIndex { $0.id == attachmentID } ?? 0) + 1
    }

    func transitionID(for attachmentID: String) -> PhotoPreviewTransitionID {
        PhotoPreviewTransitionID(groupID: groupID, attachmentID: attachmentID)
    }
}
