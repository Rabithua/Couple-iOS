import SwiftUI

struct ComposePullPrompt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let shimmerTravelDuration: TimeInterval = 2.2
    private static let shimmerCycleDuration: TimeInterval = 2.8
    let progress: CGFloat
    let isActive: Bool
    let action: () -> Void

    private var shouldAnimate: Bool {
        isActive && !reduceMotion
    }

    var body: some View {
        Button(action: action) {
            Text("上拉记录此刻")
                .font(.body)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(AppTheme.muted)
                .overlay {
                    if shouldAnimate {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                            GeometryReader { proxy in
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        Color.primary.opacity(0.7),
                                        .clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: proxy.size.width * 0.55)
                                .offset(x: shimmerOffset(at: context.date) * proxy.size.width)
                            }
                        }
                        .mask {
                            Text("上拉记录此刻")
                                .font(.body)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 44)
                .padding(.horizontal, AppTheme.horizontalPadding)
                .contentShape(Rectangle())
                .offset(y: reduceMotion ? 0 : -progress * 10)
                .opacity(0.65 + progress * 0.35)
        }
        .buttonStyle(.plain)
        .padding(.bottom, AppTheme.composePromptBottomPadding)
        .accessibilityLabel("记录此刻")
        .accessibilityHint("轻点或从页面底部上拉")
        .accessibilityIdentifier("composeMemoryButton")
    }

    private func shimmerOffset(at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: Self.shimmerCycleDuration)
        let progress = min(elapsed / Self.shimmerTravelDuration, 1)
        return -1 + CGFloat(progress * 2)
    }
}
