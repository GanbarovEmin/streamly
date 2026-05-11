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

public enum PreferredQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case p720
    case p1080
    case p2160
    case highestAvailable

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto:
            "Auto"
        case .p720:
            "720p"
        case .p1080:
            "1080p"
        case .p2160:
            "2160p"
        case .highestAvailable:
            "Highest available"
        }
    }

    public var targetQuality: ReleaseQuality? {
        switch self {
        case .auto, .highestAvailable:
            nil
        case .p720:
            .hd
        case .p1080:
            .fullHD
        case .p2160:
            .ultraHD
        }
    }
}

public enum HDRPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case preferHDR
    case avoidHDR

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto:
            "Auto"
        case .preferHDR:
            "Prefer HDR"
        case .avoidHDR:
            "Avoid HDR"
        }
    }
}

public enum CodecPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case preferHEVC
    case avoidUnsupportedAV1

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto:
            "Auto"
        case .preferHEVC:
            "Prefer HEVC"
        case .avoidUnsupportedAV1:
            "Avoid AV1 if unsupported"
        }
    }
}

public enum PreferredAudioOrder: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case russianEnglishOriginal
    case englishRussianOriginal
    case originalRussianEnglish
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .russianEnglishOriginal:
            "Russian -> English -> Original"
        case .englishRussianOriginal:
            "English -> Russian -> Original"
        case .originalRussianEnglish:
            "Original -> Russian -> English"
        case .custom:
            "Custom order"
        }
    }

    public func languagePriority(customLanguages: [String]) -> [String] {
        switch self {
        case .russianEnglishOriginal:
            ["ru", "en", "original"]
        case .englishRussianOriginal:
            ["en", "ru", "original"]
        case .originalRussianEnglish:
            ["original", "ru", "en"]
        case .custom:
            Self.normalizedCustomLanguages(customLanguages)
        }
    }

    private static func normalizedCustomLanguages(_ languages: [String]) -> [String] {
        var result = languages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if !result.contains("original") {
            result.append("original")
        }
        return result.isEmpty ? ["ru", "en", "original"] : Array(NSOrderedSet(array: result)) as? [String] ?? result
    }
}

public struct AudioSelectionOverride: Codable, Equatable, Sendable {
    public var trackID: String?
    public var languageCode: String?
    public var isOriginal: Bool
    public var updatedAt: Date

    public init(
        trackID: String? = nil,
        languageCode: String? = nil,
        isOriginal: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.trackID = trackID
        self.languageCode = languageCode?.lowercased()
        self.isOriginal = isOriginal
        self.updatedAt = updatedAt
    }
}

public struct PlaybackSettings: Codable, Equatable, Sendable {
    public var preferredAudioOrder: PreferredAudioOrder
    public var preferredAudioLanguages: [String]
    public var preferredQuality: PreferredQuality
    public var hdrPreference: HDRPreference
    public var codecPreference: CodecPreference
    public var maxFileSizeBytes: Int64?
    public var preferHighSeedersOverHighestQuality: Bool
    public var hardwareAccelerationEnabled: Bool
    public var startFromLastPosition: Bool
    public var defaultFullscreen: Bool
    public var seekStepSeconds: Int
    public var rememberedVolume: Double
    public var rememberedAudioLanguage: String?
    public var rememberedSubtitleLanguage: String?
    public var subtitlesEnabled: Bool
    public var playbackSpeed: Double
    public var audioBoost: Double
    public var dimBackgroundAroundVideo: Bool
    public var enableTimelinePreviews: Bool
    public var autoplayNextEpisode: Bool
    public var manualAudioOverridesByMediaID: [String: AudioSelectionOverride]

