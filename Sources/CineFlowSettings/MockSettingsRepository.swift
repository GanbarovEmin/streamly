import CineFlowCore
import Foundation

public final class MockSettingsRepository: SettingsRepositoryProtocol {
    private var settings: AppSettings
    private var subtitleSettingsValue: SubtitleSettings
    private var languages: [String]
    private var metadataCredentials: [String: String]

    public init(settings: AppSettings = AppSettings(), languages: [String] = ["ru", "en"]) {
        self.settings = settings
        subtitleSettingsValue = SubtitleSettings(languagePreference: SubtitleLanguagePreference(languages))
        self.languages = languages
        metadataCredentials = [:]
    }

    public var appSettings: AppSettings {
        get async { settings }
    }

    public var subtitleLanguagePriority: [String] {
        get async { languages }
    }

    public var subtitleSettings: SubtitleSettings {
        get async { subtitleSettingsValue }
    }

    public func setAppSettings(_ settings: AppSettings) async {
        self.settings = settings
    }

    public func setSubtitleLanguagePriority(_ languages: [String]) async {
        self.languages = languages
        subtitleSettingsValue.languagePreference = SubtitleLanguagePreference(languages)
    }

    public func setSubtitleSettings(_ settings: SubtitleSettings) async {
        subtitleSettingsValue = settings
        languages = settings.languagePreference.languageCodes
    }

    public func metadataCredential(forKey key: String) async -> String? {
        metadataCredentials[key]
    }

    public func setMetadataCredential(_ value: String?, forKey key: String) async {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            metadataCredentials[key] = trimmed
        } else {
            metadataCredentials.removeValue(forKey: key)
        }
    }

    public func clearAllLocalData() async {
        settings = AppSettings()
        subtitleSettingsValue = SubtitleSettings()
        languages = ["ru", "en"]
        metadataCredentials.removeAll()
    }
}
