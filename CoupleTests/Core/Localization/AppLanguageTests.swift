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

    @Test
    func systemBirthdayTitleUsesTheSelectedLanguage() throws {
        let appBundle = try #require(Bundle(identifier: "com.oursince.couple"))
        let birthday = Anniversary(
            id: "birthday",
            coupleId: "couple",
            ownerId: "owner",
            title: "Alice",
            date: "2000-08-20",
            annual: true,
            visibility: .shared,
            createdAt: .now,
            updatedAt: .now,
            nextOccurrence: nil,
            systemKind: "birthday"
        )

        #expect(
            birthday.localizedDisplayTitle(language: .english, bundle: appBundle)
                == "Alice’s birthday"
        )
        #expect(
            birthday.localizedDisplayTitle(language: .simplifiedChinese, bundle: appBundle)
                == "Alice的生日"
        )
        #expect(
            birthday.localizedDisplayTitle(language: .traditionalChinese, bundle: appBundle)
                == "Alice的生日"
        )
    }

    @Test
    func datesUseTheSelectedAppLocale() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18,
            hour: 13,
            minute: 5
        )))

        #expect(date.localizedMonthTitle(locale: AppLanguage.english.locale) == "August 2026")
        #expect(date.localizedMonthTitle(locale: AppLanguage.simplifiedChinese.locale) == "2026年8月")
        #expect(
            date.localizedDateTime(locale: AppLanguage.english.locale)
                != date.localizedDateTime(locale: AppLanguage.simplifiedChinese.locale)
        )
    }

    @Test
    func calendarGridAndWeekdaysFollowTheLocaleFirstWeekday() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_GB")
        let calendar = Calendar.localizedGregorian(locale: locale, timeZone: timeZone)
        let date = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 16
        )))
        let month = try #require(
            CalendarMonth.make(startingAt: date, count: 1, calendar: calendar).first
        )

        #expect(calendar.firstWeekday == 2)
        #expect(calendar.localizedVeryShortStandaloneWeekdaySymbols.first == "M")
        #expect(month.days.prefix(2).allSatisfy { $0 == nil })
        #expect(calendar.component(.day, from: try #require(month.days[2])) == 1)
    }
}