    public init(
        preferredAudioOrder: PreferredAudioOrder = .russianEnglishOriginal,
        preferredAudioLanguages: [String] = ["ru", "en"],
        preferredQuality: PreferredQuality = .auto,
        hdrPreference: HDRPreference = .auto,
        codecPreference: CodecPreference = .auto,
        maxFileSizeBytes: Int64? = nil,
        preferHighSeedersOverHighestQuality: Bool = false,
        hardwareAccelerationEnabled: Bool = true,
        startFromLastPosition: Bool = true,
        defaultFullscreen: Bool = false,
        seekStepSeconds: Int = 10,
        rememberedVolume: Double = 1,
        rememberedAudioLanguage: String? = nil,
        rememberedSubtitleLanguage: String? = nil,
        subtitlesEnabled: Bool = true,
        playbackSpeed: Double = 1,
        audioBoost: Double = 1,
        dimBackgroundAroundVideo: Bool = false,
        enableTimelinePreviews: Bool = true,
        autoplayNextEpisode: Bool = true,
        manualAudioOverridesByMediaID: [String: AudioSelectionOverride] = [:]
    ) {
        self.preferredAudioOrder = preferredAudioOrder
        self.preferredAudioLanguages = Self.normalizedLanguages(preferredAudioLanguages)
        self.preferredQuality = preferredQuality
        self.hdrPreference = hdrPreference
        self.codecPreference = codecPreference
        self.maxFileSizeBytes = maxFileSizeBytes.map { max(0, $0) }
        self.preferHighSeedersOverHighestQuality = preferHighSeedersOverHighestQuality
        self.hardwareAccelerationEnabled = hardwareAccelerationEnabled
        self.startFromLastPosition = startFromLastPosition
        self.defaultFullscreen = defaultFullscreen
        self.seekStepSeconds = seekStepSeconds
        self.rememberedVolume = min(max(rememberedVolume, 0), 1)
        self.rememberedAudioLanguage = rememberedAudioLanguage?.lowercased()
        self.rememberedSubtitleLanguage = rememberedSubtitleLanguage?.lowercased()
        self.subtitlesEnabled = subtitlesEnabled
        self.playbackSpeed = min(max(playbackSpeed, 0.25), 4)
        self.audioBoost = min(max(audioBoost, 1), 2.5)
        self.dimBackgroundAroundVideo = dimBackgroundAroundVideo
        self.enableTimelinePreviews = enableTimelinePreviews
        self.autoplayNextEpisode = autoplayNextEpisode
        self.manualAudioOverridesByMediaID = manualAudioOverridesByMediaID
    }

