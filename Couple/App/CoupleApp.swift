import SwiftUI

@main
struct CoupleApp: App {
    @State private var store = AppStore()
    @State private var haptics = AppHaptics()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(store)
                .appHapticsHost(haptics)
                .task { await store.start() }
                .appHapticFeedback(
                    .error,
                    trigger: store.errorMessage,
                    condition: AppHaptics.whenPresent
                )
                .alert(
                    "提示",
                    isPresented: Binding(
                        get: { store.errorMessage != nil },
                        set: { if !$0 { store.errorMessage = nil } }
                    )
                ) {
                    Button("好", role: .cancel) {
                        haptics.play(.tap)
                        store.errorMessage = nil
                    }
                } message: {
                    Text(store.errorMessage ?? "")
                }
        }
    }
}
