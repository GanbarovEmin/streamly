import Combine
import Foundation

@MainActor
public final class LanguageSettingsStore: ObservableObject {
    @Published public private(set) var selectedLanguage: AppLanguage

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedValue = userDefaults.string(forKey: AppLanguage.storageKey)
        selectedLanguage = storedValue.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    public func setLanguage(_ language: AppLanguage) {
        selectedLanguage = language
        userDefaults.set(language.rawValue, forKey: AppLanguage.storageKey)
    }
}