    private enum CodingKeys: String, CodingKey {
        case preferredAudioOrder
        case preferredAudioLanguages
        case preferredQuality
        case hdrPreference
        case codecPreference
        case maxFileSizeBytes
        case preferHighSeedersOverHighestQuality
        case hardwareAccelerationEnabled
        case startFromLastPosition
        case defaultFullscreen
        case seekStepSeconds
        case rememberedVolume
        case rememberedAudioLanguage
        case rememberedSubtitleLanguage
        case subtitlesEnabled
        case playbackSpeed
        case audioBoost
        case dimBackgroundAroundVideo
        case enableTimelinePreviews
        case autoplayNextEpisode
        case manualAudioOverridesByMediaID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredAudioOrder = try container.decodeIfPresent(PreferredAudioOrder.self, forKey: .preferredAudioOrder) ?? .russianEnglishOriginal
        preferredAudioLanguages = Self.normalizedLanguages(try container.decodeIfPresent([String].self, forKey: .preferredAudioLanguages) ?? ["ru", "en"])
        preferredQuality = try container.decodeIfPresent(PreferredQuality.self, forKey: .preferredQuality) ?? .auto
        hdrPreference = try container.decodeIfPresent(HDRPreference.self, forKey: .hdrPreference) ?? .auto
        codecPreference = try container.decodeIfPresent(CodecPreference.self, forKey: .codecPreference) ?? .auto
        maxFileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .maxFileSizeBytes).map { max(0, $0) }
        preferHighSeedersOverHighestQuality = try container.decodeIfPresent(Bool.self, forKey: .preferHighSeedersOverHighestQuality) ?? false
        hardwareAccelerationEnabled = try container.decodeIfPresent(Bool.self, forKey: .hardwareAccelerationEnabled) ?? true
        startFromLastPosition = try container.decodeIfPresent(Bool.self, forKey: .startFromLastPosition) ?? true
        defaultFullscreen = try container.decodeIfPresent(Bool.self, forKey: .defaultFullscreen) ?? false
        seekStepSeconds = try container.decodeIfPresent(Int.self, forKey: .seekStepSeconds) ?? 10
        rememberedVolume = min(max(try container.decodeIfPresent(Double.self, forKey: .rememberedVolume) ?? 1, 0), 1)
        rememberedAudioLanguage = try container.decodeIfPresent(String.self, forKey: .rememberedAudioLanguage)?.lowercased()
        rememberedSubtitleLanguage = try container.decodeIfPresent(String.self, forKey: .rememberedSubtitleLanguage)?.lowercased()
        subtitlesEnabled = try container.decodeIfPresent(Bool.self, forKey: .subtitlesEnabled) ?? true
        playbackSpeed = min(max(try container.decodeIfPresent(Double.self, forKey: .playbackSpeed) ?? 1, 0.25), 4)
        audioBoost = min(max(try container.decodeIfPresent(Double.self, forKey: .audioBoost) ?? 1, 1), 2.5)
        dimBackgroundAroundVideo = try container.decodeIfPresent(Bool.self, forKey: .dimBackgroundAroundVideo) ?? false
        enableTimelinePreviews = try container.decodeIfPresent(Bool.self, forKey: .enableTimelinePreviews) ?? true
        autoplayNextEpisode = try container.decodeIfPresent(Bool.self, forKey: .autoplayNextEpisode) ?? true
        manualAudioOverridesByMediaID = try container.decodeIfPresent([String: AudioSelectionOverride].self, forKey: .manualAudioOverridesByMediaID) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preferredAudioOrder, forKey: .preferredAudioOrder)
        try container.encode(preferredAudioLanguages, forKey: .preferredAudioLanguages)
        try container.encode(preferredQuality, forKey: .preferredQuality)
        try container.encode(hdrPreference, forKey: .hdrPreference)
        try container.encode(codecPreference, forKey: .codecPreference)
        try container.encodeIfPresent(maxFileSizeBytes, forKey: .maxFileSizeBytes)
        try container.encode(preferHighSeedersOverHighestQuality, forKey: .preferHighSeedersOverHighestQuality)
        try container.encode(hardwareAccelerationEnabled, forKey: .hardwareAccelerationEnabled)
        try container.encode(startFromLastPosition, forKey: .startFromLastPosition)
        try container.encode(defaultFullscreen, forKey: .defaultFullscreen)
        try container.encode(seekStepSeconds, forKey: .seekStepSeconds)
        try container.encode(rememberedVolume, forKey: .rememberedVolume)
        try container.encodeIfPresent(rememberedAudioLanguage, forKey: .rememberedAudioLanguage)
        try container.encodeIfPresent(rememberedSubtitleLanguage, forKey: .rememberedSubtitleLanguage)
        try container.encode(subtitlesEnabled, forKey: .subtitlesEnabled)
        try container.encode(playbackSpeed, forKey: .playbackSpeed)
        try container.encode(audioBoost, forKey: .audioBoost)
        try container.encode(dimBackgroundAroundVideo, forKey: .dimBackgroundAroundVideo)
        try container.encode(enableTimelinePreviews, forKey: .enableTimelinePreviews)
        try container.encode(autoplayNextEpisode, forKey: .autoplayNextEpisode)
        try container.encode(manualAudioOverridesByMediaID, forKey: .manualAudioOverridesByMediaID)
    }

    public func rankingPreferences(
        preferredSubtitleLanguages: [String] = [],
        supportsHDR: Bool = true
    ) -> RankingPreferences {
        RankingPreferences(
            preferredAudioLanguages: preferredAudioLanguages,
            preferredSubtitleLanguages: preferredSubtitleLanguages,
            supportsHDR: supportsHDR,
            preferredQuality: preferredQuality,
            hdrPreference: hdrPreference,
            codecPreference: codecPreference,
            maxFileSizeBytes: maxFileSizeBytes,
            preferHighSeedersOverHighestQuality: preferHighSeedersOverHighestQuality
        )
    }

    public var resolvedAudioLanguagePriority: [String] {
        preferredAudioOrder.languagePriority(customLanguages: preferredAudioLanguages)
    }

    private static func normalizedLanguages(_ languages: [String]) -> [String] {
        let normalized = languages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? ["ru", "en"] : Array(NSOrderedSet(array: normalized)) as? [String] ?? normalized
    }
}

