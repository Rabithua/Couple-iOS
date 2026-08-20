import SwiftUI

struct HomeInviteRow: View {
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    @Environment(NotificationCoordinator.self) private var notifications

    var body: some View {
        Group {
            if let invite = store.relationship?.pendingInvite {
                ShareLink(item: AppLocalization.string(
                    "inviteShareMessage",
                    defaultValue: "加入我们的共同空间，邀请码：\(invite.code)"
                )) {
                    Label {
                        HStack(spacing: 8) {
                            Text("邀请码")
                            Text(invite.code)
                                .font(.system(.title2, design: .monospaced, weight: .semibold))
                        }
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.string(
                    "inviteCodeAccessibilityLabel",
                    defaultValue: "邀请码 \(invite.code)"
                ))
                .accessibilityHint("分享邀请码")
                .accessibilityIdentifier("homeInviteCode")
            } else {
                Button(action: createInvite) {
                    HStack(spacing: 8) {
                        Label {
                            Text("生成邀请码")
                        } icon: {
                            Image(systemName: "link.badge.plus")
                        }
                        if store.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(store.isBusy)
                .accessibilityIdentifier("homeCreateInvite")
            }
        }
        .font(AppTheme.titleFont())
        .foregroundStyle(AppTheme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.horizontalPadding)
    }

    private func createInvite() {
        haptics.play(.tap)
        Task {
            await store.createInvite()
            guard store.relationship?.pendingInvite != nil else { return }
            haptics.play(.success)
            await notifications.refreshRegistration()
        }
    }
}
