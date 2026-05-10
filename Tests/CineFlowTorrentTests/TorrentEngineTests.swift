import CineFlowCore
import XCTest
@testable import CineFlowTorrent

final class TorrentEngineTests: XCTestCase {
    func testMockEngineCanStartPlaybackThroughTorrentEngineProtocol() async throws {
        let engine: any TorrentEngineProtocol = MockTorrentEngine()
        let release = TorrentRelease(
            id: "matrix-2160p",
            sourceId: "mock",
            sourceName: "Mock Source",
            title: "The Matrix 2160p",
            magnetURI: "magnet:?xt=urn:btih:matrix",
            quality: .ultraHD,
            seeders: 120
        )

        let session = try await engine.startStreaming(release)
        let status = try await engine.getStatus(sessionId: session.id)
        let files = try await engine.getFileList(sessionId: session.id)
        let playbackURL = try await engine.getStreamingURL(sessionId: session.id)

        XCTAssertEqual(session.releaseId, release.id)
        XCTAssertTrue(session.isSequentialDownloadEnabled)
        XCTAssertEqual(status.state, .streaming)
        XCTAssertEqual(status.health.seeders, 120)
        XCTAssertGreaterThan(status.progress.downloadSpeedBytesPerSecond, 0)
        XCTAssertEqual(files.filter(\.isMediaFile).count, 1)
        XCTAssertTrue(playbackURL.isFileURL)
        XCTAssertTrue(playbackURL.path.contains("TorrentCache"))
    }

    func testMockEngineExposesStatusUpdatesForPlaybackLayer() async throws {
        let engine: any TorrentEngineProtocol = MockTorrentEngine()
        let session = try await engine.addMagnet(uri: "magnet:?xt=urn:btih:status")
        var iterator = engine.statusUpdates(sessionId: session.id).makeAsyncIterator()

        let update = try await iterator.next()

        XCTAssertEqual(update?.sessionId, session.id)
        XCTAssertEqual(update?.state, .downloading)
        XCTAssertGreaterThan(update?.progress.bufferedBytes ?? 0, 0)
        XCTAssertGreaterThan(update?.progress.downloadSpeedBytesPerSecond ?? 0, 0)
        XCTAssertGreaterThan(update?.health.seeders ?? 0, 0)
    }

    func testMockEngineSupportsPauseResumeStopRemoveAndStatusUpdates() async throws {
        let engine = MockTorrentEngine()
        let session = try await engine.addMagnet(uri: "magnet:?xt=urn:btih:arrival")

        try await engine.pause(sessionId: session.id)
        let pausedStatus = try await engine.getStatus(sessionId: session.id)
        XCTAssertEqual(pausedStatus.state, .paused)

        try await engine.resume(sessionId: session.id)
        let resumedStatus = try await engine.getStatus(sessionId: session.id)
        XCTAssertEqual(resumedStatus.state, .downloading)

        try await engine.stop(sessionId: session.id)
        let stoppedStatus = try await engine.getStatus(sessionId: session.id)
        XCTAssertEqual(stoppedStatus.state, .stopped)

        try await engine.remove(sessionId: session.id, deleteFiles: true)

        do {
            _ = try await engine.getStatus(sessionId: session.id)
            XCTFail("Expected removed session lookup to fail.")
        } catch TorrentEngineError.sessionNotFound(let sessionId) {
            XCTAssertEqual(sessionId, session.id)
        }
    }

    func testFileSelectionSequentialModePriorityAndCleanupPolicy() async throws {
        let engine = MockTorrentEngine()
        let torrentData = Data("mock torrent".utf8)
        let session = try await engine.addTorrentFile(data: torrentData)
        let files = try await engine.getFileList(sessionId: session.id)
        let mediaFile = try XCTUnwrap(files.first(where: \.isMediaFile))

        try await engine.selectMediaFile(sessionId: session.id, fileId: mediaFile.id)
        try await engine.setSequentialDownload(sessionId: session.id, enabled: true)
        try await engine.setDownloadPriority(sessionId: session.id, fileId: mediaFile.id, priority: .high)

        let updatedFiles = try await engine.getFileList(sessionId: session.id)
        let updatedStatus = try await engine.getStatus(sessionId: session.id)
        let updatedMediaFile = try XCTUnwrap(updatedFiles.first(where: { $0.id == mediaFile.id }))

        XCTAssertEqual(updatedStatus.selectedFileId, mediaFile.id)
        XCTAssertTrue(updatedStatus.isSequentialDownloadEnabled)
        XCTAssertEqual(updatedMediaFile.priority, .high)

        let cleanup = try await engine.cleanup(policy: .all)

        XCTAssertEqual(cleanup.removedSessionIds, [session.id])
        XCTAssertGreaterThan(cleanup.freedBytes, 0)
    }

    func testEmbeddedLibtorrentEngineUsesSwiftBoundaryAndTorrentCachePath() async throws {
        let engine = EmbeddedLibtorrentTorrentEngine(bridge: PlaceholderLibtorrentBridge())
        let cacheURL = engine.temporaryStorageURL

        XCTAssertTrue(cacheURL.path.contains("Application Support"))
        XCTAssertTrue(cacheURL.path.contains("Streamly/TorrentCache"))

        do {
            _ = try await engine.addMagnet(uri: "magnet:?xt=urn:btih:placeholder")
            XCTFail("Placeholder bridge should not perform real libtorrent work.")
        } catch TorrentEngineError.libtorrentUnavailable {
            XCTAssertTrue(true)
        }
    }
}
