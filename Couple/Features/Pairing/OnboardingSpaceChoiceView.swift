import SwiftUI

struct OnboardingSpaceChoiceView: View {
    let select: (OnboardingSpaceAction) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("加入空间还是创建空间？")
                        .font(.system(.title, design: .rounded, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 26) {
                        choiceButton(
                            title: "创建空间",
                            subtitle: "创建一个属于你们的空间",
                            action: .create,
                            height: cardHeight(for: proxy.size.height)
                        )
                        choiceButton(
                            title: "加入空间",
                            subtitle: "如果你已经有邀请码的话",
                            action: .join,
                            height: cardHeight(for: proxy.size.height)
                        )
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("onboardingSpaceChoice")
    }

    private func choiceButton(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        action: OnboardingSpaceAction,
        height: CGFloat
    ) -> some View {
        Button { select(action) } label: {
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text(subtitle)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(AppTheme.accent, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding\(action.rawValue.capitalized)SpaceButton")
    }

    private func cardHeight(for availableHeight: CGFloat) -> CGFloat {
        min(259, max(196, (availableHeight - 130) / 2))
    }
}
