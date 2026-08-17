import SwiftUI

struct AppHapticFeedbackModifier<Trigger: Equatable>: ViewModifier {
    @Environment(AppHaptics.self) private var haptics

    let feedback: AppHaptics.Feedback
    let trigger: Trigger
    let condition: ((Trigger, Trigger) -> Bool)?

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { oldValue, newValue in
            guard haptics.isEnabled,
                  condition?(oldValue, newValue) ?? true else { return nil }
            return feedback.sensoryFeedback
        }
    }
}
