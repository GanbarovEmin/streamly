import CineFlowCore
import CineFlowSources
import AppKit
import Foundation
import UniformTypeIdentifiers

public enum SettingsSectionID: String, CaseIterable, Identifiable, Sendable {
    case general
    case appearance
    case home
    case tasteProfile
    case sources
    case playback
    case subtitles
    case cache
    case updates
    case diagnostics
    case privacy
    case about

    public var id: Self { self }

    public var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .home: "Home"
        case .tasteProfile: "Taste Profile"
        case .sources: "Sources"
        case .playback: "Playback"
        case .subtitles: "Subtitles"
        case .cache: "Cache"
        case .updates: "Updates"
        case .diagnostics: "Diagnostics"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    public var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .home: "rectangle.stack"
        case .tasteProfile: "slider.horizontal.3"
        case .sources: "antenna.radiowaves.left.and.right"
        case .playback: "play.rectangle"
        case .subtitles: "captions.bubble"
        case .cache: "externaldrive"
        case .updates: "arrow.triangle.2.circlepath"
        case .diagnostics: "stethoscope"
        case .privacy: "lock.shield"
        case .about: "info.circle"
        }
    }
}

public enum SettingsMoveDirection: Equatable, Sendable {
    case up
    case down
}

public struct SettingsSectionItem: Identifiable, Equatable, Sendable {
    public let id: SettingsSectionID
    public let title: String
    public let systemImage: String
}

public struct SettingsSourceRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let requiresAuthentication: Bool
    public var settings: SourceSettings

    public var statusText: String {
        switch settings.authenticationStatus {
        case .notRequired:
            settings.isEnabled ? "Enabled" : "Disabled"
        case .unauthenticated:
            "Sign in required"
        case .authenticated(let username):
            username.map { "Signed in as \($0)" } ?? "Signed in"
        case .invalid(let reason):
            reason
        }
    }
}

public struct SettingsCacheSummary: Equatable, Sendable {
    public var imageBytes: Int64?
    public var torrentBytes: Int64
    public var subtitleBytes: Int64
    public var timelinePreviewBytes: Int64
    public var metadataBytes: Int64
    public var buckets: [SmartCacheBucketSummary]
    public var titleItems: [SmartTitleCacheItem]
    public var maxSizeBytes: Int64

    public init(
        imageBytes: Int64? = nil,
        torrentBytes: Int64 = 0,
        subtitleBytes: Int64 = 0,
        timelinePreviewBytes: Int64 = 0,
        metadataBytes: Int64 = 0,
        buckets: [SmartCacheBucketSummary] = [],
        titleItems: [SmartTitleCacheItem] = [],
        maxSizeBytes: Int64 = SmartCachePolicy().maxSizeBytes
    ) {
        self.imageBytes = imageBytes
        self.torrentBytes = torrentBytes
        self.subtitleBytes = subtitleBytes
        self.timelinePreviewBytes = timelinePreviewBytes
        self.metadataBytes = metadataBytes
        self.buckets = buckets
        self.titleItems = titleItems
        self.maxSizeBytes = maxSizeBytes
    }

    public var totalBytes: Int64 {
        (imageBytes ?? 0) + torrentBytes + subtitleBytes + timelinePreviewBytes + metadataBytes
    }

    public var isAlmostFull: Bool {
        guard maxSizeBytes > 0 else { return false }
        return Double(totalBytes) / Double(maxSizeBytes) >= 0.9
    }
}

public struct SettingsAboutInfo: Equatable, Sendable {
    public let appName: String
    public let version: String
    public let build: String
    public let credits: String
    public let licenses: String

    public init(
        appName: String = "Streamly",
        version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
        build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev",
        credits: String = "Streamly contributors",
        licenses: String = "Open-source dependencies are listed in the package manifest."
    ) {
        self.appName = appName
        self.version = version
        self.build = build
        self.credits = credits
        self.licenses = licenses
    }
}

public struct TMDBCredentialSummary: Equatable, Sendable {
    public let hasReadAccessToken: Bool
    public let hasAPIKey: Bool
    public let lastValidation: String?

    public init(hasReadAccessToken: Bool = false, hasAPIKey: Bool = false, lastValidation: String? = nil) {
        self.hasReadAccessToken = hasReadAccessToken
        self.hasAPIKey = hasAPIKey
        self.lastValidation = lastValidation
    }

    public var statusText: String {
        if hasReadAccessToken {
            return "TMDB read access token saved"
        }
        if hasAPIKey {
            return "TMDB API key saved"
        }
        return "TMDB credentials missing"
    }

