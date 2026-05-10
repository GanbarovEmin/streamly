import CineFlowCore
import XCTest
@testable import CineFlowPlayback
@testable import CineFlowSubtitles
@testable import CineFlowUI

final class PlayerViewModelTests: XCTestCase {
    @MainActor
    func testPlayerViewModelStartsMockMediaAndControlsPlayback() async throws {
        let service = MockPlaybackService()
        let source = PlaybackMediaSource(
            id: "tmdb:movie:603",
            title: "The Matrix",
            url: URL(fileURLWithPath: "/tmp/matrix.mkv"),
            qualityLabel: "2160p HDR",
            sourceName: "Mock Source"
        )
        let viewModel = PlayerViewModel(service: service, mediaSource: source)

        await viewModel.start()
        XCTAssertEqual(viewModel.status.state, .playing)

        await viewModel.togglePlayPause()
        XCTAssertEqual(viewModel.status.state, .paused)

        await viewModel.togglePlayPause()
        await viewModel.seekForward()
        await viewModel.volumeUp()
        await viewModel.selectAudioTrack(id: "audio-ru")
        await viewModel.selectSubtitleTrack(id: "sub-en")
        await viewModel.toggleFullscreen()

        XCTAssertEqual(viewModel.status.state, .playing)
        XCTAssertEqual(viewModel.status.currentTime, 10)
        XCTAssertEqual(viewModel.status.selectedAudioTrackId, "audio-ru")
        XCTAssertEqual(viewModel.status.selectedSubtitleTrackId, "sub-en")
        XCTAssertTrue(viewModel.status.isFullscreen)
        XCTAssertFalse(viewModel.audioTracks.isEmpty)
        XCTAssertFalse(viewModel.subtitleTracks.isEmpty)
    }

    @MainActor
    func testPlayerViewModelAcceptsLocalHTTPStreamingURL() async throws {
        let service = MockPlaybackService()
        let source = PlaybackMediaSource(
            id: "tmdb:movie:603",
            title: "The Matrix",
            url: URL(string: "http://127.0.0.1:49152/stream.mkv")!,
            qualityLabel: "2160p",
            sourceName: "Torrentio"
        )
        let viewModel = PlayerViewModel(service: service, mediaSource: source)

        await viewModel.start()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.status.state, .playing)
        XCTAssertEqual(viewModel.status.media?.url, source.url)
    }

    @MainActor
    func testPlayerViewModelCanFindOnlineLoadLocalAndDisableSubtitles() async throws {
        let service = MockPlaybackService()
        let subtitleService = SubtitleService(
            openSubtitlesClient: MockOpenSubtitlesClient(results: [
                SubtitleSearchResult(
                    id: "online-ru",
                    title: "The Matrix RU",
                    languageCode: "ru",
                    source: .openSubtitles,
                    score: 1,
                    downloadURL: URL(string: "https://example.test/matrix-ru.srt")
                )
            ])
        )
        let source = PlaybackMediaSource(
            id: "tmdb:movie:603",
            title: "The Matrix",
            url: URL(fileURLWithPath: "/tmp/matrix.mkv")
        )
        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent("matrix.az.srt")
        try "1\n00:00:00,000 --> 00:00:01,000\nSalam\n".write(to: localURL, atomically: true, encoding: .utf8)
        let viewModel = PlayerViewModel(service: service, mediaSource: source, subtitleService: subtitleService)

        await viewModel.start()
        await viewModel.findOnlineSubtitles()
        await viewModel.loadLocalSubtitle(url: localURL)
        await viewModel.disableSubtitles()

        XCTAssertEqual(viewModel.onlineSubtitleResults.map(\.languageCode), ["ru"])
        XCTAssertTrue(viewModel.subtitleTracks.contains(where: { $0.source == .localFile && $0.languageCode == "az" }))
        XCTAssertNil(viewModel.status.selectedSubtitleTrackId)
    }

    @MainActor
    func testPlayerViewModelResumesFromSavedPositionAndSavesOnClose() async throws {
        let service = MockPlaybackService()
        let source = PlaybackMediaSource(
            id: "tmdb:movie:603",
            title: "The Matrix",
            url: URL(fileURLWithPath: "/tmp/matrix.mkv")
        )
        let repository = InMemoryPlayerProgressRepository(records: [
            PlaybackProgress(mediaID: source.id, positionSeconds: 42, durationSeconds: 120)
        ])
        let recorder = PlaybackProgressRecorder(store: repository, saveIntervalSeconds: 5)
        let viewModel = PlayerViewModel(
            service: service,
            mediaSource: source,
            progressRecorder: recorder,
            progressRepository: repository
        )

        await viewModel.start()

        XCTAssertTrue(viewModel.shouldOfferResume)
        XCTAssertEqual(viewModel.status.currentTime, 42)

        await viewModel.seekForward()
        await viewModel.saveProgressOnClose()

        let saved = try await repository.progress(mediaID: source.id, episodeID: nil)
        XCTAssertEqual(saved?.positionSeconds, 52)
    }

    @MainActor
    func testPlayerViewModelLogsSubtitleErrorsToDiagnostics() async throws {
        let diagnostics = RecordingDiagnosticsService()
        let source = PlaybackMediaSource(
            id: "tmdb:movie:603",
            title: "The Matrix",
            url: URL(fileURLWithPath: "/tmp/matrix.mkv")
        )
        let viewModel = PlayerViewModel(
            service: MockPlaybackService(),
            mediaSource: source,
            diagnosticsService: diagnostics
        )

        await viewModel.loadLocalSubtitle(url: URL(fileURLWithPath: "/tmp/not-a-subtitle.txt"))

        let events = await diagnostics.events()
        XCTAssertEqual(events.first?.subsystem, .subtitle)
        XCTAssertEqual(events.first?.metadata["operation"], "loadLocalSubtitle")
        XCTAssertEqual(events.first?.metadata["mediaID"], source.id)
    }
}

private actor InMemoryPlayerProgressRepository: PlaybackProgressRepositoryProtocol {
    private var records: [PlaybackProgress]

    init(records: [PlaybackProgress] = []) {
        self.records = records
    }

    func saveProgress(_ progress: PlaybackProgress) async throws {
        records.removeAll { $0.mediaID == progress.mediaID && $0.episodeID == progress.episodeID }
        records.append(progress)
    }

    func progress(mediaID: String, episodeID: String?) async throws -> PlaybackProgress? {
        records.first { $0.mediaID == mediaID && $0.episodeID == episodeID }
    }

    func continueWatching(includeCompleted: Bool) async throws -> [PlaybackProgress] {
        records
            .filter { includeCompleted || !$0.completed }
            .sorted { $0.lastWatchedAt > $1.lastWatchedAt }
    }

    func clearProgress(mediaID: String, episodeID: String?) async throws {
        records.removeAll { $0.mediaID == mediaID && $0.episodeID == episodeID }
    }
}

private actor RecordingDiagnosticsService: DiagnosticsServiceProtocol {
    private var recordedEvents: [DiagnosticsEvent] = []

    func log(level: DiagnosticsLogLevel, subsystem: DiagnosticsSubsystem, message: String, metadata: [String: String]) async {
        recordedEvents.append(DiagnosticsEvent(level: level, subsystem: subsystem, message: message, metadata: metadata))
    }

    func exportDiagnostics() async -> String {
        "diagnostics.zip"
    }

    func exportDiagnosticsPackage() async throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics.zip")
    }

    func recentEvents(limit: Int) async -> [DiagnosticsEvent] {
        Array(recordedEvents.suffix(limit))
    }

    func events() -> [DiagnosticsEvent] {
        recordedEvents
    }
}
