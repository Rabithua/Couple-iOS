import CoreGraphics

struct MainPagerGestureState: Equatable {
    enum Intent: Equatable {
        case undecided
        case page
        case compose
        case ignored
    }

    static let composeActivationDistance: CGFloat = 68

    private static let intentDecisionDistance: CGFloat = 12
    private static let ambiguousDecisionDistance: CGFloat = 24
    private static let pageAxisRatio: CGFloat = 1.6
    private static let settingsPageAxisRatio: CGFloat = 2.2
    private static let pageCommitDistance: CGFloat = 36
    private static let projectedPageCommitDistance: CGFloat = 80
    private static let composeAxisRatio: CGFloat = 1.45
    private static let composeRegionHeight: CGFloat = 104

    private(set) var intent: Intent = .undecided
    private(set) var composeProgress: CGFloat = 0
    private(set) var pageTranslation: CGFloat = 0
    private(set) var pageSourceRoute: MainPagerRoute?

    var shouldPresentComposer: Bool {
        intent == .compose && composeProgress >= 1
    }

    var blocksVerticalScrolling: Bool {
        intent == .page
    }

    func shouldCommitPageSwipe(
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        guard intent == .page else { return false }

        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        guard horizontal > vertical * Self.pageAxisRatio(for: pageSourceRoute) else {
            return false
        }

        return horizontal >= Self.pageCommitDistance
            || abs(predictedEndTranslation.width) >= Self.projectedPageCommitDistance
    }

    mutating func update(
        translation: CGSize,
        startLocation: CGPoint,
        containerSize: CGSize,
        bottomSafeAreaInset: CGFloat,
        route: MainPagerRoute
    ) {
        if intent == .compose {
            updateComposeProgress(translation.height)
            return
        }

        if intent == .page {
            pageTranslation = translation.width
            return
        }

        guard intent == .undecided else { return }

        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        let distance = max(horizontal, vertical)
        guard distance >= Self.intentDecisionDistance else { return }

        if horizontal > vertical * Self.pageAxisRatio(for: route) {
            intent = .page
            pageTranslation = translation.width
            pageSourceRoute = route
            return
        }

        if canStartCompose(
            translation: translation,
            startLocation: startLocation,
            containerSize: containerSize,
            bottomSafeAreaInset: bottomSafeAreaInset,
            route: route
        ) {
            intent = .compose
            updateComposeProgress(translation.height)
            return
        }

        if distance >= Self.ambiguousDecisionDistance {
            intent = .ignored
        }
    }

    mutating func reset() {
        self = Self()
    }

    private func canStartCompose(
        translation: CGSize,
        startLocation: CGPoint,
        containerSize: CGSize,
        bottomSafeAreaInset: CGFloat,
        route: MainPagerRoute
    ) -> Bool {
        guard route == .now else { return false }
        guard startLocation.y >= containerSize.height - Self.composeRegionHeight else { return false }
        guard startLocation.y <= containerSize.height - bottomSafeAreaInset else {
            return false
        }
        guard translation.height < 0 else { return false }
        return abs(translation.height) > abs(translation.width) * Self.composeAxisRatio
    }

    private mutating func updateComposeProgress(_ verticalTranslation: CGFloat) {
        composeProgress = min(
            max(-verticalTranslation / Self.composeActivationDistance, 0),
            1
        )
    }

    private static func pageAxisRatio(for route: MainPagerRoute?) -> CGFloat {
        route == .futureSettings ? settingsPageAxisRatio : pageAxisRatio
    }
}
