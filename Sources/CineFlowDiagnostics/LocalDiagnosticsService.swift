import CineFlowCore
import Foundation

public enum DiagnosticsServiceError: LocalizedError, Equatable, Sendable {
    case exportFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .exportFailed(let status):
            "Diagnostics export failed with status \(status)."
        }
    }
}

public actor LocalDiagnosticsService: DiagnosticsServiceProtocol {
    private let baseDirectory: URL
    private let logsDirectory: URL
    private let exportsDirectory: URL
    private let appVersion: String
    private let build: String
    private let settingsSummaryProvider: @Sendable () -> DiagnosticsSettingsSummary
    private let cacheSummaryProvider: @Sendable () -> DiagnosticsCacheSummary
    private let databaseSchemaVersionProvider: @Sendable () -> String
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    private var events: [DiagnosticsEvent] = []

    public init(
        baseDirectory: URL? = nil,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
        build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev",
        settingsSummaryProvider: @escaping @Sendable () -> DiagnosticsSettingsSummary = {
            DiagnosticsSettingsSummary(language: "system", telemetryEnabled: false, sourceCount: 0)
        },
        cacheSummaryProvider: @escaping @Sendable () -> DiagnosticsCacheSummary = {
            DiagnosticsCacheSummary()
        },
        databaseSchemaVersionProvider: @escaping @Sendable () -> String = {
            "current"
        },
        fileManager: FileManager = .default
    ) {
        let resolvedBaseDirectory = baseDirectory ?? LocalDiagnosticsService.defaultBaseDirectory()
        self.baseDirectory = resolvedBaseDirectory
        logsDirectory = resolvedBaseDirectory.appendingPathComponent("Logs", isDirectory: true)
        exportsDirectory = resolvedBaseDirectory.appendingPathComponent("DiagnosticsExports", isDirectory: true)
        self.appVersion = appVersion
        self.build = build
        self.settingsSummaryProvider = settingsSummaryProvider
        self.cacheSummaryProvider = cacheSummaryProvider
        self.databaseSchemaVersionProvider = databaseSchemaVersionProvider
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    public func log(
        level: DiagnosticsLogLevel,
        subsystem: DiagnosticsSubsystem,
        message: String,
        metadata: [String: String] = [:]
    ) async {
        let event = DiagnosticsEvent(
            level: level,
            subsystem: subsystem,
            message: Self.sanitize(message),
            metadata: Self.sanitizedMetadata(metadata)
        )
        events.append(event)
        if events.count > 500 {
            events.removeFirst(events.count - 500)
        }

        do {
            try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            let line = try logLine(for: event)
            let logURL = logsDirectory.appendingPathComponent("cineflow.log")
            if fileManager.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try Data(line.utf8).write(to: logURL)
            }
        } catch {
            // Logging must never interrupt app flow.
        }
    }

    public func exportDiagnostics() async -> String {
        do {
            return try await exportDiagnosticsPackage().path
        } catch {
            return "CineFlow diagnostics export failed: \(error.localizedDescription)"
        }
    }

    public func exportDiagnosticsPackage() async throws -> URL {
        try fileManager.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
        let stagingURL = exportsDirectory.appendingPathComponent("diagnostics", isDirectory: true)
        try? fileManager.removeItem(at: stagingURL)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        let logsExportURL = stagingURL.appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(at: logsExportURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: logsDirectory.path) {
            let logFiles = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)
            for file in logFiles where file.lastPathComponent.hasSuffix(".log") {
                try fileManager.copyItem(at: file, to: logsExportURL.appendingPathComponent(file.lastPathComponent))
            }
        }

        let summary = DiagnosticsPackageSummary(
            appVersion: appVersion,
            build: build,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.architecture,
            settings: settingsSummaryProvider(),
            databaseSchemaVersion: databaseSchemaVersionProvider(),
            cache: cacheSummaryProvider(),
            recentErrorEvents: recentEventsSnapshot(limit: 25)
        )
        try encoder.encode(summary).write(to: stagingURL.appendingPathComponent("summary.json"))

        let zipURL = exportsDirectory.appendingPathComponent("CineFlow-Diagnostics-\(Self.timestamp()).zip")
        try? fileManager.removeItem(at: zipURL)
        try zip(stagingURL: stagingURL, outputURL: zipURL)
        return zipURL
    }

    public func recentEvents(limit: Int = 20) async -> [DiagnosticsEvent] {
        recentEventsSnapshot(limit: limit)
    }

    private func recentEventsSnapshot(limit: Int) -> [DiagnosticsEvent] {
        events
            .filter { [.error, .critical, .warning].contains($0.level) }
            .suffix(limit)
    }

    private func logLine(for event: DiagnosticsEvent) throws -> String {
        let metadataJSON = String(data: try encoder.encode(event.metadata), encoding: .utf8) ?? "{}"
        let timestamp = ISO8601DateFormatter().string(from: event.createdAt)
        return "\(timestamp) [\(event.level.rawValue.uppercased())] \(event.subsystem.rawValue): \(event.message) \(metadataJSON)\n"
    }

    private func zip(stagingURL: URL, outputURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = stagingURL.deletingLastPathComponent()
        process.arguments = ["-qry", outputURL.path, stagingURL.lastPathComponent]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DiagnosticsServiceError.exportFailed(process.terminationStatus)
        }
    }

    public static func sanitize(_ value: String) -> String {
        var sanitized = value
        sanitized = sanitized.replacingOccurrences(
            of: #"(?i)(password|passwd|pwd|token|access_token|refresh_token|api_key|apikey|cookie|session)=([^&\s]+)"#,
            with: "$1=[REDACTED]",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"(?i)("?(password|token|cookie|apiKey|api_key|session)"?\s*:\s*")([^"]+)(")"#,
            with: "$1[REDACTED]$4",
            options: .regularExpression
        )
        return sanitized
    }

    private static func sanitizedMetadata(_ metadata: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: metadata.map { key, value in
            if key.range(of: #"(?i)(password|token|cookie|api_key|session)"#, options: .regularExpression) != nil {
                return (key, "[REDACTED]")
            }
            return (key, sanitize(value))
        })
    }

    private static func defaultBaseDirectory(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupport.appendingPathComponent("CineFlow", isDirectory: true)
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
    }
}
