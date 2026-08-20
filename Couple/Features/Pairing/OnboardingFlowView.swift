import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppHaptics.self) private var haptics
    @Environment(AppStore.self) private var store
    @State private var selectedAction: OnboardingSpaceAction?

    var body: some View {
        NavigationStack {
            Group {
                if let selectedAction {
                    OnboardingDetailsView(
                        action: selectedAction,
                        requiresProfile: store.requiresOnboardingProfile,
                        goBack: goBack,
                        submit: submit
                    )
                } else {
                    OnboardingSpaceChoiceView(select: select)
                }
            }
            .animation(.smooth(duration: 0.3), value: selectedAction)
            .overlay {
                if store.isBusy {
                    Color.black.opacity(0.06).ignoresSafeArea()
                    ProgressView().controlSize(.large)
                }
            }
        }
        .screenBackground()
    }

    private func select(_ action: OnboardingSpaceAction) {
        haptics.play(.tap)
        if !store.requiresOnboardingProfile, action == .create {
            Task { await createSpaceForExistingAccount() }
        } else {
            selectedAction = action
        }
    }

    private func goBack() {
        haptics.play(.tap)
        selectedAction = nil
    }

    private func submit(
        displayName: String,
        birthday: Date,
        inviteCode: String?
    ) {
        guard let selectedAction else { return }
        haptics.play(.tap)
        Task {
            if store.requiresOnboardingProfile {
                await store.completeOnboarding(
                    displayName: displayName,
                    birthday: birthday,
                    action: selectedAction,
                    inviteCode: inviteCode
                )
            } else if selectedAction == .join, let inviteCode {
                await store.acceptInvite(inviteCode)
            }
            if store.phase == .main { haptics.play(.success) }
        }
    }

    private func createSpaceForExistingAccount() async {
        await store.createInvite()
        guard store.relationship?.pendingInvite != nil else { return }
        await store.continueWithoutPartner()
        if store.phase == .main { haptics.play(.success) }
    }
}
