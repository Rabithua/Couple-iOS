import SwiftUI

struct OnboardingSpaceChoiceView: View {
    let select: (OnboardingSpaceAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("我们的空间")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("创建一个新的共同空间，或使用邀请码加入对方。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    choiceButton(
                        title: "创建空间",
                        subtitle: "生成邀请码，邀请你的另一半",
                        systemImage: "plus",
                        action: .create
                    )
                    choiceButton(
                        title: "加入空间",
                        subtitle: "输入对方分享的 8 位邀请码",
                        systemImage: "link",
                        action: .join
                    )
                }

                Text("共同空间最多两个人；邀请码有效期为 7 天。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("onboardingSpaceChoice")
    }

    private func choiceButton(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String,
        action: OnboardingSpaceAction
    ) -> some View {
        Button { select(action) } label: {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2.bold())
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .opacity(0.82)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(AppTheme.accent, in: .rect(cornerRadius: 20))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding\(action.rawValue.capitalized)SpaceButton")
    }
}
