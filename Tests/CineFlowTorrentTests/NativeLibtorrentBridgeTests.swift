import CineFlowCore
import XCTest
@testable import CineFlowTorrent

final class NativeLibtorrentBridgeTests: XCTestCase {
    func testNativeBridgeDecodesStatusFilesAndStreamingURLFromABI() async throws {
        let abi = FakeNativeLibtorrentABI()
        let bridge = NativeLibtorrentBridge(abi: abi)
        let storageURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("native-bridge-test", isDirectory: true)

        let handle = try await bridge.addMagnet(
            uri: "magnet:?xt=urn:btih:native",
            storageURL: storageURL
        )
        try await bridge.setSequentialDownload(handle: handle, enabled: true)
        try await bridge.start(handle: handle)
        let status = try await bridge.status(handle: handle)
        let files = try await bridge.files(handle: handle)
        try await bridge.selectFile(handle: handle, fileId: "0")
        try await bridge.setDownloadPriority(handle: handle, fileId: "0", priority: .high)
        try await bridge.setBandwidthLimits(
            handle: handle,
            limits: TorrentBandwidthLimits(downloadBytesPerSecond: 1_024_000, uploadBytesPerSecond: 128_000)
        )
        let streamingURL = try await bridge.streamingURL(handle: handle)

        XCTAssertEqual(handle, "native-handle")
        XCTAssertEqual(status.sessionId, "native-handle")
        XCTAssertEqual(status.state, .streaming)
        XCTAssertEqual(status.progress.downloadedBytes, 524_288)
        XCTAssertEqual(status.progress.totalBytes, 1_048_576)
        XCTAssertEqual(status.progress.bufferedBytes, 262_144)
        XCTAssertEqual(status.progress.downloadSpeedBytesPerSecond, 8_388_608)
        XCTAssertEqual(status.progress.uploadSpeedBytesPerSecond, 131_072)
        XCTAssertEqual(status.health.seeders, 42)
        XCTAssertEqual(status.health.connectedPeers, 18)
        XCTAssertEqual(status.selectedFileId, "0")
        XCTAssertTrue(status.isSequentialDownloadEnabled)
        XCTAssertEqual(status.streamingURL?.absoluteString, "http://127.0.0.1:49152/stream/native-handle/0")
        XCTAssertEqual(files, [
            TorrentFile(
                id: "0",
                path: "Movie/File.mkv",
                name: "File.mkv",
                lengthBytes: 1_048_576,
                isMediaFile: true,
                priority: .high,
                progress: TorrentProgress(downloadedBytes: 524_288, totalBytes: 1_048_576)
            )
        ])
        XCTAssertEqual(streamingURL.absoluteString, "http://127.0.0.1:49152/stream/native-handle/0")
        XCTAssertEqual(abi.calls, [
            "create",
            "addMagnet:magnet:?xt=urn:btih:native",
            "setSequential:native-handle:true",
            "start:native-handle",
            "status:native-handle",
            "files:native-handle",
            "selectFile:native-handle:0",
            "setPriority:native-handle:0:3",
            "setBandwidthLimits:native-handle:1024000:128000",
            "streamingURL:native-handle"
        ])
    }

    func testNativeBridgeMapsUnavailableABIToLibtorrentUnavailable() async throws {
        let bridge = NativeLibtorrentBridge(abi: UnavailableNativeLibtorrentABI())

        do {
            _ = try await bridge.addMagnet(
                uri: "magnet:?xt=urn:btih:native",
                storageURL: URL(fileURLWithPath: NSTemporaryDirectory())
            )
            XCTFail("Expected unavailable native ABI to surface libtorrentUnavailable.")
        } catch TorrentEngineError.libtorrentUnavailable {
            XCTAssertTrue(true)
        }
    }

    func testNativeBridgeMapsNativeFileErrorsToTorrentFileNotFound() async throws {
        let abi = FakeNativeLibtorrentABI(selectFileError: .fileNotFound(sessionId: "native-handle", fileId: "9"))
        let bridge = NativeLibtorrentBridge(abi: abi)

        do {
            try await bridge.selectFile(handle: "native-handle", fileId: "9")
            XCTFail("Expected native file selection failure to map to fileNotFound.")
        } catch TorrentEngineError.fileNotFound(let sessionId, let fileId) {
            XCTAssertEqual(sessionId, "native-handle")
            XCTAssertEqual(fileId, "9")
        }
    }

