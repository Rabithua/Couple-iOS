import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppHaptics {
    private static let enabledDefaultsKey = "app.haptics.enabled"

    enum Feedback: Equatable {
        case tap
        case selection
        case press
        case step
        case boundary
        case success
        case warning
        case error

        var sensoryFeedback: SensoryFeedback {
            switch self {
            case .tap:
                .impact(flexibility: .soft, intensity: 0.4)
            case .selection:
                .selection
            case .press:
                .impact(flexibility: .soft, intensity: 0.75)
            case .step:
                .impact(flexibility: .rigid, intensity: 0.9)
            case .boundary:
                .impact(weight: .heavy, intensity: 0.8)
            case .success:
                .success
            case .warning:
                .warning
            case .error:
                .error
            }
        }
    }

    struct Event: Equatable {
        let sequence: UInt64
        let feedback: Feedback
    }

    private(set) var event: Event?
    private var nextSequence: UInt64 = 0
    private let userDefaults: UserDefaults
    var isEnabled: Bool {
        didSet {
            userDefaults.set(isEnabled, forKey: Self.enabledDefaultsKey)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: Self.enabledDefaultsKey) == nil {
            isEnabled = true
        } else {
            isEnabled = userDefaults.bool(forKey: Self.enabledDefaultsKey)
        }
    }

    func play(_ feedback: Feedback) {
        guard isEnabled else { return }
        nextSequence &+= 1
        event = Event(sequence: nextSequence, feedback: feedback)
    }

    func playTodoCompletionChange(isCompleted: Bool) {
        play(isCompleted ? .selection : .success)
    }

    nonisolated static func whenPresent<Value>(_: Value?, _ newValue: Value?) -> Bool {
        newValue != nil
    }

    nonisolated static func changedBetweenPresentValues<Value: Equatable>(
        _ oldValue: Value?,
        _ newValue: Value?
    ) -> Bool {
        guard let oldValue, let newValue else { return false }
        return oldValue != newValue
    }
}

extension View {
    @MainActor
    func appHapticsHost(_ haptics: AppHaptics) -> some View {
        environment(haptics)
            .sensoryFeedback(trigger: haptics.event) { _, newEvent in
                guard haptics.isEnabled else { return nil }
                return newEvent?.feedback.sensoryFeedback
            }
    }

    func appHapticFeedback<Trigger: Equatable>(
        _ feedback: AppHaptics.Feedback,
        trigger: Trigger
    ) -> some View {
        modifier(
            AppHapticFeedbackModifier(
                feedback: feedback,
                trigger: trigger,
                condition: nil
            )
        )
    }

    func appHapticFeedback<Trigger: Equatable>(
        _ feedback: AppHaptics.Feedback,
        trigger: Trigger,
        condition: @escaping (Trigger, Trigger) -> Bool
    ) -> some View {
        modifier(
            AppHapticFeedbackModifier(
                feedback: feedback,
                trigger: trigger,
                condition: condition
            )
        )
    }
}
