import SwiftUI

struct AppRootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            switch store.phase {
            case .launching:
                launchView
            case .signedOut:
                AuthView()
            case .pairing:
                PairingView()
            case .main:
                MainPagerView()
            }
        }
        .animation(.smooth(duration: 0.35), value: store.phase)
        .preferredColorScheme(.light)
    }

    private var launchView: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 30, weight: .semibold))
                .symbolEffect(.pulse)
            ProgressView()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .accessibilityLabel("正在载入")
    }
}

