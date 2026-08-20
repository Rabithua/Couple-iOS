import SwiftUI

struct OnboardingCardDeck: View {
    static let cardIndices = -4...4
    static let angleStep = 15.0
    static let maximumRotation = Double(cardIndices.upperBound) * angleStep

    let angle: Double
    let canvasSize: CGSize

    var body: some View {
        let cardWidth = min(237.25, canvasSize.width * 0.59)
        let cardHeight = min(431.36, cardWidth * 1.818)
        let radius = max(canvasSize.width * 2.4, 760)

        ZStack {
            ForEach(Self.cardIndices, id: \.self) { index in
                let cardAngle = Double(index) * Self.angleStep + angle
                let radians = cardAngle * .pi / 180
                let focusProgress = max(0, 1 - abs(cardAngle) / Self.angleStep)
                let cardScale = 0.76 + focusProgress * 0.24
                let cardOpacity = 0.72 + focusProgress * 0.28

                Rectangle()
                    .fill(AppTheme.accent)
                    .frame(width: cardWidth, height: cardHeight)
                    .mask {
                        RadialGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.68),
                                .init(color: .clear, location: 0.96)
                            ],
                            center: .top,
                            startRadius: 0,
                            endRadius: cardHeight / 0.96
                        )
                    }
                    .opacity(cardOpacity)
                    .scaleEffect(cardScale)
                    .rotationEffect(.degrees(cardAngle))
                    .offset(
                        x: sin(radians) * radius - 8,
                        y: (1 - cos(radians)) * radius + 28
                    )
                    .zIndex(focusProgress)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}