    public var detailText: String {
        lastValidation ?? "TMDB is optional. Save a read access token or v3 API key here to enable TMDB fallback metadata."
    }
}

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public private(set) var settings = AppSettings()
    @Published public private(set) var subtitleSettings = SubtitleSettings()
    @Published public private(set) var sections: [SettingsSectionItem] = SettingsSectionID.allCases.map {
        SettingsSectionItem(id: $0, title: $0.title, systemImage: $0.systemImage)
    }
    @Published public private(set) var sourceRows: [SettingsSourceRow] = []
    @Published public private(set) var cacheSummary = SettingsCacheSummary()
    @Published public private(set) var cachedSubtitleItems: [CachedSubtitleItem] = []
    @Published public private(set) var updateStatus: UpdateStatus = .idle
    @Published public private(set) var tmdbCredentialSummary = TMDBCredentialSummary()
    @Published public private(set) var torrentioSettings = TorrentioSettings.defaults
    @Published public private(set) var torrentioDebridTokenConfigured = false
    @Published public private(set) var lastUpdateCheckedAt: Date?
    @Published public private(set) var diagnosticsExport: String?
    @Published public private(set) var libraryImportPreview: LibraryImportPreview?
    @Published public private(set) var operationMessage: String?
    @Published public private(set) var isBusy = false
    @Published public var backupBeforeLibraryImport = true
    @Published public var torrentioDebridTokenInput = ""

    public let about: SettingsAboutInfo

    private let environment: AppEnvironment
    private let sourceManager: SourceManager?
    private let torrentioSettingsStore: any TorrentioSettingsStoreProtocol
    private let torrentioCredentialStore: any SourceCredentialStoreProtocol
    private let torrentioURLBuilder: TorrentioConfigurationURLBuilder
    private let fileManager: FileManager
    private let cacheBaseURL: URL
    private var pendingLibraryImportData: Data?

    public init(
        environment: AppEnvironment,
        sourceManager: SourceManager? = nil,
        torrentioSettingsStore: any TorrentioSettingsStoreProtocol = UserDefaultsTorrentioSettingsStore(),
        torrentioCredentialStore: (any SourceCredentialStoreProtocol)? = nil,
        torrentioURLBuilder: TorrentioConfigurationURLBuilder = TorrentioConfigurationURLBuilder(),
        fileManager: FileManager = .default,
        cacheBaseURL: URL? = nil,
        about: SettingsAboutInfo = SettingsAboutInfo()
    ) {
        self.environment = environment
        self.sourceManager = sourceManager
        self.torrentioSettingsStore = torrentioSettingsStore
        if let torrentioCredentialStore {
            self.torrentioCredentialStore = torrentioCredentialStore
        } else if let keychainService = environment.keychainService {
            self.torrentioCredentialStore = KeychainSourceCredentialStore(keychainService: keychainService)
        } else {
            self.torrentioCredentialStore = InMemorySourceCredentialStore()
        }
        self.torrentioURLBuilder = torrentioURLBuilder
        self.fileManager = fileManager
        self.cacheBaseURL = cacheBaseURL ?? Self.defaultCacheBaseURL(fileManager: fileManager)
        self.about = about
    }

    public var torrentioConfiguredManifestURL: URL? {
        try? torrentioURLBuilder.manifestURL(
            settings: torrentioSettings,
            credentials: torrentioPreviewCredentials
        )
    }

    private var torrentioPreviewCredentials: SourceCredentials? {
        guard torrentioSettings.debridProvider != .none else { return nil }
        let token = torrentioDebridTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        return SourceCredentials(username: torrentioSettings.debridProvider.rawValue, token: token)
    }

    public var hiddenRecommendationItems: [HiddenRecommendationItem] {
        settings.tasteProfile.hiddenItems
    }

    public func load() async {
        settings = await environment.settingsRepository.appSettings
        UserDefaults.standard.set(settings.appearance.reduceMotion, forKey: "streamly.reduceMotion")
        subtitleSettings = await environment.settingsRepository.subtitleSettings
        updateStatus = await environment.updateService.currentStatus
        settings.updates.automaticChecksEnabled = await environment.updateService.automaticallyChecksForUpdates
        lastUpdateCheckedAt = await environment.updateService.lastCheckedAt
        await refreshTMDBCredentialSummary()
        await refreshTorrentioSettings()
        await refreshTorrentioDebridCredentials()
        await refreshSources()
        await refreshCacheSummary()
        await refreshCachedSubtitles()
    }

    public func updateLanguage(_ language: AppLanguageSetting) async {
        settings.general.language = language
        await persistSettings()
    }

    public func updateLaunchAtLogin(_ enabled: Bool) async {
        settings.general.launchAtLogin = enabled
        await persistSettings()
    }

    public func updateOpenLastScreenOnLaunch(_ enabled: Bool) async {
        settings.general.openLastScreenOnLaunch = enabled
        await persistSettings()
    }

    public func updateReduceMotion(_ enabled: Bool) async {
        settings.appearance.reduceMotion = enabled
        UserDefaults.standard.set(enabled, forKey: "streamly.reduceMotion")
        await persistSettings()
    }

    public func updateHomeSection(_ sectionID: String, isEnabled: Bool) async {
        settings.home.setSection(sectionID, isEnabled: isEnabled)
        await persistSettings()
    }

    public func moveHomeSection(_ sectionID: String, direction: SettingsMoveDirection) async {
        let orderedIDs = settings.home.orderedSections.map(\.sectionID)
        guard let currentIndex = orderedIDs.firstIndex(of: sectionID) else { return }
        let destinationIndex: Int
        switch direction {
        case .up:
            destinationIndex = currentIndex - 1
        case .down:
            destinationIndex = currentIndex + 1
        }
        settings.home.moveSection(sectionID, to: destinationIndex)
        await persistSettings()
    }

    public func updateHomeLayoutDensity(_ density: HomeLayoutDensity) async {
        guard settings.home.layoutDensity != density else { return }
        settings.home.layoutDensity = density
        settings.home.touch()
        await persistSettings()
    }

    public func updateHomePosterSize(_ posterSize: HomePosterSizePreference) async {
        guard settings.home.posterSize != posterSize else { return }
        settings.home.posterSize = posterSize
        settings.home.touch()
        await persistSettings()
    }

    public func updateLocalRecommendationsEnabled(_ enabled: Bool) async {
        guard settings.recommendations.localRecommendationsEnabled != enabled else { return }
        settings.recommendations.localRecommendationsEnabled = enabled
        await persistSettings()
    }

    public func updateBetterReleaseNotificationsEnabled(_ enabled: Bool) async {
        guard settings.notifications.betterReleaseNotificationsEnabled != enabled else { return }
        settings.notifications.betterReleaseNotificationsEnabled = enabled
        await persistSettings()
    }

    public func updateBetterReleaseDigestMode(_ enabled: Bool) async {
        guard settings.notifications.betterReleaseDigestMode != enabled else { return }
        settings.notifications.betterReleaseDigestMode = enabled
        await persistSettings()
    }

    public func updateMacOSBetterReleaseNotificationsEnabled(_ enabled: Bool) async {
        guard settings.notifications.macOSBetterReleaseNotificationsEnabled != enabled else { return }
        settings.notifications.macOSBetterReleaseNotificationsEnabled = enabled
        await persistSettings()
    }

    public func updateNotificationCategory(_ category: NotificationCategory, isEnabled: Bool) async {
        guard settings.notifications.isCategoryEnabled(category) != isEnabled else { return }
        settings.notifications.setCategory(category, isEnabled: isEnabled)
        await persistSettings()
    }

    public func updateTasteGenre(_ genre: String, preference: TastePreferenceLevel?) async {
        settings.tasteProfile.setGenre(genre, preference: preference)
        await persistSettings()
    }

    public func restoreHiddenRecommendationItem(mediaID: String) async {
        settings.tasteProfile.restoreHiddenTitle(mediaID: mediaID)
        await persistSettings()
    }

    public func resetHomePreferences() async {
        settings.home = HomePreferences()
        await persistSettings()
    }

    public func updatePreferredAudioLanguages(_ languages: [String]) async {
        settings.playback.preferredAudioLanguages = normalizedLanguages(languages)
        await persistSettings()
    }

    public func updatePreferredAudioOrder(_ order: PreferredAudioOrder) async {
        settings.playback.preferredAudioOrder = order
        await persistSettings()
    }

    public func updatePreferredQuality(_ quality: PreferredQuality) async {
        settings.playback.preferredQuality = quality
        await persistSettings()
    }

    public func updateHDRPreference(_ preference: HDRPreference) async {
        settings.playback.hdrPreference = preference
        await persistSettings()
    }

    public func updateCodecPreference(_ preference: CodecPreference) async {
        settings.playback.codecPreference = preference
        await persistSettings()
    }

    public func updateMaxFileSizeGB(_ value: Double?) async {
        if let value, value > 0 {
            settings.playback.maxFileSizeBytes = Int64(value * 1_000_000_000)
        } else {
            settings.playback.maxFileSizeBytes = nil
        }
        await persistSettings()
    }

    public func updatePreferHighSeedersOverHighestQuality(_ enabled: Bool) async {
        settings.playback.preferHighSeedersOverHighestQuality = enabled
        await persistSettings()
    }

    public func updateHardwareAcceleration(_ enabled: Bool) async {
        settings.playback.hardwareAccelerationEnabled = enabled
        await persistSettings()
    }

    public func updateStartFromLastPosition(_ enabled: Bool) async {
        settings.playback.startFromLastPosition = enabled
        await persistSettings()
    }

    public func updateDefaultFullscreen(_ enabled: Bool) async {
        settings.playback.defaultFullscreen = enabled
        await persistSettings()
    }

    public func updateDimBackgroundAroundVideo(_ enabled: Bool) async {
        settings.playback.dimBackgroundAroundVideo = enabled
        await persistSettings()
    }

    public func updateTimelinePreviewsEnabled(_ enabled: Bool) async {
        settings.playback.enableTimelinePreviews = enabled
        await persistSettings()
    }

    public func updateAutoplayNextEpisode(_ enabled: Bool) async {
        settings.playback.autoplayNextEpisode = enabled
        await persistSettings()
    }

    public func updateRememberedVolume(_ volume: Double) async {
        settings.playback.rememberedVolume = min(max(volume, 0), 1)
        await persistSettings()
    }

    public func updateDefaultPlaybackSpeed(_ speed: Double) async {
        settings.playback.playbackSpeed = min(max(speed, 0.25), 4)
        await persistSettings()
    }

    public func updateAudioBoost(_ boost: Double) async {
        settings.playback.audioBoost = min(max(boost, 1), 2.5)
        await persistSettings()
    }

    public func updateSeekStep(_ seconds: Int) async {
        settings.playback.seekStepSeconds = min(max(seconds, 5), 60)
        await persistSettings()
    }

    public func updateSubtitleLanguages(_ languages: [String]) async {
        subtitleSettings.languagePreference = SubtitleLanguagePreference(normalizedLanguages(languages))
        await environment.settingsRepository.setSubtitleSettings(subtitleSettings)
    }

    public func updateAutoLoadEmbeddedSubtitles(_ enabled: Bool) async {
        subtitleSettings.autoLoadSubtitles = enabled
        await environment.settingsRepository.setSubtitleSettings(subtitleSettings)
    }

    public func updateAutoSearchOpenSubtitles(_ enabled: Bool) async {
        subtitleSettings.autoSearchSubtitles = enabled
        await environment.settingsRepository.setSubtitleSettings(subtitleSettings)
    }

    public func updateSubtitleAutoMode(_ mode: SubtitleAutoMode) async {
        subtitleSettings.autoMode = mode
        await environment.settingsRepository.setSubtitleSettings(subtitleSettings)
    }

    public func updateSubtitleFontSize(_ fontSize: Double) async {
        subtitleSettings.fontSize = min(max(fontSize, 24), 72)
        await environment.settingsRepository.setSubtitleSettings(subtitleSettings)
    }

    public func updateSubtitleDelay(_ seconds: Double) async {
        subtitleSettings.subtitleDelaySeconds = min(max(seconds, -10), 10)
        await environment.settingsRepository.setSubtitleSettings(subtitleSettings)
    }

    public func updateSubtitleVisualStyle(_ style: SubtitleVisualStyle) async {
        subtitleSettings.visualStyle = style
        await environment.settingsRepository.setSubtitleSettings(subtitleSettings)
    }

    public func updateSubtitlePlacement(_ placement: SubtitlePlacement) async {
        subtitleSettings.placement = placement
        await environment.settingsRepository.setSubtitleSettings(subtitleSettings)
    }

    public func updateAutomaticUpdateChecks(_ enabled: Bool) async {
        settings.updates.automaticChecksEnabled = enabled
        await environment.updateService.setAutomaticallyChecksForUpdates(enabled)
        await persistSettings()
    }

    public func updateTorrentCacheFolder(_ url: URL) async {
        guard canUseFolder(url) else {
            operationMessage = "Streamly could not access this folder. Choose a readable location or grant macOS permission."
            return
        }
        settings.storage.torrentCacheFolderPath = url.path
        await persistSettings()
        await refreshCacheSummary()
    }

    public func updateCacheRetentionDays(_ days: Int) async {
        settings.storage.cacheRetentionDays = [7, 14, 30].min(by: { abs($0 - days) < abs($1 - days) }) ?? 30
        await persistSettings()
        await refreshCacheSummary()
    }

    public func updateMaxCacheSizeGB(_ gigabytes: Int) async {
        let bounded = min(max(gigabytes, 1), 512)
        settings.storage.maxCacheSizeBytes = Int64(bounded) * 1_024 * 1_024 * 1_024
        await persistSettings()
        await refreshCacheSummary()
    }

    public func updateKeepUnfinishedCache(_ enabled: Bool) async {
        settings.storage.keepUnfinishedCache = enabled
        await persistSettings()
    }

    public func updateRemoveCompletedCache(_ enabled: Bool) async {
        settings.storage.removeCompletedCache = enabled
        await persistSettings()
    }

    public func updateTorrentDownloadLimitMBps(_ megabytesPerSecond: Int?) async {
        settings.storage.torrentDownloadLimitBytesPerSecond = megabytesPerSecond.map { Int64(max(0, $0)) * 1_024 * 1_024 }
        await persistSettings()
    }

    public func updateTorrentUploadLimitMBps(_ megabytesPerSecond: Int?) async {
        settings.storage.torrentUploadLimitBytesPerSecond = megabytesPerSecond.map { Int64(max(0, $0)) * 1_024 * 1_024 }
        await persistSettings()
    }

    public func chooseTorrentCacheFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for Streamly torrent cache."

        if panel.runModal() == .OK, let url = panel.url {
            Task { await updateTorrentCacheFolder(url) }
        }
    }

    public func saveTMDBCredentials(readAccessToken: String?, apiKey: String?) async {
        guard let keychainService = environment.keychainService else {
            operationMessage = "Keychain is unavailable. TMDB credentials were not saved."
            return
        }

        do {
            try await saveTMDBCredential(
                readAccessToken?.nilIfBlank,
                accountID: TMDBCredentialAccountIDs.readAccessToken,
                keychainService: keychainService
            )
            try await saveTMDBCredential(
                apiKey?.nilIfBlank,
                accountID: TMDBCredentialAccountIDs.apiKey,
                keychainService: keychainService
            )
            await clearLegacyTMDBCredentials()
            operationMessage = "TMDB credentials saved in Keychain."
            await refreshTMDBCredentialSummary()
        } catch {
            await handleSettingsError(error, operation: "saveTMDBCredentials", category: .authentication)
        }
    }

    public func clearTMDBCredentials() async {
        do {
            if let keychainService = environment.keychainService {
                try await keychainService.deleteCredential(accountID: TMDBCredentialAccountIDs.readAccessToken)
                try await keychainService.deleteCredential(accountID: TMDBCredentialAccountIDs.apiKey)
            }
            await clearLegacyTMDBCredentials()
            operationMessage = "TMDB credentials cleared."
            await refreshTMDBCredentialSummary()
        } catch {
            await handleSettingsError(error, operation: "clearTMDBCredentials", category: .authentication)
        }
    }

    public func validateTMDBCredentials() async {
        do {
            _ = try await environment.metadataService.trending()
            tmdbCredentialSummary = TMDBCredentialSummary(
                hasReadAccessToken: tmdbCredentialSummary.hasReadAccessToken,
                hasAPIKey: tmdbCredentialSummary.hasAPIKey,
                lastValidation: "TMDB connection is valid."
            )
            operationMessage = "TMDB connection is valid."
        } catch {
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .authentication)
            tmdbCredentialSummary = TMDBCredentialSummary(
                hasReadAccessToken: tmdbCredentialSummary.hasReadAccessToken,
                hasAPIKey: tmdbCredentialSummary.hasAPIKey,
                lastValidation: cineFlowError.userMessage
            )
            operationMessage = cineFlowError.recoverySuggestion
        }
    }

    public func setSourceEnabled(_ enabled: Bool, sourceID: String) async {
        guard let sourceManager else { return }
        do {
            try await sourceManager.setSourceEnabled(enabled, sourceId: sourceID)
            await refreshSources()
        } catch {
            await handleSettingsError(error, operation: "setSourceEnabled", category: .source, metadata: ["sourceID": sourceID])
        }
    }

    public func authenticateSource(sourceID: String, username: String?, password: String?, cookies: String) async {
        guard let sourceManager else { return }
        do {
            let parsedCookies = Dictionary(
                uniqueKeysWithValues: cookies
                    .split(separator: ";")
                    .compactMap { pair -> (String, String)? in
                        let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        guard parts.count == 2 else { return nil }
                        return (parts[0], parts[1])
                    }
            )
            try await sourceManager.authenticate(
                sourceId: sourceID,
                credentials: SourceCredentials(
                    username: username?.nilIfBlank,
                    password: password?.nilIfBlank,
                    cookies: parsedCookies
                )
            )
            operationMessage = "Source credentials saved in Keychain."
            await refreshSources()
        } catch {
            await handleSettingsError(error, operation: "authenticateSource", category: .authentication, metadata: ["sourceID": sourceID])
        }
    }

    public func testConnection(sourceID: String) async {
        guard let sourceManager else { return }
        do {
            _ = try await sourceManager.testConnection(sourceId: sourceID)
            await refreshSources()
        } catch {
            await handleSettingsError(error, operation: "testConnection", category: .source, metadata: ["sourceID": sourceID])
        }
    }

    public func clearSourceSession(sourceID: String) async {
        guard let sourceManager else { return }
        do {
            try await sourceManager.clearSession(sourceId: sourceID)
            operationMessage = "Source session cleared."
            await refreshSources()
        } catch {
            await handleSettingsError(error, operation: "clearSourceSession", category: .source, metadata: ["sourceID": sourceID])
        }
    }

    public func updateTorrentioProvider(_ provider: TorrentioProviderOption, isSelected: Bool) async {
        var providers = torrentioSettings.providers
        if isSelected {
            providers.append(provider)
        } else {
            providers.removeAll { $0 == provider }
        }
        guard !providers.isEmpty else {
            operationMessage = "Keep at least one Torrentio provider selected."
            return
        }
        torrentioSettings.providers = unique(providers)
        await persistTorrentioSettings()
    }

    public func updateTorrentioPriorityLanguage(_ language: TorrentioPriorityLanguage) async {
        torrentioSettings.priorityLanguage = language
        await persistTorrentioSettings()
    }

    public func updateTorrentioSortMode(_ sortMode: TorrentioSortMode) async {
        torrentioSettings.sortMode = sortMode
        await persistTorrentioSettings()
    }

    public func updateTorrentioExcludedQuality(_ quality: TorrentioExcludedQuality, isExcluded: Bool) async {
        var qualities = torrentioSettings.excludedQualities
        if isExcluded {
            qualities.append(quality)
        } else {
            qualities.removeAll { $0 == quality }
        }
        torrentioSettings.excludedQualities = unique(qualities)
        await persistTorrentioSettings()
    }

    public func updateTorrentioResultLimit(_ limit: Int?) async {
        torrentioSettings.resultLimit = limit.map { min(max($0, 1), 999) }
        await persistTorrentioSettings()
    }

    public func updateTorrentioSizeLimit(_ limit: String) async {
        let trimmed = limit.trimmingCharacters(in: .whitespacesAndNewlines)
        torrentioSettings.sizeLimit = trimmed.isEmpty ? nil : trimmed
        await persistTorrentioSettings()
    }

    public func updateTorrentioDebridProvider(_ provider: TorrentioDebridProvider) async {
        torrentioSettings.debridProvider = provider
        torrentioDebridTokenInput = ""
        if provider == .none {
            try? await torrentioCredentialStore.deleteCredentials(for: "torrentio")
            torrentioDebridTokenConfigured = false
        } else {
            torrentioDebridTokenConfigured = false
        }
        await persistTorrentioSettings()
    }

    public func updateTorrentioDebridOption(_ option: TorrentioDebridOption, isSelected: Bool) async {
        var options = torrentioSettings.debridOptions
        if isSelected {
            options.append(option)
        } else {
            options.removeAll { $0 == option }
        }
        torrentioSettings.debridOptions = unique(options)
        await persistTorrentioSettings()
    }

    public func saveTorrentioDebridToken() async {
        guard torrentioSettings.debridProvider != .none else {
            operationMessage = "Choose a debrid provider first."
            return
        }
        let token = torrentioDebridTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            operationMessage = "Debrid token is empty."
            return
        }

        do {
            _ = try await torrentioCredentialStore.save(
                credentials: SourceCredentials(username: torrentioSettings.debridProvider.rawValue, token: token),
                for: "torrentio"
            )
            torrentioDebridTokenConfigured = true
            torrentioDebridTokenInput = ""
            operationMessage = "Torrentio debrid token saved securely."
        } catch {
            await handleSettingsError(error, operation: "torrentio.debrid.save", category: .source, metadata: ["sourceID": "torrentio"])
        }
    }

    public func clearTorrentioDebridToken() async {
        do {
            try await torrentioCredentialStore.deleteCredentials(for: "torrentio")
            torrentioDebridTokenConfigured = false
            torrentioDebridTokenInput = ""
            operationMessage = "Torrentio debrid token cleared."
        } catch {
            await handleSettingsError(error, operation: "torrentio.debrid.clear", category: .source, metadata: ["sourceID": "torrentio"])
        }
    }

    public func resetTorrentioSettings() async {
        torrentioSettings = .defaults
        torrentioDebridTokenInput = ""
        torrentioDebridTokenConfigured = false
        try? await torrentioCredentialStore.deleteCredentials(for: "torrentio")
        await persistTorrentioSettings()
    }

    public func refreshCacheSummary() async {
        if let smartCacheManager = environment.smartCacheManager {
            do {
                let summary = try await smartCacheManager.summary(
                    policy: settings.storage.smartCachePolicy,
                    scope: cacheScope,
                    protection: await cacheProtection()
                )
                cacheSummary = SettingsCacheSummary(summary: summary)
                return
            } catch {
                await handleSettingsError(error, operation: "cache.summary", category: .cache)
            }
        }

        let imageBytes = try? await environment.imageCacheService?.cacheSizeBytes()
        let torrentBytes = directorySize(cacheScope.torrentCacheURL)
        let subtitleBytes = directorySize(cacheScope.subtitleCacheURL)
        let timelinePreviewBytes = directorySize(cacheScope.timelinePreviewCacheURL)
        cacheSummary = SettingsCacheSummary(
            imageBytes: imageBytes ?? nil,
            torrentBytes: torrentBytes,
            subtitleBytes: subtitleBytes,
            timelinePreviewBytes: timelinePreviewBytes,
            buckets: fallbackCacheBuckets(
                imageBytes: imageBytes,
                torrentBytes: torrentBytes,
                subtitleBytes: subtitleBytes,
                timelinePreviewBytes: timelinePreviewBytes
            ),
            maxSizeBytes: settings.storage.maxCacheSizeBytes
        )
    }

    public func clearImageCache() async {
        do {
            if let smartCacheManager = environment.smartCacheManager {
                _ = try await smartCacheManager.clear(category: .images, scope: cacheScope, protection: await cacheProtection())
            } else {
                try await environment.imageCacheService?.clearAll()
            }
            operationMessage = "Image cache cleared."
            await refreshCacheSummary()
        } catch {
            await handleSettingsError(error, operation: "clearImageCache", category: .cache)
        }
    }

    public func clearTorrentCache() async {
        if let smartCacheManager = environment.smartCacheManager {
            do {
                _ = try await smartCacheManager.clear(category: .torrents, scope: cacheScope, protection: await cacheProtection())
            } catch {
                await handleSettingsError(error, operation: "clearTorrentCache", category: .cache)
                return
            }
        } else {
            clearDirectory(cacheScope.torrentCacheURL)
        }
        operationMessage = "Torrent cache cleared."
        await refreshCacheSummary()
    }

    public func clearSubtitlesCache() async {
        if let smartCacheManager = environment.smartCacheManager {
            do {
                _ = try await smartCacheManager.clear(category: .subtitles, scope: cacheScope, protection: await cacheProtection())
            } catch {
                await handleSettingsError(error, operation: "clearSubtitlesCache", category: .cache)
                return
            }
        } else {
            clearDirectory(cacheScope.subtitleCacheURL)
        }
        operationMessage = "Subtitles cache cleared."
        await refreshCacheSummary()
        await refreshCachedSubtitles()
    }

    public func clearTimelinePreviewCache() async {
        if let smartCacheManager = environment.smartCacheManager {
            do {
                _ = try await smartCacheManager.clear(category: .timelinePreviews, scope: cacheScope, protection: await cacheProtection())
            } catch {
                await handleSettingsError(error, operation: "clearTimelinePreviewCache", category: .cache)
                return
            }
        } else {
            clearDirectory(cacheScope.timelinePreviewCacheURL)
            try? await environment.timelinePreviewService?.clearPreviewCache()
        }
        operationMessage = "Timeline preview cache cleared."
        await refreshCacheSummary()
    }

    public func refreshCachedSubtitles() async {
        do {
            cachedSubtitleItems = try await environment.subtitleService.cachedSubtitles()
        } catch {
            cachedSubtitleItems = []
            await handleSettingsError(error, operation: "subtitles.cached.list", category: .subtitles)
        }
    }

    public func deleteCachedSubtitle(id: String) async {
        do {
            try await environment.subtitleService.deleteCachedSubtitle(id: id)
            operationMessage = "Cached subtitle deleted."
            await refreshCachedSubtitles()
            await refreshCacheSummary()
        } catch {
            await handleSettingsError(error, operation: "subtitles.cached.delete", category: .subtitles, metadata: ["subtitleID": id])
        }
    }

    public func clearMetadataCache() async {
        guard let smartCacheManager = environment.smartCacheManager else {
            operationMessage = "Metadata cache controls are unavailable until the local database is ready."
            return
        }
        do {
            _ = try await smartCacheManager.clear(category: .metadata, scope: cacheScope, protection: await cacheProtection())
            operationMessage = "Metadata cache cleared."
            await refreshCacheSummary()
        } catch {
            await handleSettingsError(error, operation: "clearMetadataCache", category: .cache)
        }
    }

    public func clearAllCache() async {
        if let smartCacheManager = environment.smartCacheManager {
            do {
                let protection = await cacheProtection()
                for category in SmartCacheCategory.allCases {
                    _ = try await smartCacheManager.clear(category: category, scope: cacheScope, protection: protection)
                }
            } catch {
                await handleSettingsError(error, operation: "clearAllCache", category: .cache)
                return
            }
        } else {
            await clearImageCache()
            clearDirectory(cacheScope.torrentCacheURL)
            clearDirectory(cacheScope.subtitleCacheURL)
            clearDirectory(cacheScope.timelinePreviewCacheURL)
        }
        operationMessage = "All cache cleared."
        await refreshCacheSummary()
    }

    public func runCacheAutoClean() async {
        guard let smartCacheManager = environment.smartCacheManager else {
            operationMessage = "Smart cache cleanup is unavailable until the local database is ready."
            return
        }
        do {
            let result = try await smartCacheManager.runAutoClean(
                policy: settings.storage.smartCachePolicy,
                scope: cacheScope,
                protection: await cacheProtection()
            )
            operationMessage = "Smart cleanup removed \(result.removedItemCount) items and freed \(cacheLabel(result.freedBytes))."
            await refreshCacheSummary()
        } catch {
            await handleSettingsError(error, operation: "cache.autoClean", category: .cache)
        }
    }

    public func clearTitleCache(itemID: String) async {
        guard let smartCacheManager = environment.smartCacheManager else { return }
        do {
            let result = try await smartCacheManager.clearTitleCache(
                itemID: itemID,
                scope: cacheScope,
                protection: await cacheProtection()
            )
            operationMessage = result.protectedItemCount > 0
                ? "This cache item is protected while playback is active or marked to keep."
                : "Cached data cleared."
            await refreshCacheSummary()
        } catch {
            await handleSettingsError(error, operation: "cache.clearTitle", category: .cache, metadata: ["itemID": itemID])
        }
    }

    public func setTitleCacheKeepForLater(itemID: String, keep: Bool) async {
        guard let smartCacheManager = environment.smartCacheManager else { return }
        do {
            try await smartCacheManager.setKeepForLater(itemID: itemID, keep: keep)
            operationMessage = keep ? "Cache item kept for later." : "Cache item can be cleaned automatically."
            await refreshCacheSummary()
        } catch {
            await handleSettingsError(error, operation: "cache.keepForLater", category: .cache, metadata: ["itemID": itemID])
        }
    }

    public func checkForUpdates() async {
        isBusy = true
        updateStatus = .checking
        updateStatus = await environment.updateService.checkForUpdates()
        lastUpdateCheckedAt = await environment.updateService.lastCheckedAt
        if case .failed(let message) = updateStatus {
            await environment.diagnosticsService.log(
                level: .warning,
                subsystem: .update,
                message: message,
                metadata: ["operation": "checkForUpdates"]
            )
        }
        isBusy = false
    }

    public func exportDiagnostics() async {
        diagnosticsExport = await environment.diagnosticsService.exportDiagnostics()
    }

    public func exportLibrary() async {
        guard let portabilityService = environment.libraryPortabilityService else {
            operationMessage = "Library export is unavailable without the local database."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let data = try await portabilityService.exportLibraryJSON()
            let panel = NSSavePanel()
            panel.title = "Export Library"
            panel.nameFieldStringValue = "streamly-library-\(portableTimestamp()).json"
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true

            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url, options: .atomic)
                operationMessage = "Library exported to \(url.lastPathComponent)."
            } else {
                operationMessage = "Library export cancelled."
            }
        } catch {
            await handleSettingsError(error, operation: "library.export", category: .database, metadata: [:])
        }
    }

    public func chooseLibraryImportFile() async {
        guard let portabilityService = environment.libraryPortabilityService else {
            operationMessage = "Library import is unavailable without the local database."
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Import Library"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else {
            operationMessage = "Library import cancelled."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let data = try Data(contentsOf: url)
            let preview = try await portabilityService.previewImport(data)
            pendingLibraryImportData = data
            libraryImportPreview = preview
            operationMessage = preview.canImport
                ? "Import preview ready: \(libraryImportSummaryText(preview.summary)); \(preview.duplicateCount) duplicate records will be merged."
                : "Import file has validation issues. Review the preview before importing."
        } catch {
            pendingLibraryImportData = nil
            libraryImportPreview = nil
            await handleSettingsError(error, operation: "library.importPreview", category: .database, metadata: ["file": url.lastPathComponent])
        }
    }

    public func confirmLibraryImport() async {
        guard let portabilityService = environment.libraryPortabilityService, let data = pendingLibraryImportData else {
            operationMessage = "Choose a library JSON file before importing."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let result = try await portabilityService.importLibraryJSON(
                data,
                options: LibraryImportOptions(createBackupBeforeImport: backupBeforeLibraryImport)
            )
            let backupSuffix: String
            if let backupData = result.backupData {
                let backupURL = try writeLibraryImportBackup(backupData)
                backupSuffix = " Backup saved as \(backupURL.lastPathComponent)."
            } else {
                backupSuffix = ""
            }
            operationMessage = "Library imported: \(libraryImportSummaryText(result.preview.summary)); \(result.preview.duplicateCount) duplicate records merged.\(backupSuffix)"
            pendingLibraryImportData = nil
            libraryImportPreview = nil
        } catch {
            await handleSettingsError(error, operation: "library.import", category: .database, metadata: [:])
        }
    }

    public func cancelLibraryImport() {
        pendingLibraryImportData = nil
        libraryImportPreview = nil
        operationMessage = "Library import cancelled."
    }

    public func openLogsFolder() {
        operationMessage = "Logs folder: \(cacheBaseURL.appendingPathComponent("Logs", isDirectory: true).path)"
    }

    public func clearLogs() {
        clearDirectory(cacheBaseURL.appendingPathComponent("Logs", isDirectory: true))
        operationMessage = "Logs cleared."
    }

    public func clearAllLocalData() async {
        await clearAllCache()
        try? await environment.keychainService?.deleteAllCineFlowCredentials()
        await environment.settingsRepository.clearAllLocalData()
        settings = AppSettings()
        subtitleSettings = SubtitleSettings()
        cachedSubtitleItems = []
        operationMessage = "Local settings, history, library data and caches cleared."
    }

    public func cacheLabel(_ bytes: Int64?) -> String {
        guard let bytes else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func refreshSources() async {
        guard let sourceManager else {
            sourceRows = []
            return
        }

        var rows: [SettingsSourceRow] = []
        for descriptor in await sourceManager.providerDescriptors() {
            if let settings = try? await sourceManager.settings(for: descriptor.sourceId) {
                rows.append(
                    SettingsSourceRow(
                        id: descriptor.sourceId,
                        displayName: descriptor.displayName,
                        requiresAuthentication: descriptor.requiresAuthentication,
                        settings: settings
                    )
                )
            }
        }
        sourceRows = rows
    }

    private func refreshTMDBCredentialSummary() async {
        let readAccessToken = await tmdbCredentialValue(
            accountID: TMDBCredentialAccountIDs.readAccessToken,
            legacyKey: MetadataCredentialKeys.tmdbReadAccessToken
        )
        let apiKey = await tmdbCredentialValue(
            accountID: TMDBCredentialAccountIDs.apiKey,
            legacyKey: MetadataCredentialKeys.tmdbAPIKey
        )
        tmdbCredentialSummary = TMDBCredentialSummary(
            hasReadAccessToken: readAccessToken?.nilIfBlank != nil,
            hasAPIKey: apiKey?.nilIfBlank != nil,
            lastValidation: tmdbCredentialSummary.lastValidation
        )
    }

    private func saveTMDBCredential(
        _ value: String?,
        accountID: String,
        keychainService: any KeychainServiceProtocol
    ) async throws {
        guard let value else {
            try await keychainService.deleteCredential(accountID: accountID)
            return
        }

        _ = try await keychainService.saveCredential(
            KeychainCredential(
                accountID: accountID,
                kind: .apiToken,
                sourceID: "tmdb",
                token: value
            )
        )
    }

    private func tmdbCredentialValue(accountID: String, legacyKey: String) async -> String? {
        if let keychainService = environment.keychainService,
           let credential = try? await keychainService.readCredential(accountID: accountID),
           let token = credential.token?.nilIfBlank {
            return token
        }

        let legacyValue = await environment.settingsRepository.metadataCredential(forKey: legacyKey)
        guard let legacyValue = legacyValue?.nilIfBlank,
              let keychainService = environment.keychainService
        else {
            return nil
        }

        try? await saveTMDBCredential(legacyValue, accountID: accountID, keychainService: keychainService)
        await environment.settingsRepository.setMetadataCredential(nil, forKey: legacyKey)
        return legacyValue
    }

    private func clearLegacyTMDBCredentials() async {
        await environment.settingsRepository.setMetadataCredential(nil, forKey: MetadataCredentialKeys.tmdbReadAccessToken)
        await environment.settingsRepository.setMetadataCredential(nil, forKey: MetadataCredentialKeys.tmdbAPIKey)
    }

    private func refreshTorrentioSettings() async {
        do {
            torrentioSettings = try await torrentioSettingsStore.settings()
        } catch {
            torrentioSettings = .defaults
            await handleSettingsError(error, operation: "refreshTorrentioSettings", category: .source, metadata: ["sourceID": "torrentio"])
        }
    }

    private func refreshTorrentioDebridCredentials() async {
        guard torrentioSettings.debridProvider != .none else {
            torrentioDebridTokenConfigured = false
            torrentioDebridTokenInput = ""
            return
        }
        do {
            let credentials = try await torrentioCredentialStore.credentials(for: "torrentio")
            torrentioDebridTokenConfigured = credentials?.token?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            torrentioDebridTokenInput = ""
        } catch {
            torrentioDebridTokenConfigured = false
            await handleSettingsError(error, operation: "torrentio.debrid.refresh", category: .source, metadata: ["sourceID": "torrentio"])
        }
    }

    private func persistSettings() async {
        await environment.settingsRepository.setAppSettings(settings)
    }

    private func persistTorrentioSettings() async {
        do {
            try await torrentioSettingsStore.save(torrentioSettings)
            operationMessage = "Torrentio settings saved locally."
        } catch {
            await handleSettingsError(error, operation: "persistTorrentioSettings", category: .source, metadata: ["sourceID": "torrentio"])
        }
    }

    private func normalizedLanguages(_ languages: [String]) -> [String] {
        let normalized = languages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? ["ru", "en"] : Array(NSOrderedSet(array: normalized)) as? [String] ?? normalized
    }

    private func unique<Value: Hashable>(_ values: [Value]) -> [Value] {
        var seen = Set<Value>()
        return values.filter { seen.insert($0).inserted }
    }

    private var cacheScope: SmartCacheScope {
        SmartCacheScope(
            torrentCacheURL: URL(fileURLWithPath: settings.storage.torrentCacheFolderPath, isDirectory: true),
            subtitleCacheURL: cacheBaseURL.appendingPathComponent("Subtitles", isDirectory: true),
            timelinePreviewCacheURL: cacheBaseURL.appendingPathComponent("TimelinePreviews", isDirectory: true)
        )
    }

    private func cacheProtection() async -> SmartCacheProtection {
        let status = await environment.playbackService.currentStatus
        var urls: [URL] = []
        var ids: [String] = []
        if let media = status.media {
            urls.append(media.url)
            ids.append(media.id)
            if let release = media.release {
                ids.append(release.id)
                if let torrentFileURL = release.torrentFileURL {
                    urls.append(torrentFileURL)
                }
            }
        }
        return SmartCacheProtection(activeFileURLs: urls, activeIDs: ids)
    }

    private func fallbackCacheBuckets(
        imageBytes: Int64?,
        torrentBytes: Int64,
        subtitleBytes: Int64,
        timelinePreviewBytes: Int64
    ) -> [SmartCacheBucketSummary] {
        [
            SmartCacheBucketSummary(category: .images, sizeBytes: imageBytes ?? 0),
            SmartCacheBucketSummary(category: .torrents, sizeBytes: torrentBytes, path: cacheScope.torrentCacheURL.path),
            SmartCacheBucketSummary(category: .subtitles, sizeBytes: subtitleBytes, path: cacheScope.subtitleCacheURL.path),
            SmartCacheBucketSummary(category: .timelinePreviews, sizeBytes: timelinePreviewBytes, path: cacheScope.timelinePreviewCacheURL.path),
            SmartCacheBucketSummary(category: .metadata, sizeBytes: 0)
        ]
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return enumerator.reduce(Int64(0)) { partial, item in
            guard
                let fileURL = item as? URL,
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true
            else {
                return partial
            }
            return partial + Int64(values.fileSize ?? 0)
        }
    }

    private func clearDirectory(_ url: URL) {
        try? fileManager.removeItem(at: url)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func canUseFolder(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true else {
            return false
        }
        return fileManager.isReadableFile(atPath: url.path)
    }

    private func handleSettingsError(
        _ error: Error,
        operation: String,
        category: CineFlowErrorCategory,
        metadata: [String: String] = [:]
    ) async {
        let cineFlowError = CineFlowError.from(error, fallbackCategory: category)
        await environment.diagnosticsService.log(cineFlowError, operation: operation, metadata: metadata)
        operationMessage = cineFlowError.userMessage
    }

    private func writeLibraryImportBackup(_ data: Data) throws -> URL {
        let directory = cacheBaseURL.appendingPathComponent("LibraryBackups", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("streamly-library-backup-\(portableTimestamp()).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func libraryImportSummaryText(_ summary: LibraryImportSummary) -> String {
        "\(summary.libraryItems) library, \(summary.lists) lists, \(summary.watchHistory) history, \(summary.ratings) ratings, \(summary.playbackProgress) progress"
    }

    private func portableTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    private static func defaultCacheBaseURL(fileManager: FileManager) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Streamly", isDirectory: true)
    }
}

private extension SettingsCacheSummary {
    init(summary: SmartCacheSummary) {
        self.init(
            imageBytes: summary.buckets.first(where: { $0.category == .images })?.sizeBytes,
            torrentBytes: summary.buckets.first(where: { $0.category == .torrents })?.sizeBytes ?? 0,
            subtitleBytes: summary.buckets.first(where: { $0.category == .subtitles })?.sizeBytes ?? 0,
            timelinePreviewBytes: summary.buckets.first(where: { $0.category == .timelinePreviews })?.sizeBytes ?? 0,
            metadataBytes: summary.buckets.first(where: { $0.category == .metadata })?.sizeBytes ?? 0,
            buckets: summary.buckets,
            titleItems: summary.titleItems,
            maxSizeBytes: summary.maxSizeBytes
        )
    }
}

private enum MetadataCredentialKeys {
    static let tmdbReadAccessToken = "tmdb_read_access_token"
    static let tmdbAPIKey = "tmdb_api_key"
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
