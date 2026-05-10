import CineFlowCore
import Foundation
import XCTest
@testable import CineFlowDiagnostics

final class DiagnosticsServiceTests: XCTestCase {
    func testLocalLoggerWritesSanitizedLogsToApplicationSupportLogsFolder() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let service = LocalDiagnosticsService(baseDirectory: workspace)

        await service.log(
            level: .error,
            subsystem: .metadata,
            message: "TMDB token=secret-token failed for https://api.example.test/movie?api_key=secret&session=private",
            metadata: ["password": "secret-password", "safe": "visible"]
        )
        await service.log(
            level: .warning,
            subsystem: .source,
            message: #"{"token":"json-secret","status":"failed"}"#
        )

        let logURL = workspace.appendingPathComponent("Logs/streamly.log")
        let logBody = try String(contentsOf: logURL)

        XCTAssertTrue(logURL.path.contains("Logs"))
        XCTAssertTrue(logBody.contains("metadata"))
        XCTAssertTrue(logBody.contains("visible"))
        XCTAssertFalse(logBody.contains("secret-token"))
        XCTAssertFalse(logBody.contains("secret-password"))
        XCTAssertFalse(logBody.contains("api_key=secret"))
        XCTAssertFalse(logBody.contains("session=private"))
        XCTAssertFalse(logBody.contains("json-secret"))
        XCTAssertTrue(logBody.contains(#""token":"[REDACTED]""#))
    }

    func testLocalLoggerRedactsHeadersPrivateURLsAndMagnetLinks() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let service = LocalDiagnosticsService(baseDirectory: workspace)

        await service.log(
            level: .warning,
            subsystem: .source,
            message: "https://user:pass@example.test/feed?token=url-token&quality=1080p Authorization: Bearer live-token Cookie: sid=session-cookie magnet:?xt=urn:btih:privatehash",
            metadata: [
                "sourceURL": "https://example.test/manifest?api_key=query-secret&public=ok",
                "authorizationHeader": "Bearer metadata-token",
                "magnetURI": "magnet:?xt=urn:btih:metadataprivatehash"
            ]
        )

        let logURL = workspace.appendingPathComponent("Logs/streamly.log")
        let logBody = try String(contentsOf: logURL)

        XCTAssertFalse(logBody.contains("live-token"))
        XCTAssertFalse(logBody.contains("session-cookie"))
        XCTAssertFalse(logBody.contains("user:pass"))
        XCTAssertFalse(logBody.contains("url-token"))
        XCTAssertFalse(logBody.contains("privatehash"))
        XCTAssertFalse(logBody.contains("query-secret"))
        XCTAssertFalse(logBody.contains("metadata-token"))
        XCTAssertFalse(logBody.contains("metadataprivatehash"))
        XCTAssertTrue(logBody.contains("quality=1080p"))
        XCTAssertTrue(logBody.contains("public=ok"))
        XCTAssertTrue(logBody.contains("[REDACTED]"))
        XCTAssertTrue(logBody.contains("[REDACTED_MAGNET]"))
    }

    func testExportDiagnosticsCreatesZipPackageWithoutSecrets() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let service = LocalDiagnosticsService(
            baseDirectory: workspace,
            appVersion: "1.2.3",
            build: "456",
            settingsSummaryProvider: {
                DiagnosticsSettingsSummary(language: "ru", telemetryEnabled: false, sourceCount: 2)
            },
            cacheSummaryProvider: {
                DiagnosticsCacheSummary(imageBytes: 10, torrentBytes: 20, subtitlesBytes: 30)
            },
            databaseSchemaVersionProvider: { "v7" }
        )

        await service.log(level: .critical, subsystem: .playback, message: "Playback token=private-token failed")

        let zipURL = try await service.exportDiagnosticsPackage()
        let unzippedURL = workspace.appendingPathComponent("unzipped", isDirectory: true)
        try FileManager.default.createDirectory(at: unzippedURL, withIntermediateDirectories: true)
        try unzip(zipURL, to: unzippedURL)

        let summary = try String(contentsOf: unzippedURL.appendingPathComponent("diagnostics/summary.json"))
        let exportedLog = try String(contentsOf: unzippedURL.appendingPathComponent("diagnostics/logs/streamly.log"))

        XCTAssertEqual(zipURL.pathExtension, "zip")
        XCTAssertTrue(summary.contains(#""appVersion":"1.2.3""#))
        XCTAssertTrue(summary.contains(#""macOSVersion""#))
        XCTAssertTrue(summary.contains(#""architecture""#))
        XCTAssertTrue(summary.contains(#""databaseSchemaVersion":"v7""#))
        XCTAssertTrue(summary.contains(#""telemetryEnabled":false"#))
        XCTAssertFalse(summary.contains("private-token"))
        XCTAssertFalse(exportedLog.contains("private-token"))
        XCTAssertTrue(exportedLog.contains("[REDACTED]"))
    }

    func testLocalLoggerMigratesLegacyCineFlowLogToStreamlyLog() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let logsURL = workspace.appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        try Data("legacy log line\n".utf8).write(to: logsURL.appendingPathComponent("cineflow.log"))

        let service = LocalDiagnosticsService(baseDirectory: workspace)
        await service.log(level: .info, subsystem: .app, message: "new log line")

        let streamlyLogURL = logsURL.appendingPathComponent("streamly.log")
        let logBody = try String(contentsOf: streamlyLogURL)
        XCTAssertTrue(logBody.contains("legacy log line"))
        XCTAssertTrue(logBody.contains("new log line"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: logsURL.appendingPathComponent("cineflow.log").path))
    }

    private func unzip(_ zipURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipURL.path, "-d", destinationURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
