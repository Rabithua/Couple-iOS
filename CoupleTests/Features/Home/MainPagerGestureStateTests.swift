import CoreGraphics
import Testing
@testable import Couple

struct MainPagerGestureStateTests {
    private let containerSize = CGSize(width: 390, height: 844)

    @Test("A diagonal page swipe from the compose region stays horizontal")
    func diagonalPageSwipeNeverBecomesCompose() {
        var state = MainPagerGestureState()
        let startLocation = CGPoint(x: 195, y: 800)

        state.update(
            translation: CGSize(width: -20, height: -8),
            startLocation: startLocation,
            containerSize: containerSize,
            bottomSafeAreaInset: 34,
            route: .now
        )
        state.update(
            translation: CGSize(width: -140, height: -48),
            startLocation: startLocation,
            containerSize: containerSize,
            bottomSafeAreaInset: 34,
            route: .now
        )

        #expect(state.intent == .page)
        #expect(state.composeProgress == 0)
        #expect(state.shouldPresentComposer == false)
    }

    @Test("An upward pull from the bottom of Now reveals the composer")
    func bottomPullOnNowRevealsComposer() {
        var state = MainPagerGestureState()
        let startLocation = CGPoint(x: 195, y: 800)

        state.update(
            translation: CGSize(width: 3, height: -20),
            startLocation: startLocation,
            containerSize: containerSize,
            bottomSafeAreaInset: 34,
            route: .now
        )
        #expect(state.intent == .compose)
        #expect(state.shouldPresentComposer == false)

        state.update(
            translation: CGSize(
                width: 8,
                height: -MainPagerGestureState.composeActivationDistance
            ),
            startLocation: startLocation,
            containerSize: containerSize,
            bottomSafeAreaInset: 34,
            route: .now
        )

        #expect(state.composeProgress == 1)
        #expect(state.shouldPresentComposer)
    }

    @Test("Upward drags outside the bottom region remain normal scrolling")
    func pullOutsideBottomRegionIsIgnored() {
        var state = MainPagerGestureState()

        state.update(
            translation: CGSize(width: 2, height: -40),
            startLocation: CGPoint(x: 195, y: 500),
            containerSize: containerSize,
            bottomSafeAreaInset: 34,
            route: .now
        )

        #expect(state.intent == .ignored)
        #expect(state.shouldPresentComposer == false)
    }

    @Test("Upward drags from the system gesture edge are ignored")
    func pullFromSystemGestureEdgeIsIgnored() {
        var state = MainPagerGestureState()

        state.update(
            translation: CGSize(width: 2, height: -80),
            startLocation: CGPoint(x: 195, y: 814),
            containerSize: containerSize,
            bottomSafeAreaInset: 34,
            route: .now
        )

        #expect(state.intent == .ignored)
        #expect(state.shouldPresentComposer == false)
    }

    @Test("Upward drags on other pages never reveal the composer")
    func pullOutsideNowIsIgnored() {
        var state = MainPagerGestureState()

        state.update(
            translation: CGSize(width: 2, height: -40),
            startLocation: CGPoint(x: 195, y: 800),
            containerSize: containerSize,
            bottomSafeAreaInset: 34,
            route: .futureCalendar
        )

        #expect(state.intent == .ignored)
        #expect(state.shouldPresentComposer == false)
    }

    @Test("An ambiguous start can resolve horizontally before locking")
    func ambiguousStartCanResolveToPageSwipe() {
        var state = MainPagerGestureState()
        let startLocation = CGPoint(x: 195, y: 800)

        state.update(
            translation: CGSize(width: -13, height: -12),
            startLocation: startLocation,
            containerSize: containerSize,
            bottomSafeAreaInset: 34,
            route: .now
        )
        #expect(state.intent == .undecided)

        state.update(
            translation: CGSize(width: -32, height: -15),
            startLocation: startLocation,
            containerSize: containerSize,
            bottomSafeAreaInset: 34,
            route: .now
        )

        #expect(state.intent == .page)
    }

}
