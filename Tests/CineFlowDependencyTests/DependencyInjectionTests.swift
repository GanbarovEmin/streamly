import XCTest
@testable import CineFlowCore
@testable import CineFlowDatabase
@testable import CineFlowMetadata
@testable import CineFlowTorrent
@testable import CineFlowPlayback
@testable import CineFlowSubtitles
@testable import CineFlowSources
@testable import CineFlowSettings
@testable import CineFlowUpdater
@testable import CineFlowDiagnostics

final class DependencyInjectionTests: XCTestCase {
    func testMockAppEnvironmentProvidesEveryCoreService() async throws {
        let environment = AppEnvironment.mock()

        let metadataResults = try await environment.metadataService.search(query: "matrix")
        let releases = try await environment.torrentEngine.searchReleases(for: metadataResults[0])
        let playbackState = await environment.playbackService.currentState
        let subtitles = try await environment.subtitleService.preferredSubtitles(for: metadataResults[0])
        let library = try await environment.libraryRepository.items()
        let languages = await environment.settingsRepository.subtitleLanguagePriority
        let diagnostics = await environment.diagnosticsService.exportDiagnostics()
        let updateStatus = await environment.updateService.currentStatus
        let sourceCatalog = SourceProviderCatalog.mock

        XCTAssertFalse(metadataResults.isEmpty)
        XCTAssertEqual(releases.map(\.id), ["mock-2160p", "mock-1080p"])
        XCTAssertEqual(playbackState, .idle)
        XCTAssertEqual(subtitles.map(\.languageCode), ["ru", "en"])
        XCTAssertEqual(library.map(\.id), ["tmdb:movie:603"])
        XCTAssertEqual(languages, ["ru", "en"])
        XCTAssertTrue(diagnostics.contains("Streamly diagnostics"))
        XCTAssertEqual(updateStatus, .idle)
        XCTAssertEqual(sourceCatalog.providerNames, ["Mock Source Provider"])
    }

    func testRealModuleMocksCanBeInjectedWithoutChangingCoreEnvironment() {
        let environment = AppEnvironment(
            metadataService: MockMetadataService(),
            torrentEngine: MockTorrentEngine(),
            playbackService: MockPlaybackService(),
            subtitleService: MockSubtitleService(),
            libraryRepository: MockLibraryRepository(),
            settingsRepository: MockSettingsRepository(),
            diagnosticsService: MockDiagnosticsService(),
            updateService: MockUpdateService()
        )

        XCTAssertNotNil(environment)
    }
}
