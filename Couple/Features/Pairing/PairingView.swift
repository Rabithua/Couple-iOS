import SwiftUI

struct PairingView: View {
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    @State private var inviteCode = ""

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
                        .buttonStyle(.borderedProminent)
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
    }

    private func beginCreatingInvite() {
        haptics.play(.tap)
        Task {
            await store.createInvite()
            if store.relationship?.pendingInvite != nil {
                haptics.play(.success)
            }
        }
    }

    private func beginAcceptingInvite() {
        haptics.play(.tap)
        Task {
            await store.acceptInvite(inviteCode)
            if store.phase == .main {
                haptics.play(.success)
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
                .accessibilityLabel("邀请码 \(invite.code)")
            Text("有效期至 \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            ShareLink(item: "加入我的情侣共同空间，邀请码：\(invite.code)") {
                Label("分享邀请码", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
    }
}
