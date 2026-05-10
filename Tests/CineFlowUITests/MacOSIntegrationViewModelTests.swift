import CineFlowCore
import XCTest
@testable import CineFlowUI

@MainActor
final class MacOSIntegrationViewModelTests: XCTestCase {
    func testHandlesMagnetTextTorrentFilesAndOpenURLRouting() async throws {
        let engine = RecordingTorrentEngine()
        let viewModel = MacOSIntegrationViewModel(environment: AppEnvironment(
            metadataService: CoreMockMetadataService(),
            torrentEngine: engine,
            playbackService: CoreMockPlaybackService(),
            subtitleService: CoreMockSubtitleService(),
            libraryRepository: CoreMockLibraryRepository(),
            settingsRepository: CoreMockSettingsRepository(),
            diagnosticsService: CoreMockDiagnosticsService(),
            updateService: CoreMockUpdateService()
        ))
        let torrentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("torrent")
        try Data("torrent fixture".utf8).write(to: torrentURL)
        defer { try? FileManager.default.removeItem(at: torrentURL) }

        await viewModel.handleDroppedText("  magnet:?xt=urn:btih:drop  ")
        await viewModel.handleOpenURL(torrentURL)
        await viewModel.handleOpenURL(URL(string: "magnet:?xt=urn:btih:open")!)

        let addedMagnets = await engine.recordedMagnets()
        let addedTorrentFiles = await engine.recordedTorrentFiles()
        XCTAssertEqual(addedMagnets, ["magnet:?xt=urn:btih:drop", "magnet:?xt=urn:btih:open"])
        XCTAssertEqual(addedTorrentFiles.map(\.lastPathComponent), [torrentURL.lastPathComponent])
        XCTAssertEqual(viewModel.lastImportedSession?.magnetURI, "magnet:?xt=urn:btih:open")
        XCTAssertNil(viewModel.permissionErrorMessage)
    }

    func testRejectsUnsupportedDropsAndExplainsPermissionFailures() async throws {
        let engine = RecordingTorrentEngine(error: CocoaError(.fileReadNoPermission))
        let viewModel = MacOSIntegrationViewModel(environment: AppEnvironment(
            metadataService: CoreMockMetadataService(),
            torrentEngine: engine,
            playbackService: CoreMockPlaybackService(),
            subtitleService: CoreMockSubtitleService(),
            libraryRepository: CoreMockLibraryRepository(),
            settingsRepository: CoreMockSettingsRepository(),
            diagnosticsService: CoreMockDiagnosticsService(),
            updateService: CoreMockUpdateService()
        ))
        let unsupportedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")

        await viewModel.handleOpenURL(unsupportedURL)
        XCTAssertEqual(viewModel.permissionErrorMessage, "Streamly can open only .torrent files or magnet links.")

        await viewModel.handleDroppedText("not a magnet")
        XCTAssertEqual(viewModel.permissionErrorMessage, "Dropped text is not a magnet link.")

        let torrentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("torrent")
        await viewModel.handleOpenURL(torrentURL)

        XCTAssertEqual(
            viewModel.permissionErrorMessage,
            "Streamly could not access this file or folder. Choose a readable location in Settings or grant macOS permission."
        )
    }
}

private actor RecordingTorrentEngine: TorrentEngineProtocol {
    nonisolated let temporaryStorageURL = TorrentCacheLocation.defaultStorageURL()
    private(set) var addedMagnets: [String] = []
    private(set) var addedTorrentFiles: [URL] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func searchReleases(for item: MediaItem) async throws -> [TorrentRelease] {
        []
    }

    func addMagnet(uri: String) async throws -> TorrentSession {
        if let error { throw error }
        addedMagnets.append(uri)
        return TorrentSession(
            id: "magnet-\(addedMagnets.count)",
            magnetURI: uri,
            storageURL: temporaryStorageURL
        )
    }

    func addTorrentFile(url: URL) async throws -> TorrentSession {
        if let error { throw error }
        addedTorrentFiles.append(url)
        return TorrentSession(
            id: "torrent-\(addedTorrentFiles.count)",
            torrentFileURL: url,
            storageURL: temporaryStorageURL
        )
    }

    func recordedMagnets() -> [String] {
        addedMagnets
    }

    func recordedTorrentFiles() -> [URL] {
        addedTorrentFiles
    }
}