public struct UpdateSettings: Codable, Equatable, Sendable {
    public var automaticChecksEnabled: Bool
    public var sparkleStatus: String

    public init(
        automaticChecksEnabled: Bool = true,
        sparkleStatus: String = "GitHub Releases status checks"
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
    public var cacheRetentionDays: Int
    public var maxCacheSizeBytes: Int64
    public var keepUnfinishedCache: Bool
    public var removeCompletedCache: Bool
    public var torrentDownloadLimitBytesPerSecond: Int64?
    public var torrentUploadLimitBytesPerSecond: Int64?

    public init(
        torrentCacheFolderPath: String = TorrentCacheLocation.defaultStorageURL().path,
        downloadsFolderPath: String? = nil,
        cacheRetentionDays: Int = 30,
        maxCacheSizeBytes: Int64 = 50 * 1_024 * 1_024 * 1_024,
        keepUnfinishedCache: Bool = true,
        removeCompletedCache: Bool = false,
        torrentDownloadLimitBytesPerSecond: Int64? = nil,
        torrentUploadLimitBytesPerSecond: Int64? = nil
    ) {
        self.torrentCacheFolderPath = torrentCacheFolderPath
        self.downloadsFolderPath = downloadsFolderPath
        self.cacheRetentionDays = min(max(cacheRetentionDays, 7), 30)
        self.maxCacheSizeBytes = max(maxCacheSizeBytes, 1_024 * 1_024 * 1_024)
        self.keepUnfinishedCache = keepUnfinishedCache
        self.removeCompletedCache = removeCompletedCache
        self.torrentDownloadLimitBytesPerSecond = torrentDownloadLimitBytesPerSecond
        self.torrentUploadLimitBytesPerSecond = torrentUploadLimitBytesPerSecond
    }

    private enum CodingKeys: String, CodingKey {
        case torrentCacheFolderPath
        case downloadsFolderPath
        case cacheRetentionDays
        case maxCacheSizeBytes
        case keepUnfinishedCache
        case removeCompletedCache
        case torrentDownloadLimitBytesPerSecond
        case torrentUploadLimitBytesPerSecond
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            torrentCacheFolderPath: try container.decodeIfPresent(String.self, forKey: .torrentCacheFolderPath) ?? TorrentCacheLocation.defaultStorageURL().path,
            downloadsFolderPath: try container.decodeIfPresent(String.self, forKey: .downloadsFolderPath),
            cacheRetentionDays: try container.decodeIfPresent(Int.self, forKey: .cacheRetentionDays) ?? 30,
            maxCacheSizeBytes: try container.decodeIfPresent(Int64.self, forKey: .maxCacheSizeBytes) ?? 50 * 1_024 * 1_024 * 1_024,
            keepUnfinishedCache: try container.decodeIfPresent(Bool.self, forKey: .keepUnfinishedCache) ?? true,
            removeCompletedCache: try container.decodeIfPresent(Bool.self, forKey: .removeCompletedCache) ?? false,
            torrentDownloadLimitBytesPerSecond: try container.decodeIfPresent(Int64.self, forKey: .torrentDownloadLimitBytesPerSecond),
            torrentUploadLimitBytesPerSecond: try container.decodeIfPresent(Int64.self, forKey: .torrentUploadLimitBytesPerSecond)
        )
    }

    public var smartCachePolicy: SmartCachePolicy {
        SmartCachePolicy(
            retentionDays: cacheRetentionDays,
            maxSizeBytes: maxCacheSizeBytes,
            keepUnfinished: keepUnfinishedCache,
            removeCompleted: removeCompletedCache
        )
    }

    public var torrentBandwidthLimits: TorrentBandwidthLimits {
        TorrentBandwidthLimits(
            downloadBytesPerSecond: torrentDownloadLimitBytesPerSecond,
            uploadBytesPerSecond: torrentUploadLimitBytesPerSecond
        )
    }
}
