import SwiftUI

struct PairingView: View {
    @Environment(\.locale) private var locale
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    @Environment(NotificationCoordinator.self) private var notifications
    @State private var inviteCode = ""
    @State private var showingNotificationExplanation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("邀请你的另一半")
                            .font(.largeTitle.bold())
                        Text("共同空间最多两个人。邀请码 7 天内有效。")
                            .foregroundStyle(.secondary)
                    }

                    if let invite = store.relationship?.pendingInvite {
                        inviteCard(invite)
                    } else {
                        Button(action: beginCreatingInvite) {
                            Label("生成邀请码", systemImage: "link.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .appProminentButtonStyle()
                        .controlSize(.large)
                    }

                    HStack {
                        Rectangle().fill(Color(.separator)).frame(height: 1)
                        Text("或加入对方的空间").font(.caption).foregroundStyle(.secondary)
                        Rectangle().fill(Color(.separator)).frame(height: 1)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        TextField("8 位邀请码", text: $inviteCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(.title2, design: .monospaced, weight: .semibold))
                            .padding()
                            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))

                        Button(action: beginAcceptingInvite) {
                            Text("加入共同空间").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                    }

                    Button("暂时先进入", action: beginContinuingWithoutPartner)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .overlay { if store.isBusy { ProgressView().controlSize(.large) } }
        }
        .screenBackground()
        .alert("及时知道配对结果", isPresented: $showingNotificationExplanation) {
            Button("开启通知", action: requestNotificationPermission)
            Button("以后再说", role: .cancel) {}
        } message: {
            Text("允许通知后，对方加入共同空间时会立即告诉你。")
        }
    }

    private func beginCreatingInvite() {
        haptics.play(.tap)
        Task {
            await store.createInvite()
            if store.relationship?.pendingInvite != nil {
                haptics.play(.success)
                if notifications.authorizationStatus == .notDetermined {
                    showingNotificationExplanation = true
                } else {
                    await notifications.refreshRegistration()
                }
            }
        }
    }

    private func beginAcceptingInvite() {
        haptics.play(.tap)
        Task {
            await store.acceptInvite(inviteCode)
            if store.phase == .main {
                haptics.play(.success)
                _ = await notifications.requestAuthorizationIfNeeded()
            }
        }
    }

    private func beginContinuingWithoutPartner() {
        haptics.play(.tap)
        Task {
            await store.continueWithoutPartner()
            if store.phase == .main {
                haptics.play(.success)
            }
        }
    }

    private func inviteCard(_ invite: CoupleInvite) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(invite.code)
                .font(.largeTitle.monospaced().bold())
                .textSelection(.enabled)
                .accessibilityLabel(AppLocalization.string("inviteCodeAccessibilityLabel",
                    defaultValue: "邀请码 \(invite.code)"
                ))
            Text(
                "有效期至 \(invite.expiresAt.localizedDateTime(locale: locale, dateStyle: .abbreviated))"
            )
                .font(.caption)
                .foregroundStyle(.secondary)
            ShareLink(item: AppLocalization.string("inviteShareMessage",
                defaultValue: "加入我们的共同空间，邀请码：\(invite.code)"
            )) {
                Label("分享邀请码", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)

            if notifications.authorizationStatus == .notDetermined {
                Button("开启配对通知", systemImage: "bell.badge", action: explainNotifications)
                    .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
    }

    private func explainNotifications() {
        haptics.play(.tap)
        showingNotificationExplanation = true
    }

    private func requestNotificationPermission() {
        haptics.play(.tap)
        Task { _ = await notifications.requestAuthorizationIfNeeded() }
    }
}
