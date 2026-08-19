import SwiftUI
import XCTest
@testable import Couple

@MainActor
final class AppHapticsTests: XCTestCase {
    func testRepeatedFeedbackProducesDistinctEvents() throws {
        let haptics = AppHaptics(userDefaults: makeUserDefaults())

        haptics.play(.selection)
        let firstEvent = try XCTUnwrap(haptics.event)
        haptics.play(.selection)
        let secondEvent = try XCTUnwrap(haptics.event)

        XCTAssertEqual(firstEvent.feedback, .selection)
        XCTAssertEqual(secondEvent.feedback, .selection)
        XCTAssertEqual(secondEvent.sequence, firstEvent.sequence + 1)
        XCTAssertNotEqual(firstEvent, secondEvent)
    }

    func testSemanticFeedbackMapsToNativeSensoryFeedback() {
        XCTAssertEqual(
            AppHaptics.Feedback.tap.sensoryFeedback,
            .impact(flexibility: .soft, intensity: 0.4)
        )
        XCTAssertEqual(AppHaptics.Feedback.selection.sensoryFeedback, .selection)
        XCTAssertEqual(AppHaptics.Feedback.success.sensoryFeedback, .success)
        XCTAssertEqual(AppHaptics.Feedback.warning.sensoryFeedback, .warning)
        XCTAssertEqual(AppHaptics.Feedback.error.sensoryFeedback, .error)
    }

    func testPresentConditionOnlyAllowsNonNilValues() {
        XCTAssertFalse(AppHaptics.whenPresent(Optional<String>.none, nil))
        XCTAssertTrue(AppHaptics.whenPresent(nil, "first error"))
        XCTAssertTrue(AppHaptics.whenPresent("first error", "second error"))
        XCTAssertFalse(AppHaptics.whenPresent("first error", nil))
    }

    func testPresentValueChangeRequiresTwoDifferentValues() {
        XCTAssertFalse(
            AppHaptics.changedBetweenPresentValues(Optional<String>.none, nil)
        )
        XCTAssertFalse(AppHaptics.changedBetweenPresentValues(nil, "August"))
        XCTAssertFalse(AppHaptics.changedBetweenPresentValues("August", nil))
        XCTAssertFalse(AppHaptics.changedBetweenPresentValues("August", "August"))
        XCTAssertTrue(AppHaptics.changedBetweenPresentValues("August", "September"))
    }

    func testDisabledHapticsSuppressEventsAndPersistPreference() {
        let userDefaults = makeUserDefaults()
        let haptics = AppHaptics(userDefaults: userDefaults)

        XCTAssertTrue(haptics.isEnabled)
        haptics.isEnabled = false
        haptics.play(.warning)

        XCTAssertNil(haptics.event)
        XCTAssertFalse(AppHaptics(userDefaults: userDefaults).isEnabled)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "AppHapticsTests-\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults")
        }
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
