import CineFlowCore
import CineFlowSources
import AppKit
import Foundation

public enum SettingsSectionID: String, CaseIterable, Identifiable, Sendable {
    case general
    case appearance
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

    public init(imageBytes: Int64? = nil, torrentBytes: Int64 = 0, subtitleBytes: Int64 = 0) {
        self.imageBytes = imageBytes
        self.torrentBytes = torrentBytes
        self.subtitleBytes = subtitleBytes
    }

    public var totalBytes: Int64 {
        (imageBytes ?? 0) + torrentBytes + subtitleBytes
    }
}

public struct SettingsAboutInfo: Equatable, Sendable {
    public let appName: String
    public let version: String
    public let build: String
    public let credits: String
    public let licenses: String

    public init(
        appName: String = "CineFlow",
        version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
        build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev",
        credits: String = "CineFlow contributors",
        licenses: String = "Open-source dependencies are listed in the package manifest."
    ) {
        self.appName = appName
        self.version = version
        self.build = build
        self.credits = credits
        self.licenses = licenses
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
    @Published public private(set) var updateStatus: UpdateStatus = .idle
    @Published public private(set) var lastUpdateCheckedAt: Date?
    @Published public private(set) var diagnosticsExport: String?
    @Published public private(set) var operationMessage: String?
    @Published public private(set) var isBusy = false

    public let about: SettingsAboutInfo

    private let environment: AppEnvironment
    private let sourceManager: SourceManager?
    private let fileManager: FileManager
    private let cacheBaseURL: URL

    public init(
        environment: AppEnvironment,
        sourceManager: SourceManager? = nil,
        fileManager: FileManager = .default,
        cacheBaseURL: URL? = nil,
        about: SettingsAboutInfo = SettingsAboutInfo()
    ) {
        self.environment = environment
        self.sourceManager = sourceManager
        self.fileManager = fileManager
        self.cacheBaseURL = cacheBaseURL ?? Self.defaultCacheBaseURL(fileManager: fileManager)
        self.about = about
    }

    public func load() async {
        settings = await environment.settingsRepository.appSettings
        subtitleSettings = await environment.settingsRepository.subtitleSettings
        updateStatus = await environment.updateService.currentStatus
        settings.updates.automaticChecksEnabled = await environment.updateService.automaticallyChecksForUpdates
        lastUpdateCheckedAt = await environment.updateService.lastCheckedAt
        await refreshSources()
        await refreshCacheSummary()
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
        await persistSettings()
    }

    public func updatePreferredAudioLanguages(_ languages: [String]) async {
        settings.playback.preferredAudioLanguages = normalizedLanguages(languages)
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

    public func updateSubtitleFontSize(_ fontSize: Double) async {
        subtitleSettings.fontSize = min(max(fontSize, 24), 72)
        await environment.settingsRepository.setSubtitleSettings(subtitleSettings)
    }

    public func updateSubtitleDelay(_ seconds: Double) async {
        subtitleSettings.subtitleDelaySeconds = min(max(seconds, -10), 10)
        await environment.settingsRepository.setSubtitleSettings(subtitleSettings)
    }

    public func updateAutomaticUpdateChecks(_ enabled: Bool) async {
        settings.updates.automaticChecksEnabled = enabled
        await environment.updateService.setAutomaticallyChecksForUpdates(enabled)
        await persistSettings()
    }

    public func updateTorrentCacheFolder(_ url: URL) async {
        guard canUseFolder(url) else {
            operationMessage = "CineFlow could not access this folder. Choose a readable location or grant macOS permission."
            return
        }
        settings.storage.torrentCacheFolderPath = url.path
        await persistSettings()
    }

    public func chooseTorrentCacheFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for CineFlow torrent cache."

        if panel.runModal() == .OK, let url = panel.url {
            Task { await updateTorrentCacheFolder(url) }
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

    public func refreshCacheSummary() async {
        let imageBytes = try? await environment.imageCacheService?.cacheSizeBytes()
        cacheSummary = SettingsCacheSummary(
            imageBytes: imageBytes ?? nil,
            torrentBytes: directorySize(cacheBaseURL.appendingPathComponent("TorrentCache", isDirectory: true)),
            subtitleBytes: directorySize(cacheBaseURL.appendingPathComponent("Subtitles", isDirectory: true))
        )
    }

    public func clearImageCache() async {
        do {
            try await environment.imageCacheService?.clearAll()
            operationMessage = "Image cache cleared."
            await refreshCacheSummary()
        } catch {
            await handleSettingsError(error, operation: "clearImageCache", category: .cache)
        }
    }

    public func clearTorrentCache() async {
        clearDirectory(cacheBaseURL.appendingPathComponent("TorrentCache", isDirectory: true))
        operationMessage = "Torrent cache cleared."
        await refreshCacheSummary()
    }

    public func clearSubtitlesCache() async {
        clearDirectory(cacheBaseURL.appendingPathComponent("Subtitles", isDirectory: true))
        operationMessage = "Subtitles cache cleared."
        await refreshCacheSummary()
    }

    public func clearAllCache() async {
        await clearImageCache()
        clearDirectory(cacheBaseURL.appendingPathComponent("TorrentCache", isDirectory: true))
        clearDirectory(cacheBaseURL.appendingPathComponent("Subtitles", isDirectory: true))
        operationMessage = "All cache cleared."
        await refreshCacheSummary()
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

    private func persistSettings() async {
        await environment.settingsRepository.setAppSettings(settings)
    }

    private func normalizedLanguages(_ languages: [String]) -> [String] {
        let normalized = languages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? ["ru", "en"] : Array(NSOrderedSet(array: normalized)) as? [String] ?? normalized
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

    private static func defaultCacheBaseURL(fileManager: FileManager) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("CineFlow", isDirectory: true)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
