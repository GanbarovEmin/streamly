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
    func testPlayerViewModelOffersResumeChoiceBeforeSeekingAndSavesOnClose() async throws {
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
        XCTAssertEqual(viewModel.resumePrompt?.positionLabel, "0:42")
        XCTAssertEqual(viewModel.status.currentTime, 0)

        await viewModel.continueFromResume()
        XCTAssertFalse(viewModel.shouldOfferResume)
        XCTAssertEqual(viewModel.status.currentTime, 42)

        await viewModel.seekForward()
        await viewModel.saveProgressOnClose()

        let saved = try await repository.progress(mediaID: source.id, episodeID: nil)
        XCTAssertEqual(saved?.positionSeconds, 52)
    }

    @MainActor
    func testPlayerViewModelCanStartOverFromResumePrompt() async throws {
        let service = MockPlaybackService()
        let source = PlaybackMediaSource(
            id: "tmdb:movie:603",
            title: "The Matrix",
            url: URL(fileURLWithPath: "/tmp/matrix.mkv")
        )
        let repository = InMemoryPlayerProgressRepository(records: [
            PlaybackProgress(mediaID: source.id, positionSeconds: 84, durationSeconds: 120)
        ])
        let viewModel = PlayerViewModel(
            service: service,
            mediaSource: source,
            progressRepository: repository
        )

        await viewModel.start()
        await viewModel.startOverFromBeginning()

        XCTAssertFalse(viewModel.shouldOfferResume)
        XCTAssertEqual(viewModel.status.currentTime, 0)
    }

    @MainActor
    func testPlayerViewModelHandlesCinematicKeyboardShortcuts() async throws {
        let service = MockPlaybackService()
        let source = PlaybackMediaSource(
            id: "tmdb:movie:603",
            title: "The Matrix",
            url: URL(fileURLWithPath: "/tmp/matrix.mkv")
        )
        let viewModel = PlayerViewModel(service: service, mediaSource: source)

        await viewModel.start()
        await viewModel.handleShortcut(.space)
        XCTAssertEqual(viewModel.status.state, .paused)

        await viewModel.handleShortcut(.right)
        XCTAssertEqual(viewModel.status.currentTime, 10)

        await viewModel.handleShortcut(.shiftRight)
        XCTAssertEqual(viewModel.status.currentTime, 70)

        await viewModel.handleShortcut(.left)
        XCTAssertEqual(viewModel.status.currentTime, 60)

        await viewModel.handleShortcut(.shiftLeft)
        XCTAssertEqual(viewModel.status.currentTime, 0)

        await viewModel.handleShortcut(.up)
        XCTAssertEqual(viewModel.status.volume, 1)

        await viewModel.handleShortcut(.down)
        XCTAssertEqual(viewModel.status.volume, 0.9, accuracy: 0.001)

        await viewModel.handleShortcut(.mute)
        XCTAssertTrue(viewModel.status.isMuted)

        await viewModel.handleShortcut(.fullscreen)
        XCTAssertTrue(viewModel.status.isFullscreen)
    }

    @MainActor
    func testPlayerViewModelAutoHidesControlsAfterPointerActivity() async throws {
        let viewModel = PlayerViewModel(
            service: MockPlaybackService(),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:603",
                title: "The Matrix",
                url: URL(fileURLWithPath: "/tmp/matrix.mkv")
            )
        )

        viewModel.showControlsTemporarily(autoHideAfter: 0.01)
        XCTAssertTrue(viewModel.controlsAreVisible)

        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertFalse(viewModel.controlsAreVisible)
    }

    @MainActor
    func testPlayerViewModelShowsNextEpisodePromptNearCompletion() async throws {
        let nextEpisode = PlayerNextEpisodePrompt(
            title: "S1E2 The Kingsroad",
            subtitle: "Next episode"
        )
        let service = CompletingPlaybackService()
        let viewModel = PlayerViewModel(
            service: service,
            mediaSource: PlaybackMediaSource(
                id: "tmdb:series:1399:s1e1",
                title: "Winter Is Coming",
                url: URL(fileURLWithPath: "/tmp/got-s1e1.mkv")
            ),
            nextEpisodePrompt: nextEpisode
        )

        await viewModel.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.nextEpisodePrompt?.title, "S1E2 The Kingsroad")
        XCTAssertTrue(viewModel.shouldOfferNextEpisode)
    }

    @MainActor
    func testBufferingPresentationHidesTechnicalDetailsUntilAdvancedMode() async throws {
        let release = TorrentRelease(
            id: "release",
            title: "Release",
            quality: .fullHD,
            seeders: 140,
            availability: 1
        )
        let service = BufferingPlaybackService(release: release)
        let viewModel = PlayerViewModel(
            service: service,
            mediaSource: PlaybackMediaSource(release: release)
        )

        await viewModel.start()

        XCTAssertEqual(viewModel.bufferingPresentation.title, "Buffering")
        XCTAssertTrue(viewModel.bufferingPresentation.message.contains("64%"))
        XCTAssertTrue(viewModel.bufferingPresentation.advancedDetails.isEmpty)

        viewModel.setAdvancedDebugVisible(true)

        XCTAssertTrue(viewModel.bufferingPresentation.advancedDetails.contains(where: { $0.contains("Seeders: 140") }))
        XCTAssertTrue(viewModel.bufferingPresentation.advancedDetails.contains(where: { $0.contains("Health: Good") || $0.contains("Health: Excellent") }))
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

    @MainActor
    func testPlayerViewModelOffersFallbackOnStalledReleaseWithoutAutoSwitching() async throws {
        let selected = TorrentRelease(id: "weak", title: "Weak Release", quality: .fullHD, seeders: 3)
        let fallback = TorrentRelease(id: "healthy", title: "Healthy Release", quality: .fullHD, seeders: 120)
        let service = StalledPlaybackService()
        let diagnostics = RecordingDiagnosticsService()
        let source = PlaybackMediaSource(
            id: "tmdb:movie:603",
            title: "The Matrix",
            url: URL(fileURLWithPath: "/tmp/weak.mkv"),
            release: selected
        )
        let viewModel = PlayerViewModel(
            service: service,
            mediaSource: source,
            diagnosticsService: diagnostics,
            fallbackReleases: [selected, fallback]
        )

        await viewModel.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.fallbackSuggestion?.reason, .stalled)
        XCTAssertEqual(viewModel.fallbackSuggestion?.nextBestRelease?.release.id, fallback.id)
        let playedBeforeFallback = await service.playedReleaseIDs()
        XCTAssertEqual(playedBeforeFallback, [selected.id])

        await viewModel.tryNextBestRelease()

        let playedAfterFallback = await service.playedReleaseIDs()
        XCTAssertEqual(playedAfterFallback, [selected.id, fallback.id])
        let events = await diagnostics.events()
        XCTAssertTrue(events.contains(where: { $0.metadata["operation"] == "player.fallback.suggest" }))
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

private actor StalledPlaybackService: PlaybackServiceProtocol {
    private var status = PlaybackStatus()
    private var playedIDs: [String] = []

    var currentState: PlaybackState {
        get async {
            if case .playing(let release) = status.media?.release.map({ PlaybackState.playing($0) }) {
                return .playing(release)
            }
            return .idle
        }
    }

    var currentStatus: PlaybackStatus {
        get async { status }
    }

    func play(_ source: PlaybackMediaSource) async throws {
        if let release = source.release {
            playedIDs.append(release.id)
        }
        status = PlaybackStatus(media: source, state: .playing)
    }

    func play(_ release: TorrentRelease) async throws {
        try await play(PlaybackMediaSource(release: release))
    }

    func pause() async throws {}
    func resume() async throws {}
    func stop() async throws {}
    func seek(to time: Double) async throws {}
    func setVolume(_ volume: Double) async throws {}
    func setMuted(_ isMuted: Bool) async throws {}
    func setPlaybackSpeed(_ speed: Double) async throws {}
    func selectAudioTrack(id: String?) async throws {}
    func selectSubtitleTrack(id: String?) async throws {}
    func setFullscreen(_ isFullscreen: Bool) async throws {}
    func setPictureInPicture(_ isActive: Bool) async throws {}

    nonisolated func statusUpdates() -> AsyncThrowingStream<PlaybackStatus, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let source = await self.currentStatus.media
                continuation.yield(PlaybackStatus(media: source, state: .failed(reason: "stream stalled")))
                continuation.finish()
            }
        }
    }

    func playedReleaseIDs() -> [String] {
        playedIDs
    }
}

