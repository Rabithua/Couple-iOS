import Combine
import SwiftUI

struct OnboardingHeroCarousel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppHaptics.self) private var haptics
    let isActive: Bool

    @State private var automaticAngle = 0.0
    @State private var automaticDirection = 1.0
    @State private var dragAngle = 0.0
    @State private var isDragging = false
    @State private var isOverscrolling = false

    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let angle = automaticAngle + dragAngle

            OnboardingCardDeck(angle: angle, canvasSize: proxy.size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .simultaneousGesture(dragGesture(width: proxy.size.width))
                .appHapticFeedback(.step, trigger: stage(for: angle))
                .clipped()
        }
        .onReceive(timer) { _ in
            guard isActive, !reduceMotion, !isDragging else { return }
            advanceAutomaticRotation()
        }
        .accessibilityHidden(true)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                isDragging = true
                let translation = Double(value.translation.width / max(width, 1)) * 24
                let proposedAngle = automaticAngle + translation
                let overscrolling = abs(proposedAngle) > OnboardingCardDeck.maximumRotation
                if overscrolling, !isOverscrolling {
                    haptics.play(.boundary)
                }
                isOverscrolling = overscrolling

                let visualAngle = rubberBanded(proposedAngle)
                dragAngle = visualAngle - automaticAngle
            }
            .onEnded { value in
                guard isDragging else { return }
                let width = max(width, 1)
                let translation = Double(value.translation.width / width) * 24
                let projectedTranslation = Double(value.predictedEndTranslation.width / width) * 24
                let inertia = (projectedTranslation - translation) * 0.35
                let destination = snapped(automaticAngle + translation + inertia)

                updateAutomaticDirection(for: destination)
                isOverscrolling = false

                guard !reduceMotion else {
                    automaticAngle = destination
                    dragAngle = 0
                    isDragging = false
                    return
                }

                withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
                    automaticAngle = destination
                    dragAngle = 0
                } completion: {
                    isDragging = false
                }
            }
    }

    private func advanceAutomaticRotation() {
        let destination = automaticAngle + automaticDirection * OnboardingCardDeck.angleStep
        let boundedDestination: Double

        if destination >= OnboardingCardDeck.maximumRotation {
            boundedDestination = OnboardingCardDeck.maximumRotation
            automaticDirection = -1
        } else if destination <= -OnboardingCardDeck.maximumRotation {
            boundedDestination = -OnboardingCardDeck.maximumRotation
            automaticDirection = 1
        } else {
            boundedDestination = destination
        }

        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            automaticAngle = boundedDestination
        }
    }

    private func clamped(_ angle: Double) -> Double {
        min(max(angle, -OnboardingCardDeck.maximumRotation), OnboardingCardDeck.maximumRotation)
    }

    private func rubberBanded(_ angle: Double) -> Double {
        let limit = OnboardingCardDeck.maximumRotation
        guard abs(angle) > limit else { return angle }

        let overflow = abs(angle) - limit
        let maximumOverflow = OnboardingCardDeck.angleStep / 2
        let resistedOverflow = (1 - 1 / (overflow * 0.55 / maximumOverflow + 1)) * maximumOverflow
        let direction = angle < 0 ? -1.0 : 1.0
        return direction * (limit + resistedOverflow)
    }

    private func snapped(_ angle: Double) -> Double {
        let boundedAngle = clamped(angle)
        let stage = (boundedAngle / OnboardingCardDeck.angleStep).rounded()
        return clamped(stage * OnboardingCardDeck.angleStep)
    }

    private func stage(for angle: Double) -> Int {
        Int((clamped(angle) / OnboardingCardDeck.angleStep).rounded())
    }

    private func updateAutomaticDirection(for angle: Double) {
        if angle >= OnboardingCardDeck.maximumRotation {
            automaticDirection = -1
        } else if angle <= -OnboardingCardDeck.maximumRotation {
            automaticDirection = 1
        }
    }
}
