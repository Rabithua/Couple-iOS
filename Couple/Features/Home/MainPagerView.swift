import SwiftUI

enum MainPage: Int, Hashable {
    case past = -1
    case now = 0
    case future = 1
}

struct MainPagerView: View {
    @State private var page: MainPage
    @State private var showingComposer = false
    @State private var showingSettings = false

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let initialPage: MainPage
        if arguments.contains("-ui-testing-past") {
            initialPage = .past
        } else if arguments.contains("-ui-testing-future") {
            initialPage = .future
        } else {
            initialPage = .now
        }
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        TabView(selection: $page) {
            PastView()
                .tag(MainPage.past)

            NowView(
                showComposer: { showingComposer = true },
                showSettings: { showingSettings = true }
            )
            .tag(MainPage.now)

            FutureView()
                .tag(MainPage.future)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .background(Color(.systemBackground).ignoresSafeArea())
        .statusBarHidden(true)
        .sheet(isPresented: $showingComposer) {
            ComposeMemoryView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}
