import SwiftUI

struct OnboardingDetailsView: View {
    let action: OnboardingSpaceAction
    let requiresProfile: Bool
    let goBack: () -> Void
    let submit: (String, Date, String?) -> Void

    @State private var displayName = ""
    @State private var birthday = Calendar.current.date(
        byAdding: .year,
        value: -18,
        to: .now
    ) ?? .now
    @State private var inviteCode = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(action == .create ? "创建空间" : "加入空间")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(instruction)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    if requiresProfile {
                        field(title: "你的名字") {
                            TextField("1–100 个字符", text: $displayName)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("onboardingDisplayNameField")
                        }

                        field(title: "生日") {
                            DatePicker(
                                "生日",
                                selection: $birthday,
                                in: ...Date.now,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .accessibilityIdentifier("onboardingBirthdayPicker")
                        }
                    }

                    if action == .join {
                        field(title: "邀请码") {
                            TextField("8 位邀请码", text: $inviteCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.system(.title3, design: .monospaced, weight: .semibold))
                                .onChange(of: inviteCode) { _, value in
                                    inviteCode = String(
                                        value.uppercased()
                                            .filter { $0.isLetter || $0.isNumber }
                                            .prefix(8)
                                    )
                                }
                                .accessibilityIdentifier("onboardingInviteCodeField")
                        }
                    }
                }

                VStack(spacing: 10) {
                    Button(action: submitForm) {
                        Text(action == .create ? "创建共同空间" : "加入共同空间")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(AppTheme.accent, in: .rect(cornerRadius: 16))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid)
                    .opacity(isValid ? 1 : 0.4)
                    .accessibilityIdentifier("onboardingContinueButton")

                    Button(action: goBack) {
                        Text("上一步")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboardingBackButton")
                }
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("onboardingDetails")
    }

    private var instruction: LocalizedStringKey {
        if !requiresProfile { return "输入对方分享的邀请码，就可以进入共同空间。" }
        return action == .create
            ? "先告诉我们你的名字和生日，完成后会生成邀请码。"
            : "填写资料和对方的邀请码，一次完成加入。"
    }

    private var cleanedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        let profileValid = !requiresProfile || ((1...100).contains(cleanedName.count) && birthday <= .now)
        return profileValid && (action != .join || inviteCode.count == 8)
    }

    private func field<Content: View>(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
        }
    }

    private func submitForm() {
        guard isValid else { return }
        submit(cleanedName, birthday, action == .join ? inviteCode : nil)
    }
}
