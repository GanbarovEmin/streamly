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

    func testTorrentStatusModelCoversStreamingLifecycleAndBandwidthLimits() async throws {
        let engine = MockTorrentEngine()
        let session = try await engine.addMagnet(uri: "magnet:?xt=urn:btih:lifecycle")

        try await engine.setBandwidthLimits(
            sessionId: session.id,
            TorrentBandwidthLimits(downloadBytesPerSecond: 1_024_000, uploadBytesPerSecond: 128_000)
        )
        let limitedStatus = try await engine.getStatus(sessionId: session.id)

        XCTAssertEqual(TorrentSessionState.connecting.userFacingLabel, "Connecting")
        XCTAssertEqual(TorrentSessionState.metadataLoading.userFacingLabel, "Loading metadata")
        XCTAssertEqual(TorrentSessionState.buffering.userFacingLabel, "Buffering")
        XCTAssertEqual(TorrentSessionState.stalled.userFacingLabel, "Connection stalled")
        XCTAssertEqual(TorrentSessionState.completed.userFacingLabel, "Completed")
        XCTAssertEqual(TorrentSessionState.error(reason: "No peers").userFacingLabel, "Error")
        XCTAssertEqual(limitedStatus.bandwidthLimits?.downloadBytesPerSecond, 1_024_000)
        XCTAssertEqual(limitedStatus.bandwidthLimits?.uploadBytesPerSecond, 128_000)

        try await engine.setBandwidthLimits(sessionId: session.id, .unlimited)
        let unlimitedStatus = try await engine.getStatus(sessionId: session.id)
        XCTAssertEqual(unlimitedStatus.bandwidthLimits, .unlimited)
    }

    func testEmbeddedEngineStartStreamingStartsSessionWithoutSelectingVideoFile() async throws {
        let bridge = RecordingLibtorrentBridge(files: [
            TorrentFile(id: "sample", path: "sample.txt", name: "sample.txt", lengthBytes: 2_000, isMediaFile: false),
            TorrentFile(id: "small", path: "Movie/sample.mp4", name: "sample.mp4", lengthBytes: 25_000_000, isMediaFile: true),
            TorrentFile(id: "main", path: "Movie/main.mkv", name: "main.mkv", lengthBytes: 4_000_000_000, isMediaFile: true)
        ])
        let engine = EmbeddedLibtorrentTorrentEngine(bridge: bridge)
        let release = TorrentRelease(
            id: "movie-1080p",
            title: "Movie 1080p",
            magnetURI: "magnet:?xt=urn:btih:main",
            quality: .fullHD,
            seeders: 12
        )

        let session = try await engine.startStreaming(release)
        let status = try await engine.getStatus(sessionId: session.id)

        XCTAssertNil(session.selectedFileId)
        XCTAssertNil(status.selectedFileId)
        XCTAssertNil(status.streamingURL)
        let calls = await bridge.recordedCalls()
        XCTAssertEqual(calls, [
            "addMagnet",
            "setSequential:true",
            "start",
            "status"
        ])
    }

    func testCleanupPoliciesProtectActiveSessionsAndShutdownStopsRemainingSessions() async throws {
        let engine = MockTorrentEngine()
        let active = try await engine.addMagnet(uri: "magnet:?xt=urn:btih:active")
        let old = try await engine.addMagnet(uri: "magnet:?xt=urn:btih:old")

        try await engine.markSessionCreatedAt(old.id, Date(timeIntervalSinceNow: -40 * 24 * 60 * 60))
        let cleanup = try await engine.cleanup(policy: .olderThan(Date(timeIntervalSinceNow: -30 * 24 * 60 * 60), protecting: [active.id]))

        XCTAssertEqual(cleanup.removedSessionIds, [old.id])
        let activeStatus = try await engine.getStatus(sessionId: active.id)
        XCTAssertEqual(activeStatus.sessionId, active.id)

        try await engine.shutdown()

        let stopped = try await engine.getStatus(sessionId: active.id)
        XCTAssertEqual(stopped.state, .stopped)
    }

    func testEmbeddedLibtorrentEngineSurfacesUnavailableWhenPlaceholderBridgeIsInjected() async throws {
        let engine = EmbeddedLibtorrentTorrentEngine(bridge: PlaceholderLibtorrentBridge())
        let cacheURL = engine.temporaryStorageURL

        XCTAssertTrue(cacheURL.path.contains("Application Support"))
        XCTAssertTrue(cacheURL.path.contains("Streamly/TorrentCache"))

        do {
            _ = try await engine.addMagnet(uri: "magnet:?xt=urn:btih:placeholder")
            XCTFail("Placeholder bridge should remain an explicit unavailable fallback.")
        } catch TorrentEngineError.libtorrentUnavailable {
            XCTAssertTrue(true)
        }
    }
}

private actor RecordingLibtorrentBridge: LibtorrentBridgeProtocol {
    private(set) var calls: [String] = []
    private let filesValue: [TorrentFile]
    private var selectedFileID: String?
    private var sequentialDownloadEnabled = false

    init(files: [TorrentFile]) {
        filesValue = files
    }

    func addMagnet(uri: String, storageURL: URL) async throws -> String {
        calls.append("addMagnet")
        return "recording-handle"
    }

    func addTorrentFile(url: URL, storageURL: URL) async throws -> String {
        calls.append("addTorrentFile")
        return "recording-handle"
    }

    func start(handle: String) async throws {
        calls.append("start")
    }

    func pause(handle: String) async throws {}
    func resume(handle: String) async throws {}

    func stop(handle: String) async throws {
        calls.append("stop")
    }

    func remove(handle: String, deleteFiles: Bool) async throws {
        calls.append("remove:\(deleteFiles)")
    }

    func status(handle: String) async throws -> TorrentStatus {
        calls.append("status")
        return TorrentStatus(
            sessionId: handle,
            state: .streaming,
            selectedFileId: selectedFileID,
            isSequentialDownloadEnabled: sequentialDownloadEnabled,
            streamingURL: selectedFileID.map { URL(fileURLWithPath: "/tmp/\($0)") }
        )
    }

    func files(handle: String) async throws -> [TorrentFile] {
        calls.append("files")
        return filesValue
    }

    func selectFile(handle: String, fileId: String) async throws {
        calls.append("select:\(fileId)")
        selectedFileID = fileId
    }

    func setSequentialDownload(handle: String, enabled: Bool) async throws {
        calls.append("setSequential:\(enabled)")
        sequentialDownloadEnabled = enabled
    }

    func setDownloadPriority(handle: String, fileId: String, priority: TorrentFilePriority) async throws {
        calls.append("priority:\(fileId):\(priority.rawValue)")
    }

    func setBandwidthLimits(handle: String, limits: TorrentBandwidthLimits) async throws {}

    func streamingURL(handle: String) async throws -> URL {
        calls.append("streamingURL")
        guard let selectedFileID else {
            throw TorrentEngineError.streamingURLUnavailable(sessionId: handle)
        }
        return URL(fileURLWithPath: "/tmp/\(selectedFileID)")
    }

    func recordedCalls() -> [String] {
        calls
    }
}
