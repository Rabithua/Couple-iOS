import Foundation
import Observation

@MainActor
@Observable
final class AppLanguageStore {
    @ObservationIgnored private let userDefaults: UserDefaults

    var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            if selection == .system {
                userDefaults.removeObject(forKey: AppLanguage.userDefaultsKey)
            } else {
                userDefaults.set(selection.rawValue, forKey: AppLanguage.userDefaultsKey)
            }
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        selection = AppLanguage.persisted(in: userDefaults)
    }
}
