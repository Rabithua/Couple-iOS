@testable import Couple
import Foundation
import Testing

@MainActor
struct AppLanguageTests {
    @Test
    func languageSelectionPersistsAndCanReturnToSystemDefault() throws {
        let suiteName = "AppLanguageTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.removePersistentDomain(forName: suiteName)

        let store = AppLanguageStore(userDefaults: userDefaults)
        #expect(store.selection == .system)

        store.selection = .english
        #expect(AppLanguage.persisted(in: userDefaults) == .english)
        #expect(AppLanguageStore(userDefaults: userDefaults).selection == .english)

        store.selection = .system
        #expect(userDefaults.object(forKey: AppLanguage.userDefaultsKey) == nil)
    }

    @Test
    func supportedLanguagesResolveTheExpectedSettingsTitle() throws {
        let appBundle = try #require(Bundle(identifier: "com.oursince.couple"))

        #expect(AppLocalization.string("设置", bundle: appBundle, language: .simplifiedChinese) == "设置")
        #expect(AppLocalization.string("设置", bundle: appBundle, language: .english) == "Settings")
        #expect(AppLocalization.string("设置", bundle: appBundle, language: .traditionalChinese) == "設定")
    }
}
