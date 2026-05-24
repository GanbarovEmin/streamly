import CineFlowCore
import AVFoundation
import Network
import XCTest
@testable import CineFlowPlayback

final class PlaybackEngineTests: XCTestCase {
    @MainActor
    func testTorrentHLSStartupCanBeginAfterFirstPlayableSegment() {
        let oneSegment = """
        #EXTM3U
        #EXT-X-TARGETDURATION:2
        #EXTINF:2.000000,
        segment_00000.ts
        """
        let noSegment = """
        #EXTM3U
        #EXT-X-TARGETDURATION:2
        """
        let readyPlaylist = """
        #EXTM3U
        #EXTINF:2.000000,
        segment_00000.ts
        #EXTINF:2.000000,
        segment_00001.ts
        #EXTINF:2.000000,
        segment_00002.ts
        #EXTINF:2.000000,
        segment_00003.ts
        """

        XCTAssertTrue(TranscodingAVPlaybackService.playlistIsReadyForStartup(oneSegment))
        XCTAssertFalse(TranscodingAVPlaybackService.playlistIsReadyForStartup(noSegment))
        XCTAssertTrue(TranscodingAVPlaybackService.playlistIsReadyForStartup(readyPlaylist))
    }

    @MainActor
    func testLocalTorrentHLSUsesFastStartupProbeSettings() {
        XCTAssertEqual(
            TranscodingAVPlaybackService.hlsInputProbeArguments(isLocalTorrentStream: true),
            ["-probesize", "1048576", "-analyzeduration", "1500000"]
        )
        XCTAssertEqual(
            TranscodingAVPlaybackService.hlsInputProbeArguments(isLocalTorrentStream: false),
            ["-probesize", "5000000", "-analyzeduration", "5000000"]
        )
        XCTAssertEqual(
            TranscodingAVPlaybackService.hlsInputReadRateArguments(isLocalTorrentStream: true),
            ["-readrate", "1", "-readrate_initial_burst", "12"]
        )
        XCTAssertEqual(TranscodingAVPlaybackService.hlsInputReadRateArguments(isLocalTorrentStream: false), [])
        XCTAssertEqual(TranscodingAVPlaybackService.hlsReadTimeoutMicros(isLocalTorrentStream: true), "15000000")
        XCTAssertEqual(TranscodingAVPlaybackService.hlsStartupTimeoutSeconds(isLocalTorrentStream: true), 24)
        XCTAssertEqual(TranscodingAVPlaybackService.maxHLSStartupAttempts(isLocalTorrentStream: true), 2)
        XCTAssertLessThan(
            TranscodingAVPlaybackService.hlsStartupTimeoutSeconds(isLocalTorrentStream: true),
            TranscodingAVPlaybackService.hlsStartupTimeoutSeconds(isLocalTorrentStream: false)
        )
    }

    func testPlaybackPipelineDefaultsBoundStartupWaitsForAutomaticFallback() {
        let release = TorrentRelease(
            id: "bounded-startup",
            title: "Bounded Startup",
            magnetURI: "magnet:?xt=urn:btih:bounded",
            quality: .fullHD,
            seeders: 120
        )
        let request = PlaybackPipelineRequest(mediaID: "tmdb:movie:603", primaryRelease: release)

        XCTAssertEqual(request.metadataTimeoutSeconds, 16)
        XCTAssertEqual(request.streamURLTimeoutSeconds, 9)
        XCTAssertLessThan(request.metadataTimeoutSeconds, 30)
    }

    @MainActor
    func testLocalHLSBridgeUsesMovieDurationOverrideInsteadOfEventPlaylistDuration() {
        let bridgeURL = URL(string: "http://127.0.0.1:49200/stream.m3u8")!
        let directURL = URL(fileURLWithPath: "/tmp/movie.mp4")

        XCTAssertEqual(AVFoundationPlaybackService.effectiveDuration(72, mediaURL: bridgeURL, durationOverride: 7_200), 7_200)
        XCTAssertNil(AVFoundationPlaybackService.effectiveDuration(72, mediaURL: bridgeURL, durationOverride: nil))
        XCTAssertEqual(AVFoundationPlaybackService.effectiveDuration(7_200, mediaURL: directURL), 7_200)
        XCTAssertNil(AVFoundationPlaybackService.effectiveDuration(.nan, mediaURL: directURL))
        XCTAssertNil(AVFoundationPlaybackService.effectiveDuration(0, mediaURL: directURL))
    }

    @MainActor
    func testLocalHLSInitialSeekTargetsEarliestAvailableRange() {
        let ranges = [
            CMTimeRange(
                start: CMTime(seconds: 14, preferredTimescale: 600),
                duration: CMTime(seconds: 6, preferredTimescale: 600)
            ),
            CMTimeRange(
                start: CMTime(seconds: 2, preferredTimescale: 600),
                duration: CMTime(seconds: 4, preferredTimescale: 600)
            )
        ]

        XCTAssertEqual(TranscodingAVPlaybackService.initialHLSSeekTargetSeconds(from: ranges), 2)
        XCTAssertEqual(TranscodingAVPlaybackService.initialHLSSeekTargetSeconds(from: []), 0)
    }

