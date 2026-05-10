import CineFlowCore
@testable import CineFlowPlayback
@testable import CineFlowTorrent
import XCTest

final class TorrentPlaybackIntegrationTests: XCTestCase {
    @MainActor
    func testNativeTorrentStreamCanReachInAppAVPlayerWhenIntegrationEnvironmentIsProvided() async throws {
        guard let torrentPath = ProcessInfo.processInfo.environment["CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE"],
              !torrentPath.isEmpty,
              let ffmpegPath = ProcessInfo.processInfo.environment["STREAMLY_TRANSCODE_TEST_FFMPEG"],
              !ffmpegPath.isEmpty
        else {
            throw XCTSkip("Set CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE and STREAMLY_TRANSCODE_TEST_FFMPEG to run the torrent-to-player smoke test.")
        }

        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("streamly-torrent-playback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storageURL) }

        let bridge = NativeLibtorrentBridge()
        let handle = try await bridge.addTorrentFile(
            url: URL(fileURLWithPath: torrentPath),
            storageURL: storageURL
        )

        try await bridge.setSequentialDownload(handle: handle, enabled: true)
        try await bridge.start(handle: handle)
        let files = try await bridge.files(handle: handle)
        let mediaFile = try XCTUnwrap(files.first(where: \.isMediaFile))
        try await bridge.selectFile(handle: handle, fileId: mediaFile.id)
        let streamURL = try await bridge.streamingURL(handle: handle)

        let playbackService = TranscodingAVPlaybackService(
            ffmpegExecutableURL: URL(fileURLWithPath: ffmpegPath)
        )
        try await playbackService.play(
            PlaybackMediaSource(
                id: "integration:torrent-file",
                title: mediaFile.name,
                url: streamURL,
                qualityLabel: "Integration",
                sourceName: "Native torrent"
            )
        )

        let status = await playbackService.currentStatus

        XCTAssertNotNil(playbackService.avPlayer.currentItem)
        XCTAssertEqual(status.state, .playing)
        XCTAssertEqual(status.media?.url, streamURL)
        XCTAssertEqual(streamURL.host, "127.0.0.1")

        try await playbackService.stop()
        try await bridge.remove(handle: handle, deleteFiles: true)
    }
}