private actor CompletingPlaybackService: PlaybackServiceProtocol {
    private var status = PlaybackStatus()

    var currentState: PlaybackState {
        get async { .preparing }
    }

    var currentStatus: PlaybackStatus {
        get async { status }
    }

    func play(_ source: PlaybackMediaSource) async throws {
        status = PlaybackStatus(media: source, state: .playing, currentTime: 0, duration: 100)
    }

    func play(_ release: TorrentRelease) async throws {
        try await play(PlaybackMediaSource(release: release))
    }

    func pause() async throws {}
    func resume() async throws {}
    func stop() async throws {}
    func seek(to time: Double) async throws {}
    func setVolume(_ volume: Double) async throws {}
    func setMuted(_ isMuted: Bool) async throws {}
    func setPlaybackSpeed(_ speed: Double) async throws {}
    func selectAudioTrack(id: String?) async throws {}
    func selectSubtitleTrack(id: String?) async throws {}
    func setFullscreen(_ isFullscreen: Bool) async throws {}
    func setPictureInPicture(_ isActive: Bool) async throws {}

    nonisolated func statusUpdates() -> AsyncThrowingStream<PlaybackStatus, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let source = await self.currentStatus.media
                continuation.yield(PlaybackStatus(media: source, state: .playing, currentTime: 94, duration: 100))
                continuation.finish()
            }
        }
    }
}

private actor BufferingPlaybackService: PlaybackServiceProtocol {
    private var status: PlaybackStatus
    private let release: TorrentRelease

    init(release: TorrentRelease) {
        self.release = release
        status = PlaybackStatus()
    }

    var currentState: PlaybackState {
        get async { .preparing }
    }

    var currentStatus: PlaybackStatus {
        get async { status }
    }

    func play(_ source: PlaybackMediaSource) async throws {
        status = PlaybackStatus(
            media: source,
            state: .playing,
            currentTime: 12,
            duration: 100,
            bufferingState: .buffering(progress: 0.64),
            sourceName: release.sourceName
        )
    }

    func play(_ release: TorrentRelease) async throws {
        try await play(PlaybackMediaSource(release: release))
    }

    func pause() async throws {}
    func resume() async throws {}
    func stop() async throws {}
    func seek(to time: Double) async throws {}
    func setVolume(_ volume: Double) async throws {}
    func setMuted(_ isMuted: Bool) async throws {}
    func setPlaybackSpeed(_ speed: Double) async throws {}
    func selectAudioTrack(id: String?) async throws {}
    func selectSubtitleTrack(id: String?) async throws {}
    func setFullscreen(_ isFullscreen: Bool) async throws {}
    func setPictureInPicture(_ isActive: Bool) async throws {}

    nonisolated func statusUpdates() -> AsyncThrowingStream<PlaybackStatus, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(await self.currentStatus)
                continuation.finish()
            }
        }
    }
}