    @MainActor
    func testFFmpegMetadataParserExtractsMovieDurationAndSelectableTracks() {
        let log = """
        Input #0, matroska,webm, from 'http://127.0.0.1:49152/stream/session/0':
          Duration: 01:41:45.50, start: 0.000000, bitrate: N/A
          Stream #0:0: Video: hevc (Main 10), yuv420p10le(tv, bt2020nc), 3840x2160
          Stream #0:1(rus): Audio: ac3, 48000 Hz, 5.1(side), fltp, 640 kb/s
          Stream #0:2(eng): Audio: dts, 48000 Hz, 7.1, fltp
          Stream #0:3(rus): Subtitle: subrip
          Stream #0:4(eng): Subtitle: hdmv_pgs_subtitle
        """

        let metadata = TranscodingAVPlaybackService.mediaMetadata(fromFFmpegLog: log)

        XCTAssertEqual(try XCTUnwrap(metadata.durationSeconds), 6_105.5, accuracy: 0.001)
        XCTAssertEqual(metadata.audioTracks.map(\.id), ["audio:0", "audio:1"])
        XCTAssertEqual(metadata.audioTracks.map(\.languageCode), ["ru", "en"])
        XCTAssertEqual(metadata.audioTracks.map(\.qualityLabel), ["5.1 Dolby", "7.1 DTS"])
        XCTAssertEqual(metadata.subtitleTracks.map(\.id), ["subtitle:0", "subtitle:1"])
        XCTAssertEqual(metadata.subtitleTracks.map(\.languageCode), ["ru", "en"])
    }

    func testTimelinePreviewServiceGeneratesAndReusesLocalCacheWithoutRemoteGeneration() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimelinePreviewServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let generator = RecordingTimelineFrameGenerator(data: Data("jpeg-thumbnail".utf8))
        let service = TimelinePreviewService(
            cache: TimelinePreviewCache(storageURL: cacheRoot),
            generator: generator
        )
        let localRequest = TimelinePreviewRequest(
            mediaID: "tmdb:movie:603",
            mediaURL: URL(fileURLWithPath: "/tmp/matrix.mkv"),
            timeSeconds: 41.7,
            durationSeconds: 120,
            bufferedUntilSeconds: 120,
            isPlaybackActive: true,
            width: 240,
            height: 135
        )

        let generated = try await service.preview(for: localRequest)
        let cached = try await service.preview(for: localRequest)
        let loopback = try await service.preview(
            for: TimelinePreviewRequest(
                mediaID: "tmdb:movie:loopback",
                mediaURL: URL(string: "http://127.0.0.1:49152/movie.mkv")!,
                timeSeconds: 55,
                durationSeconds: 120,
                bufferedUntilSeconds: 60,
                isPlaybackActive: true,
                width: 240,
                height: 135
            )
        )
        let remote = try await service.preview(
            for: TimelinePreviewRequest(
                mediaID: "tmdb:movie:remote",
                mediaURL: URL(string: "https://streamly.local/movie.mkv")!,
                timeSeconds: 40,
                durationSeconds: 120,
                bufferedUntilSeconds: nil,
                isPlaybackActive: true,
                width: 240,
                height: 135
            )
        )