    func testNativeBridgePreservesStreamingURLErrorReason() async throws {
        let abi = FakeNativeLibtorrentABI(
            streamingURLError: .unsupported(operation: "startup_buffer_timeout:0/1")
        )
        let bridge = NativeLibtorrentBridge(abi: abi)

        do {
            _ = try await bridge.streamingURL(handle: "native-handle")
            XCTFail("Expected native streaming URL failure to preserve helper reason.")
        } catch TorrentEngineError.unsupported(let operation) {
            XCTAssertEqual(operation, "startup_buffer_timeout:0/1")
        }
    }

    func testNativeBridgeCanStartRealMagnetWhenIntegrationEnvironmentIsProvided() async throws {
        guard let magnet = ProcessInfo.processInfo.environment["CINEFLOW_NATIVE_LIBTORRENT_TEST_MAGNET"],
              !magnet.isEmpty else {
            throw XCTSkip("Set CINEFLOW_NATIVE_LIBTORRENT_TEST_MAGNET to run the native libtorrent smoke test.")
        }

        let bridge = NativeLibtorrentBridge()
        let storageURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("native-libtorrent-integration", isDirectory: true)

        let handle = try await bridge.addMagnet(uri: magnet, storageURL: storageURL)
        try await bridge.setSequentialDownload(handle: handle, enabled: true)
        try await bridge.start(handle: handle)
        let status = try await bridge.status(handle: handle)

        XCTAssertFalse(handle.isEmpty)
        XCTAssertTrue(status.isSequentialDownloadEnabled)
        XCTAssertTrue([.checking, .downloading, .streaming, .seeding].contains(status.state))
    }

    func testNativeBridgeCanResolveFilesAndStreamingURLWhenTorrentFileEnvironmentIsProvided() async throws {
        guard let torrentPath = ProcessInfo.processInfo.environment["CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE"],
              !torrentPath.isEmpty else {
            throw XCTSkip("Set CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE to run the native file-to-stream smoke test.")
        }

        let bridge = NativeLibtorrentBridge()
        let storageURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("native-libtorrent-file-stream", isDirectory: true)

        let handle = try await bridge.addTorrentFile(
            url: URL(fileURLWithPath: torrentPath),
            storageURL: storageURL
        )
        try await bridge.setSequentialDownload(handle: handle, enabled: true)
        try await bridge.start(handle: handle)
        let files = try await bridge.files(handle: handle)
        let mediaFile = try XCTUnwrap(files.first(where: \.isMediaFile))
        try await bridge.selectFile(handle: handle, fileId: mediaFile.id)
        let streamingURL = try await bridge.streamingURL(handle: handle)

        XCTAssertFalse(handle.isEmpty)
        XCTAssertFalse(files.isEmpty)
        XCTAssertEqual(streamingURL.scheme, "http")
        XCTAssertEqual(streamingURL.host, "127.0.0.1")
        try await bridge.remove(handle: handle, deleteFiles: true)
    }
}

private final class FakeNativeLibtorrentABI: NativeLibtorrentABI, @unchecked Sendable {
    var calls: [String] = []
    private let selectFileError: TorrentEngineError?
    private let streamingURLError: TorrentEngineError?

    init(selectFileError: TorrentEngineError? = nil, streamingURLError: TorrentEngineError? = nil) {
        self.selectFileError = selectFileError
        self.streamingURLError = streamingURLError
    }

    func createEngine(storagePath: String) throws -> NativeLibtorrentEngineHandle {
        calls.append("create")
        return NativeLibtorrentEngineHandle(rawValue: OpaquePointer(bitPattern: 0x1)!)
    }

    func destroyEngine(_ engine: NativeLibtorrentEngineHandle) {}

    func addMagnet(engine: NativeLibtorrentEngineHandle, uri: String, storagePath: String) throws -> String {
        calls.append("addMagnet:\(uri)")
        return "native-handle"
    }

    func addTorrentFile(engine: NativeLibtorrentEngineHandle, torrentPath: String, storagePath: String) throws -> String {
        calls.append("addTorrentFile:\(torrentPath)")
        return "native-handle"
    }

    func start(engine: NativeLibtorrentEngineHandle, handle: String) throws {
        calls.append("start:\(handle)")
    }

    func pause(engine: NativeLibtorrentEngineHandle, handle: String) throws {
        calls.append("pause:\(handle)")
    }

    func resume(engine: NativeLibtorrentEngineHandle, handle: String) throws {
        calls.append("resume:\(handle)")
    }

    func stop(engine: NativeLibtorrentEngineHandle, handle: String) throws {
        calls.append("stop:\(handle)")
    }

    func remove(engine: NativeLibtorrentEngineHandle, handle: String, deleteFiles: Bool) throws {
        calls.append("remove:\(handle):\(deleteFiles)")
    }

