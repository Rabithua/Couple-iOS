import Foundation

enum AppLocalization {
    static func string(
        _ keyAndValue: String.LocalizationValue,
        bundle: Bundle = .main,
        language: AppLanguage = .persisted()
    ) -> String {
        String(
            localized: keyAndValue,
            bundle: localizedBundle(in: bundle, for: language),
            locale: language.locale
        )
    }

    static func string(
        _ key: StaticString,
        defaultValue: String.LocalizationValue,
        bundle: Bundle = .main,
        language: AppLanguage = .persisted()
    ) -> String {
        String(
            localized: key,
            defaultValue: defaultValue,
            bundle: localizedBundle(in: bundle, for: language),
            locale: language.locale
        )
    }

    private static func localizedBundle(
        in bundle: Bundle,
        for language: AppLanguage
    ) -> Bundle {
        guard language != .system,
              let path = bundle.path(forResource: language.rawValue, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return bundle
        }
        return localizedBundle
    }
}
