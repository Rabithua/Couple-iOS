import SwiftUI

struct AuthView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    brand
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                    OnboardingHeroCarousel(isActive: scenePhase == .active)
                        .frame(height: min(470, max(320, proxy.size.height * 0.53)))
                        .padding(.top, 12)

                    Spacer(minLength: 16)

                    Button(action: beginRegistration) {
                        Text("开始吧！")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isBusy)
                    .accessibilityIdentifier("onboardingStartButton")

                    Button(action: beginSignIn) {
                        Text("已有账号？登录")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isBusy)
                    .accessibilityIdentifier("signInButton")
                    .padding(.bottom, 8)
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .overlay {
            if store.isBusy {
                Color.black.opacity(0.08).ignoresSafeArea()
                ProgressView().controlSize(.large)
            }
        }
        .screenBackground()
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text("our")
                    .foregroundStyle(AppTheme.accent)
                Text("since")
                    .foregroundStyle(.primary)
            }
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .fontWidth(.expanded)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("oursince")

            Text("属于我们的共同记录")
                .font(.system(.title3, design: .rounded, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private func beginRegistration() {
        haptics.play(.tap)
        Task {
            await store.register()
            if store.phase == .onboarding { haptics.play(.success) }
        }
    }

    private func beginSignIn() {
        haptics.play(.tap)
        Task {
            await store.signIn()
            if store.phase != .signedOut { haptics.play(.success) }
        }
    }
}
