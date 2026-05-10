import Foundation

public enum AppLanguageSetting: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case system
    case russian
    case english

    public var id: String { rawValue }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var general: GeneralSettings
    public var appearance: AppearanceSettings
    public var playback: PlaybackSettings
    public var updates: UpdateSettings
    public var privacy: PrivacySettings
    public var storage: StorageSettings

    public init(
        general: GeneralSettings = GeneralSettings(),
        appearance: AppearanceSettings = AppearanceSettings(),
        playback: PlaybackSettings = PlaybackSettings(),
        updates: UpdateSettings = UpdateSettings(),
        privacy: PrivacySettings = PrivacySettings(),
        storage: StorageSettings = StorageSettings()
    ) {
        self.general = general
        self.appearance = appearance
        self.playback = playback
        self.updates = updates
        self.privacy = privacy
        self.storage = storage
    }

    private enum CodingKeys: String, CodingKey {
        case general
        case appearance
        case playback
        case updates
        case privacy
        case storage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        general = try container.decodeIfPresent(GeneralSettings.self, forKey: .general) ?? GeneralSettings()
        appearance = try container.decodeIfPresent(AppearanceSettings.self, forKey: .appearance) ?? AppearanceSettings()
        playback = try container.decodeIfPresent(PlaybackSettings.self, forKey: .playback) ?? PlaybackSettings()
        updates = try container.decodeIfPresent(UpdateSettings.self, forKey: .updates) ?? UpdateSettings()
        privacy = try container.decodeIfPresent(PrivacySettings.self, forKey: .privacy) ?? PrivacySettings()
        storage = try container.decodeIfPresent(StorageSettings.self, forKey: .storage) ?? StorageSettings()
    }
}

public struct GeneralSettings: Codable, Equatable, Sendable {
    public var language: AppLanguageSetting
    public var launchAtLogin: Bool
    public var openLastScreenOnLaunch: Bool

    public init(
        language: AppLanguageSetting = .system,
        launchAtLogin: Bool = false,
        openLastScreenOnLaunch: Bool = false
    ) {
        self.language = language
        self.launchAtLogin = launchAtLogin
        self.openLastScreenOnLaunch = openLastScreenOnLaunch
    }
}

public struct AppearanceSettings: Codable, Equatable, Sendable {
    public var darkModeOnly: Bool
    public var accentColorName: String
    public var reduceMotion: Bool

    public init(
        darkModeOnly: Bool = true,
        accentColorName: String = "neonPurple",
        reduceMotion: Bool = false
    ) {
        self.darkModeOnly = darkModeOnly
        self.accentColorName = accentColorName
        self.reduceMotion = reduceMotion
    }
}

public struct PlaybackSettings: Codable, Equatable, Sendable {
    public var preferredAudioLanguages: [String]
    public var hardwareAccelerationEnabled: Bool
    public var startFromLastPosition: Bool
    public var defaultFullscreen: Bool
    public var seekStepSeconds: Int

    public init(
        preferredAudioLanguages: [String] = ["ru", "en"],
        hardwareAccelerationEnabled: Bool = true,
        startFromLastPosition: Bool = true,
        defaultFullscreen: Bool = false,
        seekStepSeconds: Int = 10
    ) {
        self.preferredAudioLanguages = preferredAudioLanguages
        self.hardwareAccelerationEnabled = hardwareAccelerationEnabled
        self.startFromLastPosition = startFromLastPosition
        self.defaultFullscreen = defaultFullscreen
        self.seekStepSeconds = seekStepSeconds
    }
}

public struct UpdateSettings: Codable, Equatable, Sendable {
    public var automaticChecksEnabled: Bool
    public var sparkleStatus: String

    public init(
        automaticChecksEnabled: Bool = true,
        sparkleStatus: String = "Ready for Sparkle integration"
    ) {
        self.automaticChecksEnabled = automaticChecksEnabled
        self.sparkleStatus = sparkleStatus
    }
}

public struct PrivacySettings: Codable, Equatable, Sendable {
    public var telemetryEnabled: Bool

    public init(telemetryEnabled: Bool = false) {
        self.telemetryEnabled = telemetryEnabled
    }
}

public struct StorageSettings: Codable, Equatable, Sendable {
    public var torrentCacheFolderPath: String
    public var downloadsFolderPath: String?

    public init(
        torrentCacheFolderPath: String = TorrentCacheLocation.defaultStorageURL().path,
        downloadsFolderPath: String? = nil
    ) {
        self.torrentCacheFolderPath = torrentCacheFolderPath
        self.downloadsFolderPath = downloadsFolderPath
    }
}
