import SwiftUI

@main
struct CoupleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppStore()
    @State private var haptics = AppHaptics()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(store)
                .task { await store.start() }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active { store.handleForeground() }
                }
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
                .appHapticsHost(haptics)
        }
    }
}
