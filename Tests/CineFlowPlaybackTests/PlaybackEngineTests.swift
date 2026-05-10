import CineFlowCore
import XCTest
@testable import CineFlowPlayback

final class PlaybackEngineTests: XCTestCase {
    func testMockPlaybackServicePlaysLocalMediaAndExposesControls() async throws {
        let service: any PlaybackServiceProtocol = MockPlaybackService()
        let source = PlaybackMediaSource(
            id: "tmdb:movie:603",
            title: "The Matrix",
            url: URL(fileURLWithPath: "/tmp/matrix.mkv"),
            qualityLabel: "2160p HDR",
            sourceName: "Mock Source"
        )

        try await service.play(source)
        try await service.seek(to: 42)
        try await service.setVolume(0.42)
        try await service.setMuted(true)
        try await service.setPlaybackSpeed(1.25)
        try await service.selectAudioTrack(id: "audio-ru")
        try await service.selectSubtitleTrack(id: "sub-en")
        try await service.setFullscreen(true)

        let status = await service.currentStatus

        XCTAssertEqual(status.state, .playing)
        XCTAssertEqual(status.media?.id, source.id)
        XCTAssertEqual(status.currentTime, 42)
        XCTAssertEqual(status.volume, 0.42, accuracy: 0.001)
        XCTAssertTrue(status.isMuted)
        XCTAssertEqual(status.playbackSpeed, 1.25, accuracy: 0.001)
        XCTAssertEqual(status.selectedAudioTrackId, "audio-ru")
        XCTAssertEqual(status.selectedSubtitleTrackId, "sub-en")
        XCTAssertTrue(status.isFullscreen)
        XCTAssertEqual(status.qualityLabel, "2160p HDR")
        XCTAssertEqual(status.sourceName, "Mock Source")
    }

    func testPauseResumeStopAndStatusUpdates() async throws {
        let service: any PlaybackServiceProtocol = MockPlaybackService()
        let source = PlaybackMediaSource(
            id: "mock:clip",
            title: "Clip",
            url: URL(fileURLWithPath: "/tmp/clip.mp4")
        )

        try await service.play(source)
        try await service.pause()
        let pausedStatus = await service.currentStatus
        XCTAssertEqual(pausedStatus.state, .paused)

        try await service.resume()
        let resumedStatus = await service.currentStatus
        XCTAssertEqual(resumedStatus.state, .playing)

        var iterator = service.statusUpdates().makeAsyncIterator()
        let update = try await iterator.next()
        XCTAssertEqual(update?.state, .playing)
        XCTAssertFalse(update?.audioTracks.isEmpty == true)
        XCTAssertFalse(update?.subtitleTracks.isEmpty == true)

        try await service.stop()
        let stoppedStatus = await service.currentStatus
        XCTAssertEqual(stoppedStatus.state, .idle)
    }

    func testProgressRecorderPersistsEveryConfiguredInterval() async throws {
        let store = InMemoryPlaybackProgressStore()
        let recorder = PlaybackProgressRecorder(store: store, saveIntervalSeconds: 5)
        let source = PlaybackMediaSource(
            id: "tmdb:movie:603",
            title: "The Matrix",
            url: URL(fileURLWithPath: "/tmp/matrix.mkv")
        )

        try await recorder.recordIfNeeded(status: PlaybackStatus(media: source, state: .playing, currentTime: 4, duration: 120), force: false)
        let initialRecords = await store.records
        XCTAssertTrue(initialRecords.isEmpty)

        try await recorder.recordIfNeeded(status: PlaybackStatus(media: source, state: .playing, currentTime: 5, duration: 120), force: false)
        try await recorder.recordIfNeeded(status: PlaybackStatus(media: source, state: .playing, currentTime: 8, duration: 120), force: false)
        try await recorder.recordIfNeeded(status: PlaybackStatus(media: source, state: .paused, currentTime: 8, duration: 120), force: true)

        let records = await store.records
        XCTAssertEqual(records.map(\.positionSeconds), [5, 8])
        XCTAssertEqual(records.map(\.durationSeconds), [120, 120])
    }

    func testMPVPlaybackServiceUsesSwiftBoundaryAndConfiguredOptions() async throws {
        let bridge = PlaceholderMPVBridge()
        let service = MPVPlaybackService(bridge: bridge)
        let options = service.options

        XCTAssertTrue(options.hardwareDecoding.contains("videotoolbox"))
        XCTAssertEqual(options.subtitleRendering, .enabled)
        XCTAssertEqual(options.videoOutput, "libmpv")

        do {
            try await service.play(PlaybackMediaSource(id: "mock", title: "Mock", url: URL(fileURLWithPath: "/tmp/mock.mkv")))
            XCTFail("Placeholder mpv bridge should not play media before binary integration.")
        } catch PlaybackServiceError.mpvUnavailable {
            XCTAssertTrue(true)
        }
    }
}
