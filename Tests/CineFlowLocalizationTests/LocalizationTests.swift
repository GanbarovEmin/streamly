import XCTest
@testable import CineFlowLocalization

final class LocalizationTests: XCTestCase {
    func testRussianAndEnglishNavigationStringsResolve() {
        XCTAssertEqual(L10n.string(.navigationHome, language: .ru), "Главная")
        XCTAssertEqual(L10n.string(.navigationHome, language: .en), "Home")
        XCTAssertEqual(L10n.string(.navigationSettings, language: .ru), "Настройки")
        XCTAssertEqual(L10n.string(.navigationSettings, language: .en), "Settings")
    }

    func testLanguageOptionsAreReadyForSettingsPicker() {
        XCTAssertEqual(AppLanguage.allCases, [.system, .ru, .en])
        XCTAssertEqual(AppLanguage.ru.displayNameKey, .languageRussian)
        XCTAssertEqual(AppLanguage.en.displayNameKey, .languageEnglish)
    }

    @MainActor
    func testLanguageSelectionPersistsInUserDefaults() {
        let suiteName = "CineFlowLocalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = LanguageSettingsStore(userDefaults: defaults)
        XCTAssertEqual(store.selectedLanguage, .system)

        store.setLanguage(.en)

        let reloadedStore = LanguageSettingsStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.selectedLanguage, .en)
    }

    func testFormattedStringsUseSelectedLocalizationBundle() {
        XCTAssertEqual(L10n.format(.bestReleaseFormat, language: .en, "Matrix 4K", 88), "Matrix 4K · 88 seeders")
        XCTAssertEqual(L10n.format(.bestReleaseFormat, language: .ru, "Matrix 4K", 88), "Matrix 4K · 88 сидов")
    }
}
