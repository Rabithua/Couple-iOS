import SwiftUI

struct AppRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        VStack {
            Image("LoadingLogo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 112)
                .accessibilityHidden(true)
                .phaseAnimator([false, true]) { logo, isDimmed in
                    logo
                        .opacity(isDimmed ? 0.68 : 1)
                        .scaleEffect(isDimmed && !reduceMotion ? 0.98 : 1)
                } animation: { _ in
                    .easeInOut(duration: 0.9)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .accessibilityLabel("正在载入")
    }
}
