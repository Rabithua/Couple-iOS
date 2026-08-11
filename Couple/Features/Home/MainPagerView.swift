import SwiftUI

@MainActor
struct MainPagerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    @State private var route: MainPagerRoute
    @State private var showingComposer = false
    @State private var showingSettings = false
    @State private var photoCarouselFrame = CGRect.zero
    @State private var pageSwipePresentationGate = PageSwipePresentationGate()

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
                        selectFilter: selectPastFilter
                    )
                }

                MainPagerPage(isActive: route == .now, size: proxy.size) {
                    NowView(
                        showComposer: presentComposer,
                        showSettings: presentSettings
                    )
                }

                MainPagerPage(isActive: route.isFuture, size: proxy.size) {
                    FutureView(
                        mode: route.futureMode ?? .calendar,
                        selectMode: selectFutureMode,
                        shouldSuppressPresentation: {
                            pageSwipePresentationGate.suppressesPresentation
                        }
                    )
                }
            }
            .offset(x: -CGFloat(route.sectionIndex) * proxy.size.width)
            .animation(pageAnimation, value: route.sectionIndex)
        }
        .clipped()
        .coordinateSpace(name: "mainPager")
        .contentShape(Rectangle())
        .simultaneousGesture(pageSwipeGesture)
        .onPreferenceChange(PhotoCarouselFramePreferenceKey.self) { frame in
            photoCarouselFrame = frame
        }
        .task(id: route) {
            await loadActivePastNotes()
        }
        .appHapticFeedback(.selection, trigger: route)
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showingComposer) {
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

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged(trackPageSwipe)
            .onEnded(finishPageSwipe)
    }

    private func trackPageSwipe(_ value: DragGesture.Value) {
        pageSwipePresentationGate.update(
            horizontal: value.translation.width,
            vertical: value.translation.height
        )
    }

    private func finishPageSwipe(_ value: DragGesture.Value) {
        pageSwipePresentationGate.finish()
        handlePageSwipe(value)
    }

    private func handlePageSwipe(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height
        let projectedHorizontal = value.predictedEndTranslation.width

        guard abs(horizontal) > abs(vertical) * 1.2 else { return }
        guard abs(horizontal) >= 36 || abs(projectedHorizontal) >= 80 else { return }

        if route == .now, photoCarouselFrame.contains(value.startLocation) {
            return
        }

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
        haptics.play(.tap)
        showingComposer = true
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
