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

        let logURL = workspace.appendingPathComponent("Logs/cineflow.log")
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
        let exportedLog = try String(contentsOf: unzippedURL.appendingPathComponent("diagnostics/logs/cineflow.log"))

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

    private func unzip(_ zipURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipURL.path, "-d", destinationURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
