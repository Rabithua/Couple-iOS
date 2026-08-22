import SwiftUI
import Toasts

@main
struct CoupleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppStore()
    @State private var haptics = AppHaptics()
    @State private var language = AppLanguageStore()
    @State private var notifications = NotificationCoordinator.shared
    @State private var memoryLocation = MemoryLocationCoordinator()

    var body: some Scene {
        WindowGroup {
            ZStack {
                AppRootView()
                SyncToastHost()
            }
                .environment(store)
                .environment(language)
                .environment(notifications)
                .environment(memoryLocation)
                .environment(\.locale, language.selection.locale)
                .task { await startApplication() }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhase(newPhase)
                }
                .onChange(of: store.phase) { _, phase in
                    guard phase == .main || phase == .pairing else { return }
                    Task { await notifications.refreshRegistration() }
                }
                .onChange(of: language.selection) { _, _ in
                    Task { await notifications.refreshRegistration() }
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
                .installToast(position: .bottom)
                .appHapticsHost(haptics)
        }
    }

    private func startApplication() async {
        await notifications.configure(store: store, language: language)
        await store.start()
        await notifications.refreshRegistration()
        await store.updateForegroundActivity(isActive: scenePhase == .active)
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        Task {
            await store.updateForegroundActivity(isActive: phase == .active)
            guard phase == .active else { return }
            store.handleForeground()
            await notifications.refreshRegistration()
        }
    }
}