        XCTAssertEqual(generated?.source, .generated)
        XCTAssertEqual(cached?.source, .cache)
        XCTAssertEqual(loopback?.source, .generated)
        XCTAssertEqual(generated?.imageData, Data("jpeg-thumbnail".utf8))
        XCTAssertNil(remote)
        let generatedTimes = await generator.generatedTimes()
        XCTAssertEqual(generatedTimes, [40, 50])
    }

    func testPlaybackRunStateCoversProductionLifecycle() {
        XCTAssertEqual(
            PlaybackRunState.productionLifecycleStates,
            [
                .idle,
                .loading,
                .resolving,
                .buffering,
                .ready,
                .playing,
                .paused,
                .stalled,
                .failed(reason: "unavailable"),
                .retrying,
                .completed
            ]
        )
    }

    @MainActor
    func testLocalTorrentHelperStartup5XXIsFallbackEligible() {
        let log = """
        [http @ 0x123] HTTP error 503 Service Unavailable
        http://127.0.0.1:49152/stream/session/0: Server returned 5XX Server Error reply
        """

        XCTAssertTrue(TranscodingAVPlaybackService.localTorrentStartupFailureIsFallbackEligible(logText: log))
    }

    func testPlaybackPipelineFallsBackWhenFirstReleaseCannotResolve() async throws {
        let selected = TorrentRelease(
            id: "broken",
            title: "Broken release",
            magnetURI: "magnet:?xt=urn:btih:broken",
            quality: .fullHD,
            seeders: 0
        )
        let fallback = TorrentRelease(
            id: "healthy",
            title: "Healthy release",
            magnetURI: "magnet:?xt=urn:btih:healthy",
            quality: .fullHD,
            seeders: 120
        )
        let engine = FallbackRecordingTorrentEngine(
            failures: ["broken": TorrentEngineError.streamingURLUnavailable(sessionId: "broken")]
        )
        let checker = RecordingAvailabilityChecker()
        let pipeline = PlaybackPipeline(
            torrentEngine: engine,
            availabilityChecker: checker,
            debugLogger: .disabled
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tmdb:movie:603",
                primaryRelease: selected,
                fallbackReleases: [selected, fallback],
                bandwidthLimits: .unlimited,
                maxAutomaticFallbacks: 1
            )
        )

        guard case .ready(let source, let session, let attempts) = result else {
            return XCTFail("Expected ready fallback result, got \(result)")
        }

        XCTAssertEqual(source.release?.id, fallback.id)
        XCTAssertEqual(session?.releaseId, fallback.id)
        XCTAssertEqual(attempts.map(\.release.id), ["broken", "healthy"])
        XCTAssertEqual(attempts.map(\.state), [.failed(reason: "streamingURLUnavailable(sessionId: \"broken\")"), .ready])
        let startedIDs = await engine.startedReleaseIDs()
        XCTAssertEqual(Set(startedIDs), Set(["broken", "healthy"]))
        let removedSessionIDs = await engine.removedSessionIDs()
        XCTAssertEqual(removedSessionIDs, ["session-broken"])
        let checkedURLs = await checker.checkedURLs()
        XCTAssertEqual(checkedURLs.count, 1)
        XCTAssertEqual(checkedURLs.first?.lastPathComponent, "healthy.mkv")
    }

    func testPlaybackPipelinePrefersDirectCachedStreamWithoutStartingTorrentEngine() async throws {
        let p2pRelease = TorrentRelease(
            id: "p2p",
            title: "P2P release",
            magnetURI: "magnet:?xt=urn:btih:p2p",
            quality: .fullHD,
            seeders: 120
        )
        let cachedRelease = TorrentRelease(
            id: "cached",
            sourceId: "torrentio",
            sourceName: "Torrentio Cached",
            title: "Cached release",
            directStreamURL: URL(string: "https://cached.example/movie.mkv"),
            quality: .fullHD,
            seeders: 0,
            availability: 1,
            rankScore: 100_000
        )
        let engine = FallbackRecordingTorrentEngine()
        let checker = RecordingAvailabilityChecker()
        let pipeline = PlaybackPipeline(
            torrentEngine: engine,
            availabilityChecker: checker,
            debugLogger: .disabled
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tmdb:movie:12042730",
                primaryRelease: p2pRelease,
                fallbackReleases: [p2pRelease, cachedRelease],
                maxAutomaticFallbacks: 1
            )
        )

        guard case .ready(let source, let session, let attempts) = result else {
            return XCTFail("Expected direct cached stream to be ready, got \(result)")
        }

        XCTAssertNil(session)
        XCTAssertEqual(source.url, URL(string: "https://cached.example/movie.mkv"))
        XCTAssertEqual(source.release?.id, cachedRelease.id)
        XCTAssertEqual(attempts.map(\.release.id), ["cached"])
        let startedReleaseIDs = await engine.startedReleaseIDs()
        let checkedURLNames = await checker.checkedURLs().map(\.lastPathComponent)
        XCTAssertEqual(startedReleaseIDs, [])
        XCTAssertEqual(checkedURLNames, ["movie.mkv"])
    }

    func testPlaybackPipelineSkipsFallbacksWithDuplicateInfoHash() async throws {
        let selected = TorrentRelease(
            id: "rutor-0",
            title: "Rutor 2160p",
            magnetURI: "magnet:?xt=urn:btih:sharedhash",
            quality: .ultraHD,
            seeders: 700
        )
        let duplicate = TorrentRelease(
            id: "rutor-auto",
            title: "Rutor 2160p auto",
            magnetURI: "magnet:?xt=urn:btih:sharedhash",
            quality: .ultraHD,
            seeders: 700
        )
        let fallback = TorrentRelease(
            id: "other-1080p",
            title: "Other 1080p",
            magnetURI: "magnet:?xt=urn:btih:otherhash",
            quality: .fullHD,
            seeders: 120
        )
        let engine = FallbackRecordingTorrentEngine(
            failures: [
                selected.id: TorrentEngineError.unsupported(operation: "startup_buffer_timeout:0/1"),
                duplicate.id: TorrentEngineError.unsupported(operation: "duplicate should not be attempted")
            ]
        )
        let pipeline = PlaybackPipeline(
            torrentEngine: engine,
            availabilityChecker: RecordingAvailabilityChecker(),
            debugLogger: .disabled
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tmdb:movie:603",
                primaryRelease: selected,
                fallbackReleases: [selected, duplicate, fallback],
                bandwidthLimits: .unlimited,
                maxAutomaticFallbacks: 1
            )
        )

        guard case .ready(let source, _, let attempts) = result else {
            return XCTFail("Expected duplicate hash to be skipped and next unique fallback to play, got \(result)")
        }

        XCTAssertEqual(source.release?.id, fallback.id)
        XCTAssertEqual(attempts.map(\.release.id), [selected.id, fallback.id])
        let startedIDs = await engine.startedReleaseIDs()
        XCTAssertEqual(Set(startedIDs), Set([selected.id, fallback.id]))
        XCTAssertFalse(startedIDs.contains(duplicate.id))
    }

    func testPlaybackPipelineDoesNotRejectRangeAvailableReleaseWithStaleSwarmCounters() async throws {
        let release = TorrentRelease(
            id: "provider-count-stale-but-readable",
            title: "Provider count stale but readable",
            magnetURI: "magnet:?xt=urn:btih:stale-readable",
            quality: .fullHD,
            seeders: 1_330
        )
        let engine = FallbackRecordingTorrentEngine(
            statusByReleaseID: [
                release.id: TorrentStatus(
                    sessionId: "session-\(release.id)",
                    state: .streaming,
                    progress: TorrentProgress(bufferedBytes: 0, downloadSpeedBytesPerSecond: 9_640),
                    health: TorrentHealth(seeders: 0, connectedPeers: 1, availability: 0),
                    selectedFileId: "\(release.id).mkv",
                    isSequentialDownloadEnabled: true
                )
            ]
        )
        let pipeline = PlaybackPipeline(
            torrentEngine: engine,
            availabilityChecker: RecordingAvailabilityChecker(),
            debugLogger: .disabled
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tmdb:movie:603",
                primaryRelease: release,
                fallbackReleases: [release],
                maxAutomaticFallbacks: 1
            )
        )

        guard case .ready(let source, _, let attempts) = result else {
            return XCTFail("Expected readable stream to win despite stale swarm counters, got \(result)")
        }

        XCTAssertEqual(source.release?.id, release.id)
        XCTAssertEqual(attempts.map(\.release.id), [release.id])
        XCTAssertEqual(attempts.map(\.state), [.ready])
    }

    func testPlaybackPipelineSkipsReleaseWhenStartupRangeIsUnavailable() async throws {
        let unavailable = TorrentRelease(
            id: "provider-count-stale",
            title: "Provider count stale",
            magnetURI: "magnet:?xt=urn:btih:stale",
            quality: .fullHD,
            seeders: 1_330
        )
        let fallback = TorrentRelease(
            id: "live-available",
            title: "Live available",
            magnetURI: "magnet:?xt=urn:btih:available",
            quality: .fullHD,
            seeders: 90
        )
        let engine = FallbackRecordingTorrentEngine(
            statusByReleaseID: [
                unavailable.id: TorrentStatus(
                    sessionId: "session-\(unavailable.id)",
                    state: .idle,
                    progress: TorrentProgress(bufferedBytes: 0, downloadSpeedBytesPerSecond: 9_640),
                    health: TorrentHealth(seeders: 0, connectedPeers: 2, availability: 0),
                    selectedFileId: "\(unavailable.id).mkv",
                    isSequentialDownloadEnabled: true
                ),
                fallback.id: TorrentStatus(
                    sessionId: "session-\(fallback.id)",
                    state: .streaming,
                    progress: TorrentProgress(bufferedBytes: 1_000_000),
                    health: TorrentHealth(seeders: 12, connectedPeers: 12, availability: 1),
                    selectedFileId: "\(fallback.id).mkv",
                    isSequentialDownloadEnabled: true
                )
            ]
        )
        let pipeline = PlaybackPipeline(
            torrentEngine: engine,
            availabilityChecker: RecordingAvailabilityChecker(
                responses: [
                    "\(unavailable.id).mkv": .unavailable(reason: "HTTP 503: startup_buffer_timeout:0/1")
                ]
            ),
            debugLogger: .disabled
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tmdb:movie:603",
                primaryRelease: unavailable,
                fallbackReleases: [unavailable, fallback],
                maxAutomaticFallbacks: 1
            )
        )

        guard case .ready(let source, _, let attempts) = result else {
            return XCTFail("Expected unavailable live swarm to fall back, got \(result)")
        }

        XCTAssertEqual(source.release?.id, fallback.id)
        XCTAssertEqual(attempts.map(\.release.id), [unavailable.id, fallback.id])
        XCTAssertTrue(attempts.first?.error?.technicalDescription.contains("startup_buffer_timeout") == true)
    }

    func testPlaybackPipelineLimitsParallelSwarmProbesToSmallBatches() async throws {
        let releases = (0..<14).map { index in
            TorrentRelease(
                id: "candidate-\(index)",
                title: "Candidate \(index)",
                magnetURI: "magnet:?xt=urn:btih:candidate\(index)",
                quality: .fullHD,
                seeders: 120
            )
        }
        let statusByReleaseID = Dictionary(
            uniqueKeysWithValues: releases.map { release in
                (
                    release.id,
                    TorrentStatus(
                        sessionId: "session-\(release.id)",
                        state: .idle,
                        progress: TorrentProgress(bufferedBytes: 0, downloadSpeedBytesPerSecond: 0),
                        health: TorrentHealth(seeders: 0, connectedPeers: 0, availability: 0),
                        selectedFileId: "\(release.id).mkv",
                        isSequentialDownloadEnabled: true
                    )
                )
            }
        )
        let startDelays = Dictionary(uniqueKeysWithValues: releases.map { ($0.id, UInt64(120_000_000)) })
        let engine = FallbackRecordingTorrentEngine(
            startDelays: startDelays,
            statusByReleaseID: statusByReleaseID
        )
        let pipeline = PlaybackPipeline(
            torrentEngine: engine,
            availabilityChecker: RecordingAvailabilityChecker(
                responses: Dictionary(
                    uniqueKeysWithValues: releases.map {
                        ("\($0.id).mkv", PlaybackStreamAvailability.unavailable(reason: "HTTP 503: startup_buffer_timeout:0/1"))
                    }
                )
            ),
            debugLogger: .disabled
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tmdb:movie:603",
                primaryRelease: releases[0],
                fallbackReleases: releases,
                maxAutomaticFallbacks: releases.count - 1,
                parallelSwarmProbeTimeoutSeconds: 1
            )
        )

        guard case .failed(_, _, let attempts) = result else {
            return XCTFail("Expected all unavailable candidates to fail, got \(result)")
        }

        XCTAssertEqual(attempts.count, releases.count)
        let maxConcurrentStarts = await engine.maxConcurrentStarts()
        XCTAssertGreaterThan(maxConcurrentStarts, 1)
        XCTAssertLessThanOrEqual(maxConcurrentStarts, 6)
    }

    func testPlaybackPipelineProbesTopFallbackCandidatesIndividuallyBeforeBatching() async throws {
        let releases = (0..<5).map { index in
            TorrentRelease(
                id: "candidate-\(index)",
                title: "Candidate \(index)",
                magnetURI: "magnet:?xt=urn:btih:candidate\(index)",
                quality: .fullHD,
                seeders: 120
            )
        }
        let engine = FallbackRecordingTorrentEngine(
            statusByReleaseID: [
                releases[0].id: TorrentStatus(
                    sessionId: "session-\(releases[0].id)",
                    state: .idle,
                    progress: TorrentProgress(bufferedBytes: 0, downloadSpeedBytesPerSecond: 0),
                    health: TorrentHealth(seeders: 0, connectedPeers: 0, availability: 0),
                    selectedFileId: "\(releases[0].id).mkv",
                    isSequentialDownloadEnabled: true
                )
            ]
        )
        let pipeline = PlaybackPipeline(
            torrentEngine: engine,
            availabilityChecker: RecordingAvailabilityChecker(
                responses: [
                    "\(releases[0].id).mkv": .unavailable(reason: "HTTP 503: startup_buffer_timeout:0/1")
                ]
            ),
            debugLogger: .disabled
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tmdb:movie:603",
                primaryRelease: releases[0],
                fallbackReleases: releases,
                maxAutomaticFallbacks: releases.count - 1,
                parallelSwarmProbeTimeoutSeconds: 1
            )
        )

        guard case .ready(let source, _, let attempts) = result else {
            return XCTFail("Expected second candidate to resolve before batched probing, got \(result)")
        }

        XCTAssertEqual(source.release?.id, releases[1].id)
        XCTAssertEqual(attempts.map(\.release.id), [releases[0].id, releases[1].id])
        let maxConcurrentStarts = await engine.maxConcurrentStarts()
        XCTAssertEqual(maxConcurrentStarts, 1)
    }

    func testPlaybackPipelinePreservesSelectionContextTitleForEpisodePlayback() async throws {
        let release = TorrentRelease(
            id: "got-s01e01",
            sourceId: "torrentio",
            sourceName: "Torrentio",
            title: "Game.of.Thrones.S01E01.1080p.mkv",
            magnetURI: "magnet:?xt=urn:btih:got",
            quality: .fullHD,
            seeders: 100,
            preferredFileIndex: 7
        )
        let context = PlaybackSelectionContext(
            mediaID: "tt0944947",
            displayTitle: "Game of Thrones",
            mediaKind: .series,
            seasonNumber: 1,
            episodeNumber: 1,
            episodeID: "tt0944947:1:1"
        )
        let pipeline = PlaybackPipeline(
            torrentEngine: FallbackRecordingTorrentEngine(),
            availabilityChecker: RecordingAvailabilityChecker(),
            debugLogger: .disabled
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tt0944947",
                selectionContext: context,
                primaryRelease: release,
                fallbackReleases: [],
                bandwidthLimits: .unlimited
            )
        )

        guard case .ready(let source, _, _) = result else {
            return XCTFail("Expected ready episode playback source, got \(result)")
        }

        XCTAssertEqual(source.title, "Game of Thrones")
        XCTAssertEqual(source.release?.title, "Game.of.Thrones.S01E01.1080p.mkv")
        XCTAssertEqual(source.selectionContext?.episodeID, "tt0944947:1:1")
        XCTAssertEqual(source.selectionContext?.seasonNumber, 1)
        XCTAssertEqual(source.selectionContext?.episodeNumber, 1)
    }

    func testPlaybackPipelineAutoStartsMatchedEpisodeWithoutManualSelection() async throws {
        let release = TorrentRelease(
            id: "torrentio:tt0944947:1:1:abcdefabcdefabcdefabcdefabcdefabcdefabcd:auto",
            sourceId: "torrentio",
            sourceName: "Torrentio",
            title: "Game of Thrones Season 1 Pack",
            magnetURI: "magnet:?xt=urn:btih:got",
            quality: .ultraHD,
            seeders: 12
        )
        let files = [
            TorrentFile(
                id: "8",
                path: "Игра престолов.S01.WEB-DL.2160p",
                name: "Игра престолов.S01E08.WEB-DL.2160p.mkv",
                lengthBytes: 9_700_000_000,
                isMediaFile: true
            ),
            TorrentFile(
                id: "1",
                path: "Игра престолов.S01.WEB-DL.2160p",
                name: "Игра престолов.S01E01.WEB-DL.2160p.mkv",
                lengthBytes: 9_500_000_000,
                isMediaFile: true
            )
        ]
        let engine = FallbackRecordingTorrentEngine(
            preselectsFile: false,
            filesByReleaseID: [release.id: files]
        )
        let pipeline = PlaybackPipeline(
            torrentEngine: engine,
            availabilityChecker: RecordingAvailabilityChecker(),
            debugLogger: .disabled
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tt0944947",
                primaryRelease: release,
                fallbackReleases: [],
                bandwidthLimits: .unlimited
            )
        )

        guard case .ready(let source, _, _) = result else {
            return XCTFail("Expected automatic episode playback, got \(result)")
        }

        XCTAssertEqual(source.release?.id, release.id)
        let selectedFileIDs = await engine.selectedFileIDs()
        XCTAssertEqual(selectedFileIDs, ["1"])
    }

    func testPlaybackPipelineReappliesStreamingPrioritiesForPreselectedSession() async throws {
        let release = TorrentRelease(
            id: "preselected",
            sourceId: "torrentio",
            sourceName: "Torrentio",
            title: "Preselected Movie",
            magnetURI: "magnet:?xt=urn:btih:preselected",
            quality: .fullHD,
            seeders: 42
        )
        let files = [
            TorrentFile(
                id: "preselected.mkv",
                path: "Preselected Movie/preselected.mkv",
                name: "preselected.mkv",
                lengthBytes: 4_000_000_000,
                isMediaFile: true
            ),
            TorrentFile(
                id: "sample.mkv",
                path: "Preselected Movie/sample.mkv",
                name: "sample.mkv",
                lengthBytes: 40_000_000,
                isMediaFile: true
            ),
            TorrentFile(
                id: "poster.jpg",
                path: "Preselected Movie/poster.jpg",
                name: "poster.jpg",
                lengthBytes: 500_000,
                isMediaFile: false
            )
        ]
        let engine = FallbackRecordingTorrentEngine(
            preselectsFile: true,
            filesByReleaseID: [release.id: files]
        )
        let pipeline = PlaybackPipeline(
            torrentEngine: engine,
            availabilityChecker: RecordingAvailabilityChecker(),
            debugLogger: .disabled
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tmdb:movie:preselected",
                primaryRelease: release,
                fallbackReleases: [],
                bandwidthLimits: .unlimited
            )
        )

        guard case .ready(_, _, _) = result else {
            return XCTFail("Expected preselected playback source, got \(result)")
        }

        let selectedFileIDs = await engine.selectedFileIDs()
        XCTAssertTrue(selectedFileIDs.isEmpty)
        let sequentialCalls = await engine.sequentialDownloadCalls()
        XCTAssertEqual(sequentialCalls, ["session-preselected:true"])
        let priorityCalls = await engine.priorityCalls()
        XCTAssertEqual(
            priorityCalls,
            [
                "preselected.mkv:high",
                "sample.mkv:low",
                "poster.jpg:disabled"
            ]
        )
    }

    func testPlaybackPipelineReturnsFailedWhenEveryFallbackFails() async throws {
        let first = TorrentRelease(
            id: "first",
            title: "First",
            magnetURI: "magnet:?xt=urn:btih:first",
            quality: .fullHD,
            seeders: 1
        )
        let second = TorrentRelease(
            id: "second",
            title: "Second",
            magnetURI: "magnet:?xt=urn:btih:second",
            quality: .hd,
            seeders: 1
        )
        let pipeline = PlaybackPipeline(
            torrentEngine: FallbackRecordingTorrentEngine(
                failures: [
                    "first": TorrentEngineError.streamingURLUnavailable(sessionId: "first"),
                    "second": TorrentEngineError.streamingURLUnavailable(sessionId: "second")
                ]
            ),
            availabilityChecker: RecordingAvailabilityChecker(),
            debugLogger: .disabled
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tmdb:movie:603",
                primaryRelease: first,
                fallbackReleases: [first, second],
                bandwidthLimits: .unlimited,
                maxAutomaticFallbacks: 1
            )
        )

        guard case .failed(let error, let suggestion, let attempts) = result else {
            return XCTFail("Expected failed result, got \(result)")
        }

        XCTAssertEqual(error.category, .torrent)
        XCTAssertNil(suggestion?.nextBestRelease)
        XCTAssertEqual(attempts.map(\.release.id), ["first", "second"])
        XCTAssertEqual(attempts.last?.state, .failed(reason: "streamingURLUnavailable(sessionId: \"second\")"))
    }

    func testPlaybackPipelineFallsBackWhenResolvedStreamIsUnavailable() async throws {
        let selected = TorrentRelease(
            id: "unavailable",
            title: "Unavailable stream",
            magnetURI: "magnet:?xt=urn:btih:unavailable",
            quality: .fullHD,
            seeders: 12
        )
        let fallback = TorrentRelease(
            id: "available",
            title: "Available stream",
            magnetURI: "magnet:?xt=urn:btih:available",
            quality: .hd,
            seeders: 90
        )
        let checker = RecordingAvailabilityChecker(
            responses: ["unavailable.mkv": .unavailable(reason: "HTTP 503")]
        )
        let pipeline = PlaybackPipeline(
            torrentEngine: FallbackRecordingTorrentEngine(),
            availabilityChecker: checker,
            debugLogger: .disabled
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tmdb:movie:603",
                primaryRelease: selected,
                fallbackReleases: [selected, fallback],
                bandwidthLimits: .unlimited,
                maxAutomaticFallbacks: 1
            )
        )

        guard case .ready(let source, _, let attempts) = result else {
            return XCTFail("Expected ready fallback result, got \(result)")
        }

        XCTAssertEqual(source.release?.id, fallback.id)
        XCTAssertEqual(attempts.map(\.release.id), ["unavailable", "available"])
        XCTAssertEqual(attempts.first?.error?.category, .playback)
        let checkedURLs = await checker.checkedURLs()
        XCTAssertEqual(checkedURLs.map(\.lastPathComponent), ["unavailable.mkv", "available.mkv"])
    }

    func testPlaybackPipelineTimesOutSlowStartAndFallsBack() async throws {
        let slow = TorrentRelease(
            id: "slow",
            title: "Slow release",
            magnetURI: "magnet:?xt=urn:btih:slow",
            quality: .fullHD,
            seeders: 30
        )
        let fallback = TorrentRelease(
            id: "fast",
            title: "Fast release",
            magnetURI: "magnet:?xt=urn:btih:fast",
            quality: .hd,
            seeders: 100
        )
        let engine = FallbackRecordingTorrentEngine(startDelays: ["slow": 5_000_000_000])
        let pipeline = PlaybackPipeline(
            torrentEngine: engine,
            availabilityChecker: RecordingAvailabilityChecker(),
            debugLogger: .disabled
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tmdb:movie:603",
                primaryRelease: slow,
                fallbackReleases: [slow, fallback],
                bandwidthLimits: .unlimited,
                maxAutomaticFallbacks: 1,
                torrentStartTimeoutSeconds: 1
            )
        )

        guard case .ready(let source, _, let attempts) = result else {
            return XCTFail("Expected timeout fallback result, got \(result)")
        }

        XCTAssertEqual(source.release?.id, fallback.id)
        XCTAssertEqual(attempts.map(\.release.id), ["slow", "fast"])
        XCTAssertTrue(attempts.first?.error?.technicalDescription.contains("timed out") == true)
        let startedIDs = await engine.startedReleaseIDs()
        XCTAssertEqual(startedIDs, ["slow", "fast"])
    }

    func testPlaybackDebugLoggerOnlyWritesWhenEnabled() async {
        let diagnostics = PlaybackPipelineRecordingDiagnostics()
        await PlaybackDebugLogger.disabled.log(
            diagnostics: diagnostics,
            event: "source.selected",
            metadata: ["releaseID": "off"]
        )
        await PlaybackDebugLogger(enabled: true).log(
            diagnostics: diagnostics,
            event: "source.selected",
            metadata: ["releaseID": "on"]
        )

        let events = await diagnostics.events()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.level, .debug)
        XCTAssertEqual(events.first?.subsystem, .playback)
        XCTAssertEqual(events.first?.metadata["event"], "source.selected")
        XCTAssertEqual(events.first?.metadata["releaseID"], "on")
    }

    func testPlaybackPipelineDebugTraceIncludesTorrentReadinessAndStreamURL() async throws {
        let diagnostics = PlaybackPipelineRecordingDiagnostics()
        let release = TorrentRelease(
            id: "debug",
            sourceId: "torrentio",
            sourceName: "Torrentio",
            title: "Debug Release",
            magnetURI: "magnet:?xt=urn:btih:debug",
            quality: .fullHD,
            seeders: 120
        )
        let pipeline = PlaybackPipeline(
            torrentEngine: FallbackRecordingTorrentEngine(preselectsFile: false),
            availabilityChecker: RecordingAvailabilityChecker(),
            debugLogger: PlaybackDebugLogger(enabled: true),
            diagnosticsService: diagnostics
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tmdb:movie:603",
                primaryRelease: release,
                bandwidthLimits: .unlimited
            )
        )

        guard case .ready(let source, _, _) = result else {
            return XCTFail("Expected ready playback source, got \(result)")
        }

        XCTAssertEqual(source.url.lastPathComponent, "debug.mkv")
        let events = await diagnostics.events()
        let eventsByName = Dictionary(uniqueKeysWithValues: events.compactMap { event -> (String, DiagnosticsEvent)? in
            guard let name = event.metadata["event"] else { return nil }
            return (name, event)
        })

        let sourceSelected = try XCTUnwrap(eventsByName["source.selected"])
        XCTAssertEqual(sourceSelected.metadata["sourceName"], "Torrentio")
        XCTAssertEqual(sourceSelected.metadata["infoHash"], "debug")

        let metadataReady = try XCTUnwrap(eventsByName["torrent.metadata.ready"])
        XCTAssertEqual(metadataReady.metadata["fileCount"], "1")
        XCTAssertEqual(metadataReady.metadata["peersCount"], "4")
        XCTAssertEqual(metadataReady.metadata["seedersCount"], "120")
        XCTAssertEqual(metadataReady.metadata["torrentState"], "streaming")

        let fileSelected = try XCTUnwrap(eventsByName["torrent.file.selected"])
        XCTAssertEqual(fileSelected.metadata["fileID"], "debug.mkv")
        XCTAssertEqual(fileSelected.metadata["fileName"], "debug.mkv")

        let streamURLReady = try XCTUnwrap(eventsByName["stream.url.ready"])
        XCTAssertEqual(streamURLReady.metadata["streamURL"], "file://<local-file>/debug.mkv")

        let streamReady = try XCTUnwrap(eventsByName["stream.ready"])
        XCTAssertEqual(streamReady.metadata["streamURL"], "file://<local-file>/debug.mkv")
    }

    func testPlaybackPipelineRejectsLocalTorrentStreamWhenStartupRangeUnavailable() async throws {
        let diagnostics = PlaybackPipelineRecordingDiagnostics()
        let localStreamURL = try XCTUnwrap(URL(string: "http://127.0.0.1:11470/stream/session-local/0"))
        let release = TorrentRelease(
            id: "local",
            sourceId: "torrentio",
            sourceName: "Torrentio",
            title: "Local Stream Release",
            magnetURI: "magnet:?xt=urn:btih:local",
            quality: .fullHD,
            seeders: 4
        )
        let checker = RecordingAvailabilityChecker(
            responses: ["0": .unavailable(reason: "HTTP 503 while waiting for first torrent piece")]
        )
        let pipeline = PlaybackPipeline(
            torrentEngine: FallbackRecordingTorrentEngine(
                preselectsFile: false,
                streamingURL: localStreamURL
            ),
            availabilityChecker: checker,
            debugLogger: PlaybackDebugLogger(enabled: true),
            diagnosticsService: diagnostics
        )

        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: "tmdb:movie:603",
                primaryRelease: release,
                bandwidthLimits: .unlimited
            )
        )

        guard case .failed(let error, _, let attempts) = result else {
            return XCTFail("Expected local torrent stream startup probe to fail, got \(result)")
        }

        XCTAssertEqual(attempts.map(\.release.id), [release.id])
        XCTAssertTrue(error.technicalDescription.contains("HTTP 503"))
        let checkedURLs = await checker.checkedURLs()
        XCTAssertEqual(checkedURLs, [localStreamURL])

        let events = await diagnostics.events()
        XCTAssertTrue(events.contains { $0.metadata["event"] == "stream.availability.start" })
        XCTAssertFalse(events.contains { $0.metadata["event"] == "stream.availability.skipped" })
    }

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

    func testProgressRecorderUsesSelectionContextForSeriesEpisode() async throws {
        let store = InMemoryPlaybackProgressStore()
        let recorder = PlaybackProgressRecorder(store: store, saveIntervalSeconds: 5)
        let context = PlaybackSelectionContext(
            mediaID: "tt0944947",
            displayTitle: "Game of Thrones",
            mediaKind: .series,
            seasonNumber: 1,
            episodeNumber: 1,
            episodeID: "tt0944947:1:1"
        )
        let source = PlaybackMediaSource(
            id: context.episodeID!,
            title: context.displayTitle,
            url: URL(fileURLWithPath: "/tmp/got-s1e1.mkv"),
            selectionContext: context
        )

        try await recorder.recordIfNeeded(
            status: PlaybackStatus(media: source, state: .playing, currentTime: 12, duration: 60),
            force: true
        )

        let records = await store.records
        XCTAssertEqual(records.first?.mediaID, "tt0944947")
        XCTAssertEqual(records.first?.episodeID, "tt0944947:1:1")
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

private actor RecordingTimelineFrameGenerator: TimelineFrameGenerating {
    private let data: Data
    private var times: [Double] = []

    init(data: Data) {
        self.data = data
    }

    func frameData(for url: URL, at seconds: Double, width: Int, height: Int) async throws -> Data {
        times.append(seconds)
        return data
    }

    func generatedTimes() -> [Double] {
        times
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

private actor FallbackRecordingTorrentEngine: TorrentEngineProtocol {
    private let failures: [String: Error]
    private let startDelays: [String: UInt64]
    private let preselectsFile: Bool
    private let streamingURL: URL?
    private let filesByReleaseID: [String: [TorrentFile]]
    private let statusByReleaseID: [String: TorrentStatus]
    private var startedIDs: [String] = []
    private var removedIDs: [String] = []
    private var selectedIDs: [String] = []
    private var sequentialCalls: [String] = []
    private var priorityCallValues: [String] = []
    private var sessions: [String: TorrentSession] = [:]
    private var releaseIDsBySessionID: [String: String] = [:]
    private var activeStartCount = 0
    private var maxActiveStartCount = 0

    init(
        failures: [String: Error] = [:],
        startDelays: [String: UInt64] = [:],
        preselectsFile: Bool = true,
        streamingURL: URL? = nil,
        filesByReleaseID: [String: [TorrentFile]] = [:],
        statusByReleaseID: [String: TorrentStatus] = [:]
    ) {
        self.failures = failures
        self.startDelays = startDelays
        self.preselectsFile = preselectsFile
        self.streamingURL = streamingURL
        self.filesByReleaseID = filesByReleaseID
        self.statusByReleaseID = statusByReleaseID
    }

    func searchReleases(for item: MediaItem) async throws -> [TorrentRelease] {
        []
    }

    func startStreaming(_ release: TorrentRelease) async throws -> TorrentSession {
        activeStartCount += 1
        maxActiveStartCount = max(maxActiveStartCount, activeStartCount)
        defer { activeStartCount -= 1 }
        startedIDs.append(release.id)
        let fileID = "\(release.id).mkv"
        let session = TorrentSession(
            id: "session-\(release.id)",
            releaseId: release.id,
            sourceId: release.sourceId,
            magnetURI: release.magnetURI,
            torrentFileURL: release.torrentFileURL,
            storageURL: URL(fileURLWithPath: "/tmp/session-\(release.id)", isDirectory: true),
            selectedFileId: preselectsFile ? fileID : nil,
            streamingURL: preselectsFile ? (streamingURL ?? URL(fileURLWithPath: "/tmp/\(fileID)")) : nil,
            isSequentialDownloadEnabled: true
        )
        sessions[session.id] = session
        releaseIDsBySessionID[session.id] = release.id
        if let delay = startDelays[release.id] {
            try await Task.sleep(nanoseconds: delay)
        }
        return session
    }

    func remove(sessionId: String, deleteFiles: Bool) async throws {
        if sessions.removeValue(forKey: sessionId) == nil {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }
        removedIDs.append(sessionId)
    }

    func getFileList(sessionId: String) async throws -> [TorrentFile] {
        guard let session = sessions[sessionId],
              let releaseID = releaseIDsBySessionID[session.id]
        else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }
        let fileID = session.selectedFileId ?? "\(releaseID).mkv"
        if let files = filesByReleaseID[releaseID] {
            return files
        }
        return [
            TorrentFile(
                id: fileID,
                path: fileID,
                name: fileID,
                lengthBytes: 4_000_000_000,
                isMediaFile: true,
                priority: .high
            )
        ]
    }

    func selectMediaFile(sessionId: String, fileId: String) async throws {
        guard var session = sessions[sessionId] else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }
        session.selectedFileId = fileId
        selectedIDs.append(fileId)
        session.streamingURL = streamingURL ?? URL(fileURLWithPath: "/tmp/\(fileId)")
        sessions[sessionId] = session
    }

    func setBandwidthLimits(sessionId: String, _ limits: TorrentBandwidthLimits) async throws {
        _ = sessionId
        _ = limits
    }

    func setSequentialDownload(sessionId: String, enabled: Bool) async throws {
        guard var session = sessions[sessionId] else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }
        session.isSequentialDownloadEnabled = enabled
        sessions[sessionId] = session
        sequentialCalls.append("\(sessionId):\(enabled)")
    }

    func setDownloadPriority(sessionId: String, fileId: String, priority: TorrentFilePriority) async throws {
        guard sessions[sessionId] != nil else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }
        priorityCallValues.append("\(fileId):\(priority)")
    }

    func getStreamingURL(sessionId: String) async throws -> URL {
        if let releaseID = releaseIDsBySessionID[sessionId], let failure = failures[releaseID] {
            throw failure
        }
        guard let url = sessions[sessionId]?.streamingURL else {
            throw TorrentEngineError.streamingURLUnavailable(sessionId: sessionId)
        }
        return url
    }

    func getStatus(sessionId: String) async throws -> TorrentStatus {
        guard let session = sessions[sessionId] else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }
        if let releaseID = releaseIDsBySessionID[sessionId],
           let status = statusByReleaseID[releaseID] {
            return status
        }
        return TorrentStatus(
            sessionId: session.id,
            state: .streaming,
            progress: TorrentProgress(bufferedBytes: 1_000_000),
            health: TorrentHealth(seeders: 120, connectedPeers: 4, availability: 1),
            selectedFileId: session.selectedFileId,
            isSequentialDownloadEnabled: true,
            streamingURL: session.streamingURL
        )
    }

    func startedReleaseIDs() -> [String] {
        startedIDs
    }

    func removedSessionIDs() -> [String] {
        removedIDs
    }

    func selectedFileIDs() -> [String] {
        selectedIDs
    }

    func sequentialDownloadCalls() -> [String] {
        sequentialCalls
    }

    func priorityCalls() -> [String] {
        priorityCallValues
    }

    func maxConcurrentStarts() -> Int {
        maxActiveStartCount
    }
}

private actor RecordingAvailabilityChecker: PlaybackStreamAvailabilityChecking {
    private var urls: [URL] = []
    private let responses: [String: PlaybackStreamAvailability]

    init(responses: [String: PlaybackStreamAvailability] = [:]) {
        self.responses = responses
    }

    func check(_ url: URL, timeoutSeconds: TimeInterval) async -> PlaybackStreamAvailability {
        urls.append(url)
        return responses[url.lastPathComponent] ?? .available
    }

    func checkedURLs() -> [URL] {
        urls
    }
}

private actor PlaybackPipelineRecordingDiagnostics: DiagnosticsServiceProtocol {
    private var recordedEvents: [DiagnosticsEvent] = []

    func log(level: DiagnosticsLogLevel, subsystem: DiagnosticsSubsystem, message: String, metadata: [String: String]) async {
        recordedEvents.append(DiagnosticsEvent(level: level, subsystem: subsystem, message: message, metadata: metadata))
    }

    func exportDiagnostics() async -> String {
        "diagnostics.zip"
    }

    func recentEvents(limit: Int) async -> [DiagnosticsEvent] {
        Array(recordedEvents.suffix(limit))
    }

    func events() -> [DiagnosticsEvent] {
        recordedEvents
    }
}
