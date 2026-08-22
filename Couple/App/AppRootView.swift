import SwiftUI

struct AppRootView: View {
    @Environment(AppLanguageStore.self) private var language
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            switch store.phase {
            case .launching:
                launchView
            case .signedOut:
                AuthView()
            case .onboarding:
                OnboardingFlowView()
            case .pairing:
                OnboardingFlowView()
            case .main:
                MainPagerView()
            }
        }
        .id(language.selection)
        .animation(.smooth(duration: 0.35), value: store.phase)
    }

    private var launchView: some View {
        VStack(spacing: 12) {
            Image("LoadingLogo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 112)
                .accessibilityHidden(true)
            ProgressView()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .accessibilityLabel("正在载入")
    }
}
