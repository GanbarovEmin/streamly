import CineFlowCore
import Foundation

public struct MockDiagnosticsService: DiagnosticsServiceProtocol {
    public init() {}

    public func log(level: DiagnosticsLogLevel, subsystem: DiagnosticsSubsystem, message: String, metadata: [String: String]) async {}

    public func exportDiagnostics() async -> String {
        "Streamly diagnostics: mock services active; torrent/playback engines are not initialized."
    }

    public func exportDiagnosticsPackage() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Streamly-Mock-Diagnostics")
            .appendingPathExtension("zip")
        try Data("mock diagnostics".utf8).write(to: url)
        return url
    }

    public func recentEvents(limit: Int) async -> [DiagnosticsEvent] {
        []
    }
}
