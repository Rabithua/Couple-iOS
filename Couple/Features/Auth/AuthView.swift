import SwiftUI

struct AuthView: View {
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    @State private var displayName = ""
    @State private var showingRegistration = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.largeTitle.bold())
                    Text("oursince")
                        .font(.largeTitle.bold())
                    Text("只属于两个人的共同记录。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button(action: beginSignIn) {
                        Label("使用 Passkey 登录", systemImage: "person.badge.key.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .appProminentButtonStyle()
                    .controlSize(.large)
                    .disabled(store.isBusy)
                    .accessibilityIdentifier("signInButton")

                    Button("第一次使用？创建空间", action: presentRegistration)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(store.isBusy)

                    Button("预览设计与交互", action: enterPreview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .accessibilityIdentifier("previewButton")
                }

                Text("Passkey 由系统和 iCloud 钥匙串保护；服务端不保存密码。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(28)
            .overlay {
                if store.isBusy {
                    Color.black.opacity(0.08).ignoresSafeArea()
                    ProgressView().controlSize(.large)
                }
            }
            .sheet(isPresented: $showingRegistration) {
                registrationSheet
            }
        }
        .screenBackground()
    }

    private var registrationSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如：程袭", text: $displayName)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("你的名字")
                } footer: {
                    Text("对方会在共同空间里看到这个名字。")
                }
            }
            .navigationTitle("创建空间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", action: dismissRegistration)
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建", systemImage: "checkmark", action: beginRegistration)
                        .labelStyle(.iconOnly)
                        .appProminentButtonStyle()
                        .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isBusy)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func beginSignIn() {
        haptics.play(.tap)
        Task {
            await store.signIn()
            if store.phase != .signedOut {
                haptics.play(.success)
            }
        }
    }

    private func presentRegistration() {
        haptics.play(.tap)
        showingRegistration = true
    }

    private func dismissRegistration() {
        haptics.play(.tap)
        showingRegistration = false
    }

    private func beginRegistration() {
        haptics.play(.tap)
        Task {
            await store.register(
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if store.phase != .signedOut {
                haptics.play(.success)
                showingRegistration = false
            }
        }
    }

    private func enterPreview() {
        haptics.play(.tap)
        store.enterPreview()
    }
}
