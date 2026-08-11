import SwiftUI

struct DesignNavigationContainer<Content: View, NavigationBar: View>: View {
    private let content: Content
    private let navigationBar: NavigationBar

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder navigationBar: () -> NavigationBar
    ) {
        self.content = content()
        self.navigationBar = navigationBar()
    }

    var body: some View {
        content
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    DesignTopEdgeBackground(length: AppTheme.navigationFadeLength)

                    navigationBar
                        .padding(.top, AppTheme.tabBarTopPadding)
                        .padding(.bottom, AppTheme.tabBarBottomPadding)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: AppTheme.navigationFadeLength,
                    alignment: .top
                )
            }
    }
}
