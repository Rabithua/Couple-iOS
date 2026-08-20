import SwiftUI

@MainActor
struct MainPagerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    @Environment(NotificationCoordinator.self) private var notifications
    @State private var route: MainPagerRoute
    @State private var showingComposer = false
    @State private var photoCarouselFrame = ViewFrameStore()
    @State private var gestureSession = MainPagerGestureSession()
    @State private var mainGestureState = MainPagerGestureState()
    @State private var suppressPageContentInteractions = false
    @State private var pageContentSuppressionID = UUID()
    @State private var isPhotoPreviewPresented = false
    @State private var calendarNotificationDestination: NotificationDestination?
    @GestureState private var isMainGestureActive = false

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let initialRoute: MainPagerRoute
        if arguments.contains("-ui-testing-past") {
            initialRoute = .pastAll
        } else if arguments.contains("-ui-testing-settings") {
            initialRoute = .futureSettings
        } else if arguments.contains("-ui-testing-future") {
            initialRoute = .futureCalendar
        } else {
            initialRoute = .now
        }
        _route = State(initialValue: initialRoute)
    }

    var body: some View {
        PhotoPreviewHost(
            canPresent: canPresentPhotoPreview,
            onPresentationChanged: updatePhotoPreviewPresentation
        ) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    MainPagerPage(
                        isActive: route.isPast,
                        isInteractionEnabled: pageContentInteractionEnabled,
                        usesDisabledState: false,
                        size: proxy.size
                    ) {
                        PastView(
                            filter: route.pastFilter ?? .all,
                            pageDragOffset: route.isPast ? innerPageDragOffset : 0,
                            isActive: route.isPast,
                            isInteractionEnabled: pageContentInteractionEnabled,
                            verticalScrollingDisabled: route.isPast && verticalScrollingDisabled,
                            selectFilter: selectPastFilter
                        )
                    }

                    MainPagerPage(
                        isActive: route == .now,
                        isInteractionEnabled: pageContentInteractionEnabled,
                        usesDisabledState: false,
                        size: proxy.size
                    ) {
                        NowView(
                            composePullProgress: route == .now
                                ? mainGestureState.composeProgress
                                : 0,
                            isActive: route == .now,
                            isInteractionEnabled: pageContentInteractionEnabled,
                            verticalScrollingDisabled: route == .now
                                && verticalScrollingDisabled,
                            showComposer: presentComposer,
                            showSettings: presentSettings,
                            setPhotoCarouselFrame: photoCarouselFrame.update
                        )
                    }

                    MainPagerPage(
                        isActive: route.isFuture,
                        isInteractionEnabled: pageContentInteractionEnabled,
                        usesDisabledState: false,
                        size: proxy.size
                    ) {
                        FutureView(
                            mode: route.futureMode ?? .calendar,
                            pageDragOffset: route.isFuture ? innerPageDragOffset : 0,
                            isActive: route.isFuture,
                            verticalScrollingDisabled: route.isFuture
                                && verticalScrollingDisabled,
                            pageInteractionDisabled: suppressPageContentInteractions,
                            notificationDestination: calendarNotificationDestination,
                            selectMode: selectFutureMode
                        )
                    }
                }
                .offset(
                    x: -CGFloat(route.sectionIndex) * proxy.size.width
                        + outerPageDragOffset
                )
                .animation(pageAnimation, value: route.sectionIndex)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    mainGesture(
                        in: proxy.size,
                        bottomSafeAreaInset: proxy.safeAreaInsets.bottom
                    ),
                    including: isPhotoPreviewPresented ? .none : .all
                )
                .onChange(of: isMainGestureActive) { wasActive, isActive in
                    guard wasActive, !isActive, gestureSession.isTracking else { return }
                    withAnimation(pageAnimation) {
                        resetMainGestureTracking()
                    }
                }
            }
            .clipped()
            .ignoresSafeArea(.container, edges: .bottom)
            .coordinateSpace(name: "mainPager")
            .background(Color(.systemBackground).ignoresSafeArea())
        }
        .task(id: route) {
            await loadActivePastNotes()
        }
        .task(id: notifications.pendingDestination?.id) {
            handleNotificationDestination()
        }
        .appHapticFeedback(.selection, trigger: route)
        .sheet(isPresented: $showingComposer, onDismiss: resetMainGestureTracking) {
            ComposeMemoryView()
        }
    }

    private var pageAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.32)
    }

    private var outerPageDragOffset: CGFloat {
        pageDragOffset(forSameSection: false)
    }

    private var innerPageDragOffset: CGFloat {
        pageDragOffset(forSameSection: true)
    }

    private var verticalScrollingDisabled: Bool {
        mainGestureState.blocksVerticalScrolling
            && !gestureSession.pageSwipeStartedInPhotoCarousel
    }

    private var pageContentInteractionEnabled: Bool {
        !suppressPageContentInteractions
    }

    private func pageDragOffset(forSameSection sameSection: Bool) -> CGFloat {
        guard mainGestureState.intent == .page else { return 0 }
        let sourceRoute = mainGestureState.pageSourceRoute ?? route
        guard !(
            sourceRoute == .now
                && gestureSession.pageSwipeStartedInPhotoCarousel
        ) else { return 0 }

        let translation = mainGestureState.pageTranslation
        guard translation != 0 else { return 0 }

        let direction = translation < 0 ? 1 : -1
        guard let destination = MainPagerRoute(rawValue: sourceRoute.rawValue + direction) else {
            return sameSection ? translation * 0.16 : 0
        }

        return (destination.sectionIndex == sourceRoute.sectionIndex) == sameSection
            ? translation
            : 0
    }

    private func mainGesture(
        in containerSize: CGSize,
        bottomSafeAreaInset: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("mainPager"))
            .updating($isMainGestureActive) { _, isActive, _ in
                if !isActive {
                    isActive = true
                }
            }
            .onChanged { value in
                trackMainGesture(
                    value,
                    containerSize: containerSize,
                    bottomSafeAreaInset: bottomSafeAreaInset
                )
            }
            .onEnded { value in
                finishMainGesture(
                    value,
                    containerSize: containerSize,
                    bottomSafeAreaInset: bottomSafeAreaInset
                )
            }
    }

    private func trackMainGesture(
        _ value: DragGesture.Value,
        containerSize: CGSize,
        bottomSafeAreaInset: CGFloat
    ) {
        if !gestureSession.isTracking {
            gestureSession.isTracking = true
            suppressPhotoPreviewAfterDrag()
            gestureSession.pageSwipeStartedInPhotoCarousel = route == .now
                && photoCarouselFrame.frame.contains(value.startLocation)
        }

        updateMainGestureState(
            translation: value.translation,
            startLocation: value.startLocation,
            containerSize: containerSize,
            bottomSafeAreaInset: bottomSafeAreaInset,
            route: route
        )

        presentComposerIfThresholdReached()
    }

    private func finishMainGesture(
        _ value: DragGesture.Value,
        containerSize: CGSize,
        bottomSafeAreaInset: CGFloat
    ) {
        suppressPhotoPreviewAfterDrag()
        updateMainGestureState(
            translation: value.translation,
            startLocation: value.startLocation,
            containerSize: containerSize,
            bottomSafeAreaInset: bottomSafeAreaInset,
            route: route
        )

        let intent = gestureSession.state.intent
        let didReachComposeThreshold = gestureSession.state.shouldPresentComposer

        if intent == .page {
            suppressComposerTapAfterPageSwipe()
            handlePageSwipe(value)
        } else {
            presentComposerIfThresholdReached()
        }

        if didReachComposeThreshold {
            resetMainGestureTracking()
        } else {
            withAnimation(pageAnimation) {
                resetMainGestureTracking()
            }
        }
    }

    private func updateMainGestureState(
        translation: CGSize,
        startLocation: CGPoint,
        containerSize: CGSize,
        bottomSafeAreaInset: CGFloat,
        route: MainPagerRoute
    ) {
        let previousIntent = gestureSession.state.intent
        var updatedState = gestureSession.state
        updatedState.update(
            translation: translation,
            startLocation: startLocation,
            containerSize: containerSize,
            bottomSafeAreaInset: bottomSafeAreaInset,
            route: route
        )
        guard updatedState != gestureSession.state else { return }

        gestureSession.state = updatedState
        if updatedState.intent == .page || updatedState.intent == .compose,
           updatedState != mainGestureState {
            mainGestureState = updatedState
        }
        if previousIntent != .page, updatedState.intent == .page {
            beginSuppressingPageContentInteractions()
        }
    }

    private func handlePageSwipe(_ value: DragGesture.Value) {
        guard gestureSession.state.shouldCommitPageSwipe(
            translation: value.translation,
            predictedEndTranslation: value.predictedEndTranslation
        ) else { return }

        if route == .now, gestureSession.pageSwipeStartedInPhotoCarousel {
            return
        }

        let horizontal = value.translation.width
        let projectedHorizontal = value.predictedEndTranslation.width
        let directionSource = abs(projectedHorizontal) > abs(horizontal)
            ? projectedHorizontal
            : horizontal
        let nextRawValue = route.rawValue + (directionSource < 0 ? 1 : -1)
        guard let nextRoute = MainPagerRoute(rawValue: nextRawValue) else { return }

        route = nextRoute
    }

    private func selectPastFilter(_ filter: PastFilter) {
        route = .past(filter)
    }

    private func selectFutureMode(_ mode: FutureMode) {
        route = .future(mode)
    }

    private func presentComposer() {
        guard !gestureSession.suppressComposerTapForCurrentEvent else {
            gestureSession.suppressComposerTapForCurrentEvent = false
            return
        }
        haptics.play(.tap)
        showingComposer = true
    }

    private func presentComposerIfThresholdReached() {
        guard route == .now,
              gestureSession.state.shouldPresentComposer,
              !gestureSession.composerPresentedForCurrentGesture else { return }

        gestureSession.composerPresentedForCurrentGesture = true
        haptics.play(.selection)
        showingComposer = true
    }

    private func suppressComposerTapAfterPageSwipe() {
        gestureSession.suppressComposerTapForCurrentEvent = true
        Task { @MainActor in
            await Task.yield()
            gestureSession.suppressComposerTapForCurrentEvent = false
        }
    }

    private func canPresentPhotoPreview() -> Bool {
        Date.now >= gestureSession.photoPreviewSuppressedUntil
    }

    private func updatePhotoPreviewPresentation(_ isPresented: Bool) {
        isPhotoPreviewPresented = isPresented
        if isPresented {
            resetMainGestureTracking()
        }
    }

    private func suppressPhotoPreviewAfterDrag() {
        gestureSession.photoPreviewSuppressedUntil = Date.now.addingTimeInterval(0.2)
    }

    private func resetMainGestureTracking() {
        gestureSession.reset()
        let resetState = MainPagerGestureState()
        if mainGestureState != resetState {
            mainGestureState = resetState
        }
        releasePageContentInteractionsAfterCurrentEvent()
    }

    private func beginSuppressingPageContentInteractions() {
        pageContentSuppressionID = UUID()
        suppressPageContentInteractions = true
    }

    private func releasePageContentInteractionsAfterCurrentEvent() {
        guard suppressPageContentInteractions else { return }
        let suppressionID = pageContentSuppressionID
        Task { @MainActor in
            await Task.yield()
            guard pageContentSuppressionID == suppressionID else { return }
            suppressPageContentInteractions = false
        }
    }

    private func presentSettings() {
        haptics.play(.tap)
        route = .futureSettings
    }

    private func loadActivePastNotes() async {
        guard let filter = route.pastFilter else { return }
        await store.selectNotes(filter.query)
    }

    private func handleNotificationDestination() {
        guard let destination = notifications.pendingDestination else { return }
        switch destination.route {
        case .main:
            route = .now
        case .past:
            route = .pastAll
        case .futureList:
            route = .futureList
        case .futureCalendar:
            route = .futureCalendar
            calendarNotificationDestination = destination
        }
        notifications.consumeDestination()
    }
}

@MainActor
private final class MainPagerGestureSession {
    var state = MainPagerGestureState()
    var isTracking = false
    var pageSwipeStartedInPhotoCarousel = false
    var composerPresentedForCurrentGesture = false
    var suppressComposerTapForCurrentEvent = false
    var photoPreviewSuppressedUntil = Date.distantPast

    func reset() {
        state.reset()
        isTracking = false
        pageSwipeStartedInPhotoCarousel = false
        composerPresentedForCurrentGesture = false
    }
}