    func statusJSON(engine: NativeLibtorrentEngineHandle, handle: String) throws -> String {
        calls.append("status:\(handle)")
        return """
        {
          "state": "streaming",
          "downloadedBytes": 524288,
          "totalBytes": 1048576,
          "bufferedBytes": 262144,
          "downloadSpeedBytesPerSecond": 8388608,
          "uploadSpeedBytesPerSecond": 131072,
          "seeders": 42,
          "leechers": 5,
          "connectedPeers": 18,
          "availability": 1.0,
          "selectedFileId": "0",
          "isSequentialDownloadEnabled": true,
          "streamingURL": "http://127.0.0.1:49152/stream/native-handle/0"
        }
        """
    }

    func filesJSON(engine: NativeLibtorrentEngineHandle, handle: String) throws -> String {
        calls.append("files:\(handle)")
        return """
        [
          {
            "id": "0",
            "path": "Movie/File.mkv",
            "name": "File.mkv",
            "lengthBytes": 1048576,
            "isMediaFile": true,
            "priority": 3,
            "downloadedBytes": 524288,
            "totalBytes": 1048576
          }
        ]
        """
    }

    func selectFile(engine: NativeLibtorrentEngineHandle, handle: String, fileId: String) throws {
        calls.append("selectFile:\(handle):\(fileId)")
        if let selectFileError {
            throw selectFileError
        }
    }

    func setSequentialDownload(engine: NativeLibtorrentEngineHandle, handle: String, enabled: Bool) throws {
        calls.append("setSequential:\(handle):\(enabled)")
    }

    func setDownloadPriority(engine: NativeLibtorrentEngineHandle, handle: String, fileId: String, priority: TorrentFilePriority) throws {
        calls.append("setPriority:\(handle):\(fileId):\(priority.rawValue)")
    }

    func setBandwidthLimits(engine: NativeLibtorrentEngineHandle, handle: String, limits: TorrentBandwidthLimits) throws {
        calls.append("setBandwidthLimits:\(handle):\(limits.downloadBytesPerSecond ?? -1):\(limits.uploadBytesPerSecond ?? -1)")
    }

    func streamingURL(engine: NativeLibtorrentEngineHandle, handle: String) throws -> URL {
        calls.append("streamingURL:\(handle)")
        if let streamingURLError {
            throw streamingURLError
        }
        return URL(string: "http://127.0.0.1:49152/stream/native-handle/0")!
    }
}

private struct UnavailableNativeLibtorrentABI: NativeLibtorrentABI {
    func createEngine(storagePath: String) throws -> NativeLibtorrentEngineHandle {
        throw TorrentEngineError.libtorrentUnavailable
    }

    func destroyEngine(_ engine: NativeLibtorrentEngineHandle) {}

    func addMagnet(engine: NativeLibtorrentEngineHandle, uri: String, storagePath: String) throws -> String {
        throw TorrentEngineError.libtorrentUnavailable
    }

    func addTorrentFile(engine: NativeLibtorrentEngineHandle, torrentPath: String, storagePath: String) throws -> String {
        throw TorrentEngineError.libtorrentUnavailable
    }

    func start(engine: NativeLibtorrentEngineHandle, handle: String) throws {}
    func pause(engine: NativeLibtorrentEngineHandle, handle: String) throws {}
    func resume(engine: NativeLibtorrentEngineHandle, handle: String) throws {}
    func stop(engine: NativeLibtorrentEngineHandle, handle: String) throws {}
    func remove(engine: NativeLibtorrentEngineHandle, handle: String, deleteFiles: Bool) throws {}
    func statusJSON(engine: NativeLibtorrentEngineHandle, handle: String) throws -> String { "{}" }
    func filesJSON(engine: NativeLibtorrentEngineHandle, handle: String) throws -> String { "[]" }
    func selectFile(engine: NativeLibtorrentEngineHandle, handle: String, fileId: String) throws {}
    func setSequentialDownload(engine: NativeLibtorrentEngineHandle, handle: String, enabled: Bool) throws {}
    func setDownloadPriority(engine: NativeLibtorrentEngineHandle, handle: String, fileId: String, priority: TorrentFilePriority) throws {}
    func setBandwidthLimits(engine: NativeLibtorrentEngineHandle, handle: String, limits: TorrentBandwidthLimits) throws {}
    func streamingURL(engine: NativeLibtorrentEngineHandle, handle: String) throws -> URL {
        throw TorrentEngineError.libtorrentUnavailable
    }
}
