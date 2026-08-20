import Combine
import SwiftUI

struct OnboardingHeroCarousel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool

    @State private var automaticAngle = 0.0
    @State private var dragAngle = 0.0
    @State private var isDragging = false

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = min(238, proxy.size.width * 0.58)
            let cardHeight = min(432, proxy.size.height * 0.9)
            let radius = max(proxy.size.width * 2.35, 760)

            ZStack {
                ForEach(-4...4, id: \.self) { index in
                    let angle = relativeAngle(for: index)
                    let radians = angle * .pi / 180

                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppTheme.accent)
                        .frame(width: cardWidth, height: cardHeight)
                        .rotationEffect(.degrees(angle))
                        .offset(
                            x: sin(radians) * radius,
                            y: (1 - cos(radians)) * radius * 0.58
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(dragGesture(width: proxy.size.width))
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: min(150, proxy.size.height * 0.34))
                .allowsHitTesting(false)
            }
            .clipped()
        }
        .onReceive(timer) { _ in
            guard isActive, !reduceMotion, !isDragging else { return }
            automaticAngle = normalized(automaticAngle + 0.035)
        }
        .accessibilityHidden(true)
    }

    private func relativeAngle(for index: Int) -> Double {
        Double(index) * 15 + (reduceMotion ? 0 : automaticAngle + dragAngle)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                isDragging = true
                dragAngle = Double(value.translation.width / max(width, 1)) * 24
            }
            .onEnded { value in
                let projected = automaticAngle
                    + Double(value.predictedEndTranslation.width / max(width, 1)) * 24
                let snapped = (projected / 15).rounded() * 15
                withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.2)) {
                    automaticAngle = normalized(snapped)
                    dragAngle = 0
                }
                isDragging = false
            }
    }

    private func normalized(_ angle: Double) -> Double {
        let remainder = angle.truncatingRemainder(dividingBy: 15)
        return remainder > 7.5 ? remainder - 15 : remainder
    }
}
