import SwiftUI

@MainActor
struct MainPagerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    @State private var route: MainPagerRoute
    @State private var showingComposer = false
    @State private var showingSettings = false
    @State private var photoCarouselFrame = CGRect.null
    @State private var pageSwipeStartedInPhotoCarousel = false
    @State private var isTrackingMainGesture = false
    @State private var mainGestureState = MainPagerGestureState()
    @State private var composerPresentedForCurrentGesture = false
    @State private var suppressComposerTapForCurrentEvent = false

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let initialRoute: MainPagerRoute
        if arguments.contains("-ui-testing-past") {
            initialRoute = .pastAll
        } else if arguments.contains("-ui-testing-future") {
            initialRoute = .futureCalendar
        } else {
            initialRoute = .now
        }
        _route = State(initialValue: initialRoute)
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                MainPagerPage(isActive: route.isPast, size: proxy.size) {
                    PastView(
                        filter: route.pastFilter ?? .all,
                        pageDragOffset: innerPageDragOffset,
                        selectFilter: selectPastFilter
                    )
                }

                MainPagerPage(isActive: route == .now, size: proxy.size) {
                    NowView(
                        composePullProgress: mainGestureState.composeProgress,
                        isActive: route == .now,
                        showComposer: presentComposer,
                        showSettings: presentSettings,
                        setPhotoCarouselFrame: { frame in
                            photoCarouselFrame = frame
                        }
                    )
                }

                MainPagerPage(isActive: route.isFuture, size: proxy.size) {
                    FutureView(
                        mode: route.futureMode ?? .calendar,
                        pageDragOffset: innerPageDragOffset,
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
                )
            )
        }
        .clipped()
        .ignoresSafeArea(.container, edges: .bottom)
        .coordinateSpace(name: "mainPager")
        .task(id: route) {
            await loadActivePastNotes()
        }
        .appHapticFeedback(.selection, trigger: route)
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showingComposer, onDismiss: resetMainGestureTracking) {
            ComposeMemoryView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(startedOn: relationshipStartedOn)
        }
    }

    private var pageAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.32)
    }

    private var relationshipStartedOn: Date {
        guard let rawDate = store.relationship?.couple?.startedOn else { return .now }
        return Date.fromDateOnly(rawDate) ?? .now
    }

    private var outerPageDragOffset: CGFloat {
        pageDragOffset(forSameSection: false)
    }

    private var innerPageDragOffset: CGFloat {
        pageDragOffset(forSameSection: true)
    }

    private func pageDragOffset(forSameSection sameSection: Bool) -> CGFloat {
        guard mainGestureState.intent == .page else { return 0 }
        let sourceRoute = mainGestureState.pageSourceRoute ?? route
        guard !(sourceRoute == .now && pageSwipeStartedInPhotoCarousel) else { return 0 }

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
        if !isTrackingMainGesture {
            isTrackingMainGesture = true
            pageSwipeStartedInPhotoCarousel = route == .now
                && photoCarouselFrame.contains(value.startLocation)
        }

        mainGestureState.update(
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
        mainGestureState.update(
            translation: value.translation,
            startLocation: value.startLocation,
            containerSize: containerSize,
            bottomSafeAreaInset: bottomSafeAreaInset,
            route: route
        )

        let intent = mainGestureState.intent
        let didReachComposeThreshold = mainGestureState.shouldPresentComposer

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

    private func handlePageSwipe(_ value: DragGesture.Value) {
        guard mainGestureState.shouldCommitPageSwipe(
            translation: value.translation,
            predictedEndTranslation: value.predictedEndTranslation
        ) else { return }

        if route == .now, pageSwipeStartedInPhotoCarousel {
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
        guard !suppressComposerTapForCurrentEvent else {
            suppressComposerTapForCurrentEvent = false
            return
        }
        haptics.play(.tap)
        showingComposer = true
    }

    private func presentComposerIfThresholdReached() {
        guard route == .now,
              mainGestureState.shouldPresentComposer,
              !composerPresentedForCurrentGesture else { return }

        composerPresentedForCurrentGesture = true
        haptics.play(.selection)
        showingComposer = true
    }

    private func suppressComposerTapAfterPageSwipe() {
        suppressComposerTapForCurrentEvent = true
        DispatchQueue.main.async {
            suppressComposerTapForCurrentEvent = false
        }
    }

    private func resetMainGestureTracking() {
        mainGestureState.reset()
        composerPresentedForCurrentGesture = false
        isTrackingMainGesture = false
        pageSwipeStartedInPhotoCarousel = false
    }

    private func presentSettings() {
        haptics.play(.tap)
        showingSettings = true
    }

    private func loadActivePastNotes() async {
        guard let filter = route.pastFilter else { return }
        await store.selectNotes(filter.query)
    }
}
