import CineFlowCore
import AVFoundation
import Network
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

    @MainActor
    func testAVFoundationPlaybackServiceTracksLocalFileStateChanges() async throws {
        let service: any PlaybackServiceProtocol = AVFoundationPlaybackService()
        let source = PlaybackMediaSource(
            id: "tmdb:movie:603",
            title: "The Matrix",
            url: URL(fileURLWithPath: "/tmp/matrix.mp4"),
            qualityLabel: "Local",
            sourceName: "Local file"
        )

        try await service.play(source)
        var status = await service.currentStatus
        XCTAssertEqual(status.state, .playing)
        XCTAssertEqual(status.media?.id, source.id)

        try await service.pause()
        status = await service.currentStatus
        XCTAssertEqual(status.state, .paused)

        try await service.resume()
        status = await service.currentStatus
        XCTAssertEqual(status.state, .playing)

        try await service.stop()
        status = await service.currentStatus
        XCTAssertEqual(status.state, .idle)
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
        let bridge = UnavailableMPVBridge()
        let service = MPVPlaybackService(bridge: bridge)
        let options = service.options

        XCTAssertTrue(options.hardwareDecoding.contains("videotoolbox"))
        XCTAssertEqual(options.subtitleRendering, .enabled)
        XCTAssertEqual(options.videoOutput, "libmpv")

        do {
            try await service.play(PlaybackMediaSource(id: "mock", title: "Mock", url: URL(fileURLWithPath: "/tmp/mock.mkv")))
            XCTFail("Unavailable mpv bridge should not play media before binary integration.")
        } catch PlaybackServiceError.mpvUnavailable {
            XCTAssertTrue(true)
        }
    }

    @MainActor
    func testTranscodingAVPlaybackServiceCanStartInAppHLSWhenIntegrationEnvironmentIsProvided() async throws {
        guard let ffmpegPath = ProcessInfo.processInfo.environment["STREAMLY_TRANSCODE_TEST_FFMPEG"],
              !ffmpegPath.isEmpty else {
            throw XCTSkip("Set STREAMLY_TRANSCODE_TEST_FFMPEG to run the in-app HLS playback smoke test.")
        }

        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("streamly-transcode-smoke-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let sampleURL = rootURL.appendingPathComponent("sample.mp4")
        try makeSampleMP4(ffmpegPath: ffmpegPath, outputURL: sampleURL)

        let server = try PlaybackTestHTTPFileServer(rootURL: rootURL)
        defer { server.stop() }

        let service = TranscodingAVPlaybackService(ffmpegExecutableURL: URL(fileURLWithPath: ffmpegPath))
        try await service.play(
            PlaybackMediaSource(
                id: "integration:sample",
                title: "Transcode Smoke",
                url: server.url(for: "sample.mp4"),
                qualityLabel: "Smoke",
                sourceName: "Local HTTP"
            )
        )
        defer { Task { try? await service.stop() } }

        let item = try XCTUnwrap(service.avPlayer.currentItem)
        let isPlayable = try await item.asset.load(.isPlayable)
        XCTAssertTrue(isPlayable)

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline,
              item.status == .unknown,
              service.avPlayer.currentTime().seconds <= 0 {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertTrue(
            item.status == .readyToPlay || service.avPlayer.currentTime().seconds > 0,
            "AVPlayer did not become ready for local HLS playback; status=\(item.status.rawValue), error=\(item.error?.localizedDescription ?? "none")"
        )
    }

    private func makeSampleMP4(ffmpegPath: String, outputURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-f", "lavfi",
            "-i", "testsrc2=size=320x180:rate=24",
            "-f", "lavfi",
            "-i", "sine=frequency=880:sample_rate=44100",
            "-t", "2",
            "-pix_fmt", "yuv420p",
            "-c:v", "libx264",
            "-preset", "ultrafast",
            "-c:a", "aac",
            outputURL.path
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

private final class PlaybackTestHTTPFileServer: @unchecked Sendable {
    private let rootURL: URL
    private let listener: NWListener
    private let queue = DispatchQueue(label: "streamly.playback-test.http-server")
    private var port: UInt16 = 0

    init(rootURL: URL) throws {
        self.rootURL = rootURL
        listener = try NWListener(using: .tcp, on: .any)

        let ready = DispatchSemaphore(value: 0)
        var startupError: Error?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case .failed(let error):
                startupError = error
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 2)

        if let startupError {
            throw startupError
        }
        port = try XCTUnwrap(listener.port?.rawValue)
    }

    func url(for path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)/\(path)")!
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let response = self.response(for: data ?? Data())
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func response(for requestData: Data) -> Data {
        guard let request = String(data: requestData, encoding: .utf8),
              let requestLine = request.components(separatedBy: "\r\n").first
        else {
            return httpResponse(status: "400 Bad Request", body: Data())
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return httpResponse(status: "400 Bad Request", body: Data())
        }

        let method = parts[0]
        guard method == "GET" || method == "HEAD" else {
            return httpResponse(status: "405 Method Not Allowed", body: Data())
        }

        let rawPath = String(parts[1]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let path = (rawPath.removingPercentEncoding ?? rawPath).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty, !path.contains("..") else {
            return httpResponse(status: "404 Not Found", body: Data())
        }

        let fileURL = rootURL.appendingPathComponent(path)
        guard fileURL.path.hasPrefix(rootURL.path),
              let body = try? Data(contentsOf: fileURL)
        else {
            return httpResponse(status: "404 Not Found", body: Data())
        }

        if let range = byteRange(from: request, size: body.count) {
            let slice = method == "HEAD" ? Data() : body.subdata(in: range)
            return httpResponse(
                status: "206 Partial Content",
                headers: ["Content-Range": "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(body.count)"],
                body: slice,
                contentLength: range.count
            )
        }

        return httpResponse(status: "200 OK", body: method == "HEAD" ? Data() : body, contentLength: body.count)
    }

    private func byteRange(from request: String, size: Int) -> Range<Int>? {
        guard let line = request.components(separatedBy: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("range:") }),
            let value = line.components(separatedBy: "bytes=").dropFirst().first
        else {
            return nil
        }

        let rangeText = value.trimmingCharacters(in: .whitespaces)
            .split(separator: ",", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        let parts = rangeText.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let startText = parts.first,
              let start = Int(startText)
        else {
            return nil
        }
        let end = parts.count > 1 ? Int(parts[1]) ?? (size - 1) : (size - 1)
        guard start >= 0, start < size else { return nil }
        return start..<(min(end, size - 1) + 1)
    }

    private func httpResponse(
        status: String,
        headers: [String: String] = [:],
        body: Data,
        contentLength: Int? = nil
    ) -> Data {
        var response = Data()
        response.append(Data("HTTP/1.1 \(status)\r\n".utf8))
        response.append(Data("Accept-Ranges: bytes\r\n".utf8))
        for (key, value) in headers {
            response.append(Data("\(key): \(value)\r\n".utf8))
        }
        response.append(Data("Content-Length: \(contentLength ?? body.count)\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(body)
        return response
    }
}
