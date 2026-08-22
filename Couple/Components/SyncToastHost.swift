import SwiftUI
import Toasts

struct SyncToastHost: View {
    @Environment(AppStore.self) private var store
    @Environment(\.presentToast) private var presentToast

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: store.syncToastNotice) { _, notice in
                guard let notice else { return }
                presentToast(
                    ToastValue(
                        icon: icon(for: notice.kind),
                        message: notice.message,
                        duration: notice.kind == .success ? 2.5 : 4
                    )
                )
            }
    }

    private func icon(for kind: SyncToastNotice.Kind) -> some View {
        let systemName: String
        let color: Color
        switch kind {
        case .success:
            systemName = "checkmark.circle.fill"
            color = .green
        case .pending:
            systemName = "arrow.triangle.2.circlepath"
            color = AppTheme.accent
        case .error:
            systemName = "exclamationmark.triangle.fill"
            color = .red
        }
        return Image(systemName: systemName)
            .foregroundStyle(color)
    }
}
