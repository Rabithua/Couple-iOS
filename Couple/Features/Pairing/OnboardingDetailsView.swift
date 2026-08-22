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
    @State private var isBirthdayPickerPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(pageTitle)
                    .font(.system(.title, design: .rounded, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)

                if requiresProfile {
                    nameSection
                    birthdaySection
                }

                if action == .join {
                    inviteSection
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActions
        }
        .appHapticFeedback(.step, trigger: isValid) { oldValue, newValue in
            !oldValue && newValue
        }
    }

    private var pageTitle: LocalizedStringKey {
        requiresProfile ? "需要知道你的一些信息" : "填入你收到的邀请码"
    }

    private var nameSection: some View {
        onboardingSection(
            title: "你的名字",
            description: "这将是在你们共同的空间里面显示的名字\n可以是昵称或者是真实姓名\nwhatever，随你喜欢～"
        ) {
            fieldSurface {
                TextField("此处输入名字", text: $displayName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("onboardingDisplayNameField")
                    .onChange(of: displayName) { _, value in
                        if value.count > 100 {
                            displayName = String(value.prefix(100))
                        }
                    }
            }
        }
    }

    private var birthdaySection: some View {
        onboardingSection(
            title: "你的生日",
            description: "这一天你会收到一些小惊喜！"
        ) {
            Button {
                isBirthdayPickerPresented = true
            } label: {
                Text(verbatim: birthdayDisplayText)
                    .font(.system(.body, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isBirthdayPickerPresented) {
                DatePicker(
                    "选择你的生日",
                    selection: $birthday,
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.graphical)
                .padding()
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.height(400)])
                .accessibilityIdentifier("onboardingBirthdayEditor")
            }
            .accessibilityLabel("选择你的生日")
            .accessibilityValue(birthdayDisplayText)
            .accessibilityIdentifier("onboardingBirthdayPicker")
        }
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if requiresProfile {
                Text("— 以及 —")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)

                Text("填入你收到的邀请码")
                    .font(.system(.title, design: .rounded, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }

            fieldSurface {
                TextField("8 位邀请码", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
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

    private var bottomActions: some View {
        HStack(spacing: 10) {
            Button(action: goBack) {
                Text("上一步")
                    .font(.system(.title2, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minWidth: 96, minHeight: 50)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboardingBackButton")

            Button(action: submitForm) {
                Text("继续")
                    .font(.system(.title2, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(AppTheme.accent, in: .rect(cornerRadius: 10))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!isValid)
            .opacity(isValid ? 1 : 0.4)
            .accessibilityIdentifier("onboardingContinueButton")
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }

    private var cleanedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var birthdayDisplayText: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: birthday)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return ""
        }
        return "\(year)/\(month)/\(day)"
    }

    private var isValid: Bool {
        let profileValid = !requiresProfile || ((1...100).contains(cleanedName.count) && birthday <= .now)
        return profileValid && (action != .join || inviteCode.count == 8)
    }

    private func onboardingSection<Content: View>(
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .medium))
                Text(description)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
    }

    private func fieldSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 6))
    }

    private func submitForm() {
        guard isValid else { return }
        submit(cleanedName, birthday, action == .join ? inviteCode : nil)
    }
}
