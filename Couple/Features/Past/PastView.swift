import SwiftUI

enum PastFilter: String, CaseIterable, Hashable {
    case completed
    case anniversaries
    case photos
    case all

    var title: String {
        switch self {
        case .completed: String(localized: "共同完成")
        case .anniversaries: String(localized: "纪念日")
        case .photos: String(localized: "照片")
        case .all: String(localized: "全部")
        }
    }

    var query: NoteQuery {
        switch self {
        case .all: .all
        case .photos: .photos
        case .anniversaries: .anniversaries
        case .completed: .completedTodos
        }
    }

    var pageIndex: Int {
        switch self {
        case .completed: 0
        case .anniversaries: 1
        case .photos: 2
        case .all: 3
        }
    }

    var scrollIdentifier: String {
        switch self {
        case .completed: "pastCompletedScroll"
        case .anniversaries: "pastAnniversariesScroll"
        case .photos: "pastPhotosScroll"
        case .all: "pastAllScroll"
        }
    }
}

struct PastView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let filter: PastFilter
    let pageDragOffset: CGFloat
    let verticalScrollingDisabled: Bool
    let selectFilter: (PastFilter) -> Void

    var body: some View {
        DesignNavigationContainer {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    MainPagerPage(isActive: filter == .completed, size: proxy.size) {
                        PastPageView(
                            filter: .completed,
                            scrollingDisabled: verticalScrollingDisabled
                        )
                    }

                    MainPagerPage(isActive: filter == .anniversaries, size: proxy.size) {
                        PastPageView(
                            filter: .anniversaries,
                            scrollingDisabled: verticalScrollingDisabled
                        )
                    }

                    MainPagerPage(isActive: filter == .photos, size: proxy.size) {
                        PastPageView(
                            filter: .photos,
                            scrollingDisabled: verticalScrollingDisabled
                        )
                    }

                    MainPagerPage(isActive: filter == .all, size: proxy.size) {
                        PastPageView(
                            filter: .all,
                            scrollingDisabled: verticalScrollingDisabled
                        )
                    }
                }
                .offset(
                    x: -CGFloat(filter.pageIndex) * proxy.size.width
                        + pageDragOffset
                )
                .animation(pageAnimation, value: filter)
            }
            .clipped()
        } navigationBar: {
            DesignTabBar(
                items: PastFilter.allCases.map { ($0, $0.title) },
                selection: filter,
                select: selectFilter
            )
            .padding(.horizontal, AppTheme.horizontalPadding)
            .accessibilityIdentifier("pastNavigationBar")
        }
        .screenBackground()
    }

    private var pageAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.32)
    }
}
