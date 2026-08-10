import SwiftUI

@main
struct CoupleApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(store)
                .task { await store.start() }
                .alert(
                    "提示",
                    isPresented: Binding(
                        get: { store.errorMessage != nil },
                        set: { if !$0 { store.errorMessage = nil } }
                    )
                ) {
                    Button("好", role: .cancel) { store.errorMessage = nil }
                } message: {
                    Text(store.errorMessage ?? "")
                }
        }
    }
}

