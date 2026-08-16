import Testing
@testable import Couple

@MainActor
struct PhotoPreviewPresentationTests {
    @Test("Presentation starts on the requested image")
    func startsOnRequestedImage() throws {
        let attachments = Array(SampleData.attachments.prefix(3))
        let selectedAttachment = try #require(attachments.last)
        let presentation = try #require(PhotoPreviewPresentation(
            groupID: "past.photos.note-1",
            attachments: attachments,
            selectedAttachmentID: selectedAttachment.id
        ))

        #expect(presentation.attachments == attachments)
        #expect(presentation.selectedAttachmentID == selectedAttachment.id)
        #expect(presentation.selectedIndex == 2)
    }

    @Test("Changing pages updates the selected transition target")
    func pageSelectionUpdatesTransitionTarget() throws {
        let attachments = Array(SampleData.attachments.prefix(2))
        let firstAttachment = try #require(attachments.first)
        let secondAttachment = try #require(attachments.last)
        let presentation = try #require(PhotoPreviewPresentation(
            groupID: "home.featured",
            attachments: attachments,
            selectedAttachmentID: firstAttachment.id
        ))

        presentation.selectedAttachmentID = secondAttachment.id

        #expect(presentation.selectedIndex == 1)
        #expect(
            presentation.selectedTransitionID
                == PhotoPreviewTransitionID(
                    groupID: "home.featured",
                    attachmentID: secondAttachment.id
                )
        )
    }

    @Test("The same attachment in separate groups has distinct transition identities")
    func duplicateAttachmentUsesGroupScopedIdentity() throws {
        let attachment = try #require(SampleData.attachments.first)
        let firstPresentation = try #require(PhotoPreviewPresentation(
            groupID: "past.all.note-1",
            attachments: [attachment],
            selectedAttachmentID: attachment.id
        ))
        let secondPresentation = try #require(PhotoPreviewPresentation(
            groupID: "past.photos.note-1",
            attachments: [attachment],
            selectedAttachmentID: attachment.id
        ))

        #expect(firstPresentation.selectedTransitionID != secondPresentation.selectedTransitionID)
    }

    @Test("A missing initial image cannot create a presentation")
    func rejectsMissingInitialImage() {
        let presentation = PhotoPreviewPresentation(
            groupID: "home.featured",
            attachments: Array(SampleData.attachments.prefix(2)),
            selectedAttachmentID: "missing"
        )

        #expect(presentation == nil)
    }
}
