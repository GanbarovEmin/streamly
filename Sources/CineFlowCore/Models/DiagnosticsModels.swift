import Foundation

public enum DiagnosticsLogLevel: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case warning
    case error
    case critical
}

public enum DiagnosticsSubsystem: String, Codable, CaseIterable, Sendable {
    case app
    case metadata
    case source
    case torrent
    case playback
    case subtitle
    case update
    case settings
    case database
}

public struct DiagnosticsEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let level: DiagnosticsLogLevel
    public let subsystem: DiagnosticsSubsystem
    public let message: String
    public let metadata: [String: String]
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        level: DiagnosticsLogLevel,
        subsystem: DiagnosticsSubsystem,
        message: String,
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.level = level
        self.subsystem = subsystem
        self.message = message
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public struct DiagnosticsSettingsSummary: Codable, Equatable, Sendable {
    public let language: String
    public let telemetryEnabled: Bool
    public let sourceCount: Int

    public init(language: String, telemetryEnabled: Bool, sourceCount: Int) {
        self.language = language
        self.telemetryEnabled = telemetryEnabled
        self.sourceCount = sourceCount
    }
}

public struct DiagnosticsCacheSummary: Codable, Equatable, Sendable {
    public let imageBytes: Int64
    public let torrentBytes: Int64
    public let subtitlesBytes: Int64

    public init(imageBytes: Int64 = 0, torrentBytes: Int64 = 0, subtitlesBytes: Int64 = 0) {
        self.imageBytes = imageBytes
        self.torrentBytes = torrentBytes
        self.subtitlesBytes = subtitlesBytes
    }
}

public struct DiagnosticsPackageSummary: Codable, Equatable, Sendable {
    public let appVersion: String
    public let build: String
    public let macOSVersion: String
    public let architecture: String
    public let settings: DiagnosticsSettingsSummary
    public let databaseSchemaVersion: String
    public let cache: DiagnosticsCacheSummary
    public let recentErrorEvents: [DiagnosticsEvent]

    public init(
        appVersion: String,
        build: String,
        macOSVersion: String,
        architecture: String,
        settings: DiagnosticsSettingsSummary,
        databaseSchemaVersion: String,
        cache: DiagnosticsCacheSummary,
        recentErrorEvents: [DiagnosticsEvent]
    ) {
        self.appVersion = appVersion
        self.build = build
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.settings = settings
        self.databaseSchemaVersion = databaseSchemaVersion
        self.cache = cache
        self.recentErrorEvents = recentErrorEvents
    }
}
