import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case traditionalChinese = "zh-Hant"

    static let userDefaultsKey = "app.preferences.language"

    var id: Self { self }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .simplifiedChinese: Locale(identifier: rawValue)
        case .english: Locale(identifier: rawValue)
        case .traditionalChinese: Locale(identifier: rawValue)
        }
    }

    var displayName: String {
        switch self {
        case .system: AppLocalization.string("跟随系统")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        case .traditionalChinese: "繁體中文"
        }
    }

    static func persisted(in userDefaults: UserDefaults = .standard) -> Self {
        guard let rawValue = userDefaults.string(forKey: userDefaultsKey) else {
            return .system
        }
        return Self(rawValue: rawValue) ?? .system
    }
}
