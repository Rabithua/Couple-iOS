import Testing
@testable import Couple

struct PhotoPreviewTransitionStateTests {
    @Test("A stable transition image isolates the interactive pager")
    func stagesTransitionImageAroundAnimations() {
        var state = PhotoPreviewTransitionState()

        #expect(state.phase == .idle)
        #expect(state.showsTransitionImage == false)
        #expect(state.showsInteractivePreview == false)

        let beganPresentation = state.beginPresentation()
        #expect(beganPresentation)
        #expect(state.phase == .opening)
        #expect(state.showsTransitionImage)
        #expect(state.showsInteractivePreview == false)

        state.finishPresentation()
        #expect(state.phase == .presented)
        #expect(state.showsTransitionImage == false)
        #expect(state.showsInteractivePreview)

        let preparedDismissal = state.prepareDismissal()
        #expect(preparedDismissal)
        #expect(state.phase == .preparingDismissal)
        #expect(state.showsTransitionImage)
        #expect(state.showsInteractivePreview == false)

        let beganDismissal = state.beginDismissal()
        #expect(beganDismissal)
        #expect(state.phase == .closing)
        #expect(state.showsTransitionImage)
        #expect(state.showsInteractivePreview == false)

        state.finishDismissal()
        #expect(state.phase == .idle)
        #expect(state.showsTransitionImage == false)
        #expect(state.showsInteractivePreview == false)
    }

    @Test("A stale opening completion cannot interrupt dismissal")
    func ignoresStaleOpeningCompletion() {
        var state = PhotoPreviewTransitionState()

        let beganPresentation = state.beginPresentation()
        let preparedDismissal = state.prepareDismissal()
        #expect(beganPresentation)
        #expect(preparedDismissal)

        state.finishPresentation()

        #expect(state.phase == .preparingDismissal)
        #expect(state.showsTransitionImage)
        #expect(state.showsInteractivePreview == false)
    }

    @Test("Invalid duplicate transitions are ignored")
    func rejectsDuplicateTransitions() {
        var state = PhotoPreviewTransitionState()

        let beganPresentation = state.beginPresentation()
        let duplicatePresentation = state.beginPresentation()
        let prematureDismissal = state.beginDismissal()
        #expect(beganPresentation)
        #expect(duplicatePresentation == false)
        #expect(prematureDismissal == false)

        state.finishPresentation()
        let preparedDismissal = state.prepareDismissal()
        let duplicateDismissal = state.prepareDismissal()
        #expect(preparedDismissal)
        #expect(duplicateDismissal == false)
    }
}
