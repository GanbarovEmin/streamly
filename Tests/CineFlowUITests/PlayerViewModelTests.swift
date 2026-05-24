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
    func testPlayerViewModelAppliesAndPersistsComfortPreferences() async throws {
        let settingsRepository = CoreMockSettingsRepository(
            settings: AppSettings(
                playback: PlaybackSettings(
                    preferredAudioLanguages: ["ru", "en"],
                    defaultFullscreen: true,
                    rememberedVolume: 0.42,
                    rememberedAudioLanguage: "ru",
                    rememberedSubtitleLanguage: "en",
                    subtitlesEnabled: true,
                    playbackSpeed: 1.5,
                    audioBoost: 1.5,
                    dimBackgroundAroundVideo: true
                )
            )
        )
        await settingsRepository.setSubtitleSettings(
            SubtitleSettings(
                languagePreference: SubtitleLanguagePreference(["en", "ru"]),
                fontSize: 52,
                subtitleDelaySeconds: 0.5,
                visualStyle: .highContrast
            )
        )
        let viewModel = PlayerViewModel(
            service: MockPlaybackService(),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:603",
                title: "The Matrix",
                url: URL(fileURLWithPath: "/tmp/matrix.mkv")
            ),
            settingsRepository: settingsRepository
        )

        await viewModel.start()

        XCTAssertEqual(viewModel.status.volume, 0.42, accuracy: 0.001)
        XCTAssertEqual(viewModel.status.playbackSpeed, 1.5, accuracy: 0.001)
        XCTAssertEqual(viewModel.status.audioBoost, 1.5, accuracy: 0.001)
        XCTAssertEqual(viewModel.status.subtitleDelaySeconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(viewModel.status.subtitleFontSize, 52, accuracy: 0.001)
        XCTAssertEqual(viewModel.status.subtitleStyle, .highContrast)
        XCTAssertEqual(viewModel.status.selectedAudioTrackId, "audio-ru")
        XCTAssertEqual(viewModel.status.selectedSubtitleTrackId, "sub-en")
        XCTAssertTrue(viewModel.status.isFullscreen)
        XCTAssertTrue(viewModel.dimBackgroundAroundVideo)

        await viewModel.setVolume(0.66)
        await viewModel.setPlaybackSpeed(1.25)
        await viewModel.setAudioBoost(2.0)
        await viewModel.selectAudioTrack(id: "audio-en")
        await viewModel.disableSubtitles()
        await viewModel.toggleFullscreen()
        await viewModel.toggleDimBackground()

        let persisted = await settingsRepository.appSettings
        XCTAssertEqual(persisted.playback.rememberedVolume, 0.66, accuracy: 0.001)
        XCTAssertEqual(persisted.playback.playbackSpeed, 1.25, accuracy: 0.001)
        XCTAssertEqual(persisted.playback.audioBoost, 2.0, accuracy: 0.001)
        XCTAssertEqual(persisted.playback.rememberedAudioLanguage, "en")
        XCTAssertFalse(persisted.playback.subtitlesEnabled)
        XCTAssertFalse(persisted.playback.defaultFullscreen)
        XCTAssertFalse(persisted.playback.dimBackgroundAroundVideo)
    }

    @MainActor
    func testTimelinePreviewLoadsLazyThumbnailForLocalMedia() async throws {
        let settingsRepository = CoreMockSettingsRepository(
            settings: AppSettings(playback: PlaybackSettings(enableTimelinePreviews: true))
        )
        let previewService = RecordingTimelinePreviewService(
            preview: TimelinePreview(
                mediaID: "tmdb:movie:603",
                timeSeconds: 40,
                imageData: Data("jpeg-frame".utf8),
                contentType: "image/jpeg",
                source: .generated
            )
        )
        let viewModel = PlayerViewModel(
            service: ConfigurableSubtitlePlaybackService(audioTracks: [], subtitleTracks: []),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:603",
                title: "The Matrix",
                url: URL(fileURLWithPath: "/tmp/matrix.mkv")
            ),
            settingsRepository: settingsRepository,
            timelinePreviewService: previewService
        )

        await viewModel.start()
        await viewModel.loadTimelinePreview(at: 42)

        XCTAssertEqual(viewModel.timelinePreview.timeLabel, "0:42")
        XCTAssertEqual(viewModel.timelinePreview.imageData, Data("jpeg-frame".utf8))
        XCTAssertFalse(viewModel.timelinePreview.isLoading)
        let requests = await previewService.requests()
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.mediaID, "tmdb:movie:603")
        XCTAssertEqual(request.timeSeconds, 42, accuracy: 0.001)
        XCTAssertEqual(request.isPlaybackActive, true)
    }

    @MainActor
    func testTimelinePreviewRespectsDisabledSettingAndBufferedAvailability() async throws {
        let previewService = RecordingTimelinePreviewService(preview: nil)
        let disabledSettings = CoreMockSettingsRepository(
            settings: AppSettings(playback: PlaybackSettings(enableTimelinePreviews: false))
        )
        let disabledViewModel = PlayerViewModel(
            service: ConfigurableSubtitlePlaybackService(audioTracks: [], subtitleTracks: []),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:disabled-preview",
                title: "Disabled",
                url: URL(fileURLWithPath: "/tmp/disabled.mkv")
            ),
            settingsRepository: disabledSettings,
            timelinePreviewService: previewService
        )

        await disabledViewModel.start()
        await disabledViewModel.loadTimelinePreview(at: 24)

        XCTAssertTrue(disabledViewModel.timelinePreview.isHidden)
        let disabledRequests = await previewService.requests()
        XCTAssertEqual(disabledRequests.count, 0)

        let remoteViewModel = PlayerViewModel(
            service: ConfigurableSubtitlePlaybackService(
                audioTracks: [],
                subtitleTracks: [],
                duration: 100,
                bufferingState: .buffering(progress: 0.2)
            ),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:remote-preview",
                title: "Remote",
                url: URL(string: "https://streamly.local/movie.mkv")!
            ),
            settingsRepository: CoreMockSettingsRepository(
                settings: AppSettings(playback: PlaybackSettings(enableTimelinePreviews: true))
            ),
            timelinePreviewService: previewService
        )

        await remoteViewModel.start()
        await remoteViewModel.loadTimelinePreview(at: 80)

        XCTAssertTrue(remoteViewModel.timelinePreview.isUnavailable)
        XCTAssertEqual(remoteViewModel.timelinePreview.message, "Preview unavailable")
        let remoteRequests = await previewService.requests()
        XCTAssertEqual(remoteRequests.count, 0)
    }

    @MainActor
    func testLocalSubtitleSelectionPublishesActiveCueForCustomPlayerOverlay() async throws {
        let subtitleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("streamly-subtitle-\(UUID().uuidString).srt")
        try """
        1
        00:00:01,000 --> 00:00:03,500
        First line
        Second line

        2
        00:00:05,000 --> 00:00:06,000
        Later cue
        """.write(to: subtitleURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: subtitleURL) }

        let viewModel = PlayerViewModel(
            service: ConfigurableSubtitlePlaybackService(audioTracks: [], subtitleTracks: [], duration: 120),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:subtitle-overlay",
                title: "Subtitle Overlay",
                url: URL(fileURLWithPath: "/tmp/subtitle-overlay.mkv")
            )
        )

        await viewModel.start()
        await viewModel.loadLocalSubtitle(url: subtitleURL)
        await viewModel.seek(to: 2)

        XCTAssertEqual(viewModel.activeSubtitleText, "First line\nSecond line")

        await viewModel.seek(to: 4)

        XCTAssertNil(viewModel.activeSubtitleText)
    }

    @MainActor
    func testSmartAudioSelectsPreferredLanguageAndBestAvailableQuality() async throws {
        let settingsRepository = CoreMockSettingsRepository(
            settings: AppSettings(
                playback: PlaybackSettings(
                    preferredAudioOrder: .russianEnglishOriginal,
                    preferredAudioLanguages: ["ru", "en"]
                )
            )
        )
        let viewModel = PlayerViewModel(
            service: ConfigurableSubtitlePlaybackService(
                audioTracks: [
                    AudioTrack(id: "audio-ru-stereo", languageCode: "ru", displayName: "Russian Stereo", codec: "AAC", channels: "2.0"),
                    AudioTrack(id: "audio-en-atmos", languageCode: "en", displayName: "English Atmos", codec: "Dolby TrueHD", channels: "7.1"),
                    AudioTrack(id: "audio-ru-dts", languageCode: "ru", displayName: "Russian DTS", codec: "DTS-HD MA", channels: "5.1")
                ],
                subtitleTracks: []
            ),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:603",
                title: "The Matrix",
                url: URL(fileURLWithPath: "/tmp/matrix.mkv")
            ),
            settingsRepository: settingsRepository
        )

        await viewModel.start()

        XCTAssertEqual(viewModel.status.selectedAudioTrackId, "audio-ru-dts")
        XCTAssertEqual(viewModel.audioTracks.first(where: { $0.id == "audio-ru-dts" })?.qualityLabel, "5.1 DTS")
        XCTAssertTrue(viewModel.audioSelectionSummary.contains("Russian"))
        XCTAssertTrue(viewModel.audioSelectionSummary.contains("5.1 DTS"))
    }

    @MainActor
    func testSmartAudioFallsBackToEnglishThenOriginalPredictably() async throws {
        let settingsRepository = CoreMockSettingsRepository(
            settings: AppSettings(
                playback: PlaybackSettings(
                    preferredAudioOrder: .russianEnglishOriginal,
                    preferredAudioLanguages: ["ru", "en"]
                )
            )
        )
        let englishViewModel = PlayerViewModel(
            service: ConfigurableSubtitlePlaybackService(
                audioTracks: [
                    AudioTrack(id: "audio-en", languageCode: "en", displayName: "English", codec: "AAC", channels: "5.1"),
                    AudioTrack(id: "audio-ja-original", languageCode: "ja", displayName: "Original Japanese", codec: "AAC", channels: "2.0", isOriginal: true)
                ],
                subtitleTracks: []
            ),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:english-fallback",
                title: "Fallback",
                url: URL(fileURLWithPath: "/tmp/fallback.mkv")
            ),
            settingsRepository: settingsRepository
        )

        await englishViewModel.start()

        XCTAssertEqual(englishViewModel.status.selectedAudioTrackId, "audio-en")
        XCTAssertTrue(englishViewModel.audioSelectionSummary.contains("fallback English"))

        let originalViewModel = PlayerViewModel(
            service: ConfigurableSubtitlePlaybackService(
                audioTracks: [
                    AudioTrack(id: "audio-ja-original", languageCode: "ja", displayName: "Original Japanese", codec: "AAC", channels: "2.0", isOriginal: true),
                    AudioTrack(id: "audio-de", languageCode: "de", displayName: "German", codec: "AAC", channels: "5.1")
                ],
                subtitleTracks: []
            ),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:original-fallback",
                title: "Fallback Original",
                url: URL(fileURLWithPath: "/tmp/original.mkv")
            ),
            settingsRepository: settingsRepository
        )

        await originalViewModel.start()

        XCTAssertEqual(originalViewModel.status.selectedAudioTrackId, "audio-ja-original")
        XCTAssertTrue(originalViewModel.audioSelectionSummary.contains("fallback Original"))
    }

    @MainActor
    func testManualAudioOverrideIsRememberedPerMedia() async throws {
        let settingsRepository = CoreMockSettingsRepository(
            settings: AppSettings(playback: PlaybackSettings(preferredAudioOrder: .russianEnglishOriginal))
        )
        let source = PlaybackMediaSource(
            id: "tmdb:movie:603",
            title: "The Matrix",
            url: URL(fileURLWithPath: "/tmp/matrix.mkv")
        )
        let firstViewModel = PlayerViewModel(
            service: ConfigurableSubtitlePlaybackService(
                audioTracks: [
                    AudioTrack(id: "audio-ru", languageCode: "ru", displayName: "Russian", codec: "AAC", channels: "5.1"),
                    AudioTrack(id: "audio-en", languageCode: "en", displayName: "English", codec: "Dolby Digital", channels: "5.1")
                ],
                subtitleTracks: []
            ),
            mediaSource: source,
            settingsRepository: settingsRepository
        )

        await firstViewModel.start()
        await firstViewModel.selectAudioTrack(id: "audio-en")

        let persisted = await settingsRepository.appSettings
        XCTAssertEqual(persisted.playback.manualAudioOverridesByMediaID[source.id]?.trackID, "audio-en")

        let secondViewModel = PlayerViewModel(
            service: ConfigurableSubtitlePlaybackService(
                audioTracks: [
                    AudioTrack(id: "audio-ru", languageCode: "ru", displayName: "Russian", codec: "AAC", channels: "5.1"),
                    AudioTrack(id: "audio-en", languageCode: "en", displayName: "English", codec: "Dolby Digital", channels: "5.1")
                ],
                subtitleTracks: []
            ),
            mediaSource: source,
            settingsRepository: settingsRepository
        )

        await secondViewModel.start()

        XCTAssertEqual(secondViewModel.status.selectedAudioTrackId, "audio-en")
        XCTAssertTrue(secondViewModel.audioMenuTracks.contains(where: { $0.id == "audio-en" && $0.qualityLabel == "5.1 Dolby" }))
    }

    @MainActor
    func testPlayerViewModelSupportsChaptersSubtitleStyleAndKeyboardComfortControls() async throws {
        let settingsRepository = CoreMockSettingsRepository()
        let viewModel = PlayerViewModel(
            service: MockPlaybackService(),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:603",
                title: "The Matrix",
                url: URL(fileURLWithPath: "/tmp/matrix.mkv")
            ),
            settingsRepository: settingsRepository
        )

        await viewModel.start()
        XCTAssertEqual(viewModel.chapters.map(\.title), ["Opening", "Middle", "Finale"])

        await viewModel.seekToChapter(viewModel.chapters[1])
        XCTAssertEqual(viewModel.status.currentTime, 600)

        await viewModel.handleShortcut(.speedUp)
        XCTAssertEqual(viewModel.status.playbackSpeed, 1.25, accuracy: 0.001)

        await viewModel.handleShortcut(.audioBoostUp)
        XCTAssertEqual(viewModel.status.audioBoost, 1.25, accuracy: 0.001)

        await viewModel.setSubtitleStyle(.cinematic)
        await viewModel.adjustSubtitleDelay(by: 0.25)

        let subtitles = await settingsRepository.subtitleSettings
        XCTAssertEqual(subtitles.visualStyle, .cinematic)
        XCTAssertEqual(subtitles.subtitleDelaySeconds, 0.25, accuracy: 0.001)
    }

    @MainActor
    func testSmartSubtitlesSelectPreferredEmbeddedTrackByLanguagePriority() async throws {
        let settingsRepository = CoreMockSettingsRepository()
        let viewModel = PlayerViewModel(
            service: MockPlaybackService(),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:603",
                title: "The Matrix",
                url: URL(fileURLWithPath: "/tmp/matrix.mkv")
            ),
            settingsRepository: settingsRepository
        )

        await viewModel.start()

        XCTAssertEqual(viewModel.status.selectedSubtitleTrackId, "sub-ru")
    }

    @MainActor
    func testSmartSubtitlesFallsBackToOpenSubtitlesWhenNoEmbeddedOrLocalTrackExists() async throws {
        let settingsRepository = CoreMockSettingsRepository()
        let subtitleService = SmartSubtitleServiceMock(
            onlineResults: [
                SubtitleSearchResult(
                    id: "online-ru",
                    title: "Arrival Russian",
                    languageCode: "ru",
                    source: .openSubtitles,
                    score: 10,
                    downloadURL: URL(string: "https://example.test/arrival-ru.srt")
                )
            ],
            downloadedTrack: SubtitleTrack(
                id: "cached:arrival-ru",
                languageCode: "ru",
                displayName: "Arrival Russian",
                source: .openSubtitles,
                localURL: URL(fileURLWithPath: "/tmp/arrival-ru.srt")
            )
        )
        let playbackService = ConfigurableSubtitlePlaybackService(
            audioTracks: [AudioTrack(id: "audio-ru", languageCode: "ru", displayName: "Russian")],
            subtitleTracks: []
        )
        let viewModel = PlayerViewModel(
            service: playbackService,
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:329865",
                title: "Arrival",
                url: URL(string: "http://127.0.0.1:49152/stream.mkv")!
            ),
            subtitleService: subtitleService,
            settingsRepository: settingsRepository
        )

        await viewModel.start()

        XCTAssertEqual(viewModel.status.selectedSubtitleTrackId, "cached:arrival-ru")
        XCTAssertEqual(viewModel.subtitleTracks.map(\.id), ["cached:arrival-ru"])
        let searchCount = await subtitleService.searchCountValue()
        XCTAssertEqual(searchCount, 1)
    }

    @MainActor
    func testSmartSubtitlesHonorsDisabledAutoSearchSetting() async throws {
        let settingsRepository = CoreMockSettingsRepository()
        await settingsRepository.setSubtitleSettings(SubtitleSettings(autoSearchSubtitles: false))
        let subtitleService = SmartSubtitleServiceMock(
            onlineResults: [
                SubtitleSearchResult(
                    id: "online-ru",
                    title: "Arrival Russian",
                    languageCode: "ru",
                    source: .openSubtitles,
                    score: 10
                )
            ]
        )
        let viewModel = PlayerViewModel(
            service: ConfigurableSubtitlePlaybackService(
                audioTracks: [AudioTrack(id: "audio-ru", languageCode: "ru", displayName: "Russian")],
                subtitleTracks: []
            ),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:329865",
                title: "Arrival",
                url: URL(fileURLWithPath: "/tmp/arrival.mkv")
            ),
            subtitleService: subtitleService,
            settingsRepository: settingsRepository
        )

        await viewModel.start()

        XCTAssertNil(viewModel.status.selectedSubtitleTrackId)
        let searchCount = await subtitleService.searchCountValue()
        XCTAssertEqual(searchCount, 0)
    }

    @MainActor
    func testSmartSubtitlesOnlyForeignAudioKeepsRegularSubtitlesOffButAllowsForcedTrack() async throws {
        let settingsRepository = CoreMockSettingsRepository(
            settings: AppSettings(playback: PlaybackSettings(preferredAudioLanguages: ["ru", "en"]))
        )
        await settingsRepository.setSubtitleSettings(
            SubtitleSettings(
                languagePreference: SubtitleLanguagePreference(["ru", "en"]),
                autoMode: .onlyForeignAudio
            )
        )
        let viewModel = PlayerViewModel(
            service: ConfigurableSubtitlePlaybackService(
                audioTracks: [AudioTrack(id: "audio-ru", languageCode: "ru", displayName: "Russian")],
                subtitleTracks: [
                    SubtitleTrack(id: "sub-en", languageCode: "en", displayName: "English", source: .embedded),
                    SubtitleTrack(id: "sub-forced", languageCode: "en", displayName: "English forced", source: .embedded)
                ]
            ),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:329865",
                title: "Arrival",
                url: URL(fileURLWithPath: "/tmp/arrival.mkv")
            ),
            settingsRepository: settingsRepository
        )

        await viewModel.start()

        XCTAssertEqual(viewModel.status.selectedSubtitleTrackId, "sub-forced")
    }

    @MainActor
    func testManualSubtitleOverrideIsRememberedPerMedia() async throws {
        let settingsRepository = CoreMockSettingsRepository()
        let source = PlaybackMediaSource(
            id: "tmdb:movie:603",
            title: "The Matrix",
            url: URL(fileURLWithPath: "/tmp/matrix.mkv")
        )
        let firstViewModel = PlayerViewModel(
            service: MockPlaybackService(),
            mediaSource: source,
            settingsRepository: settingsRepository
        )

        await firstViewModel.start()
        await firstViewModel.selectSubtitleTrack(id: "sub-en")

        let persistedSubtitles = await settingsRepository.subtitleSettings
        XCTAssertEqual(persistedSubtitles.manualOverridesByMediaID[source.id]?.trackID, "sub-en")

        let secondViewModel = PlayerViewModel(
            service: MockPlaybackService(),
            mediaSource: source,
            settingsRepository: settingsRepository
        )
        await secondViewModel.start()

        XCTAssertEqual(secondViewModel.status.selectedSubtitleTrackId, "sub-en")
    }

    @MainActor
    func testSubtitleMenuGroupsTracksBySourceAndExposesSearchActions() async throws {
        let subtitleService = SmartSubtitleServiceMock(
            localTracks: [
                SubtitleTrack(
                    id: "local:/tmp/arrival.en.srt",
                    languageCode: "en",
                    displayName: "arrival.en.srt",
                    source: .localFile,
                    localURL: URL(fileURLWithPath: "/tmp/arrival.en.srt")
                )
            ],
            onlineResults: [
                SubtitleSearchResult(
                    id: "online-ru",
                    title: "Arrival RU",
                    languageCode: "ru",
                    source: .openSubtitles,
                    score: 10,
                    downloadURL: URL(string: "https://example.test/arrival-ru.srt")
                )
            ]
        )
        let viewModel = PlayerViewModel(
            service: ConfigurableSubtitlePlaybackService(
                audioTracks: [AudioTrack(id: "audio-ru", languageCode: "ru", displayName: "Russian")],
                subtitleTracks: [
                    SubtitleTrack(id: "embedded-ru", languageCode: "ru", displayName: "Russian embedded", source: .embedded)
                ]
            ),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:329865",
                title: "Arrival",
                url: URL(fileURLWithPath: "/tmp/arrival.mkv")
            ),
            subtitleService: subtitleService,
            settingsRepository: CoreMockSettingsRepository()
        )

        await viewModel.start()
        await viewModel.reloadLocalSubtitles()
        await viewModel.findOnlineSubtitles()

        XCTAssertEqual(viewModel.embeddedSubtitleTracks.map(\.id), ["embedded-ru"])
        XCTAssertEqual(viewModel.localSubtitleTracks.map(\.id), ["local:/tmp/arrival.en.srt"])
        XCTAssertEqual(viewModel.onlineSubtitleTracks.map(\.id), [])
        XCTAssertEqual(viewModel.onlineSubtitleResults.map(\.id), ["online-ru"])
    }

    @MainActor
    func testSubtitleDelayQuickControlsUseHalfSecondStepAndReset() async throws {
        let settingsRepository = CoreMockSettingsRepository()
        let viewModel = PlayerViewModel(
            service: MockPlaybackService(),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:603",
                title: "The Matrix",
                url: URL(fileURLWithPath: "/tmp/matrix.mkv")
            ),
            settingsRepository: settingsRepository
        )

        await viewModel.start()
        await viewModel.handleShortcut(.subtitleDelayUp)
        await viewModel.handleShortcut(.subtitleDelayUp)
        XCTAssertEqual(viewModel.status.subtitleDelaySeconds, 1.0, accuracy: 0.001)

        await viewModel.handleShortcut(.subtitleDelayDown)
        XCTAssertEqual(viewModel.status.subtitleDelaySeconds, 0.5, accuracy: 0.001)

        await viewModel.resetSubtitleDelay()
        XCTAssertEqual(viewModel.status.subtitleDelaySeconds, 0, accuracy: 0.001)
        let persisted = await settingsRepository.subtitleSettings
        XCTAssertEqual(persisted.subtitleDelaySeconds, 0, accuracy: 0.001)
    }

    @MainActor
    func testOnlineSubtitleSearchErrorDoesNotBreakPlayback() async throws {
        let diagnostics = RecordingDiagnosticsService()
        let viewModel = PlayerViewModel(
            service: MockPlaybackService(),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:603",
                title: "The Matrix",
                url: URL(fileURLWithPath: "/tmp/matrix.mkv")
            ),
            subtitleService: ThrowingSubtitleServiceMock(),
            diagnosticsService: diagnostics
        )

        await viewModel.start()
        await viewModel.findOnlineSubtitles()

        if case .playing = viewModel.status.state {
        } else {
            XCTFail("Expected playback to remain playing, got \(viewModel.status.state)")
        }
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.onlineSubtitleResults.isEmpty)
        let events = await diagnostics.recentEvents(limit: 1)
        XCTAssertEqual(events.first?.subsystem, .subtitle)
        XCTAssertEqual(events.first?.metadata["operation"], "findOnlineSubtitles")
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
    func testResumePromptDismissesImmediatelyEvenWhenSeekFails() async throws {
        let service = SeekFailingPlaybackService()
        let source = PlaybackMediaSource(
            id: "tmdb:movie:603",
            title: "The Matrix",
            url: URL(fileURLWithPath: "/tmp/matrix.mkv")
        )
        let repository = InMemoryPlayerProgressRepository(records: [
            PlaybackProgress(mediaID: source.id, positionSeconds: 42, durationSeconds: 120)
        ])
        let viewModel = PlayerViewModel(
            service: service,
            mediaSource: source,
            progressRepository: repository
        )

        await viewModel.start()
        XCTAssertTrue(viewModel.shouldOfferResume)

        await viewModel.continueFromResume()

        XCTAssertFalse(viewModel.shouldOfferResume)
        XCTAssertNotNil(viewModel.errorMessage)
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

        for _ in 0..<50 where viewModel.controlsAreVisible {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertFalse(viewModel.controlsAreVisible)
    }

    @MainActor
    func testPlayerViewModelKeepsControlsVisibleWhenPointerActivityResetsAutoHideTimer() async throws {
        let viewModel = PlayerViewModel(
            service: MockPlaybackService(),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:movie:603",
                title: "The Matrix",
                url: URL(fileURLWithPath: "/tmp/matrix.mkv")
            )
        )

        viewModel.showControlsTemporarily(autoHideAfter: 0.5)
        try await Task.sleep(nanoseconds: 50_000_000)
        viewModel.showControlsTemporarily(autoHideAfter: 0.5)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(viewModel.controlsAreVisible)

        for _ in 0..<50 where viewModel.controlsAreVisible {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

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
        XCTAssertEqual(viewModel.nextEpisodeCountdownSeconds, 10)

        viewModel.cancelNextEpisodeCountdown()

        XCTAssertNil(viewModel.nextEpisodePrompt)
        XCTAssertNil(viewModel.nextEpisodeCountdownSeconds)
    }

    @MainActor
    func testPlayerViewModelDoesNotStartNextEpisodeCountdownWhenAutoplayIsDisabled() async throws {
        let settingsRepository = CoreMockSettingsRepository(
            settings: AppSettings(playback: PlaybackSettings(autoplayNextEpisode: false))
        )
        let viewModel = PlayerViewModel(
            service: CompletingPlaybackService(),
            mediaSource: PlaybackMediaSource(
                id: "tmdb:series:1399:s1e1",
                title: "Winter Is Coming",
                url: URL(fileURLWithPath: "/tmp/got-s1e1.mkv")
            ),
            settingsRepository: settingsRepository,
            nextEpisodePrompt: PlayerNextEpisodePrompt(
                title: "S01E02 The Kingsroad",
                subtitle: "Next Episode · 56m"
            )
        )

        await viewModel.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.nextEpisodePrompt?.title, "S01E02 The Kingsroad")
        XCTAssertNil(viewModel.nextEpisodeCountdownSeconds)
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
    func testBufferingPresentationCarriesSelectionLogoURL() async throws {
        let logoURL = try XCTUnwrap(URL(string: "https://images.metahub.space/logo/medium/tt0133093/img"))
        let release = TorrentRelease(
            id: "release-logo",
            title: "Release",
            quality: .fullHD,
            seeders: 140,
            availability: 1
        )
        let context = PlaybackSelectionContext(
            mediaID: "imdb:movie:tt0133093",
            displayTitle: "The Matrix",
            mediaKind: .movie,
            logoURL: logoURL
        )
        let viewModel = PlayerViewModel(
            service: BufferingPlaybackService(release: release),
            mediaSource: PlaybackMediaSource(release: release, selectionContext: context)
        )

        await viewModel.start()

        XCTAssertEqual(viewModel.bufferingPresentation.logoURL, logoURL)
    }

    @MainActor
    func testBufferingPresentationShowsLiveTorrentTransferDetails() async throws {
        let release = TorrentRelease(
            id: "release",
            title: "Release",
            quality: .ultraHD,
            seeders: 358,
            availability: 1
        )
        let session = TorrentSession(
            id: "session-transfer",
            releaseId: release.id,
            sourceId: release.sourceId,
            magnetURI: release.magnetURI,
            storageURL: URL(fileURLWithPath: "/tmp/streamly-test-cache"),
            selectedFileId: "movie.mkv",
            streamingURL: URL(string: "http://127.0.0.1:11470/stream/session-transfer/movie.mkv"),
            isSequentialDownloadEnabled: true
        )
        let torrentStatus = TorrentStatus(
            sessionId: session.id,
            state: .streaming,
            progress: TorrentProgress(
                downloadedBytes: 1_200_000_000,
                totalBytes: 12_000_000_000,
                bufferedBytes: PlayerViewModel.startupPlayableBufferTargetBytes / 2,
                downloadSpeedBytesPerSecond: 3_400_000,
                uploadSpeedBytesPerSecond: 128_000
            ),
            health: TorrentHealth(seeders: 358, leechers: 12, connectedPeers: 42, availability: 2.0),
            selectedFileId: "movie.mkv",
            isSequentialDownloadEnabled: true,
            streamingURL: session.streamingURL
        )
        let viewModel = PlayerViewModel(
            service: BufferingPlaybackService(release: release),
            mediaSource: PlaybackMediaSource(release: release),
            torrentEngine: StaticTorrentStatusEngine(status: torrentStatus),
            torrentSession: session
        )

        await viewModel.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        let presentation = viewModel.bufferingPresentation
        XCTAssertEqual(try XCTUnwrap(presentation.progress), 0.5, accuracy: 0.001)
        XCTAssertTrue(presentation.message.contains("50%"))
        XCTAssertTrue(presentation.primaryDetails.contains(where: { $0.contains("Download speed:") && $0.contains("/s") }))
        XCTAssertTrue(presentation.primaryDetails.contains(where: { $0.contains("Loaded:") && $0.contains("GB") && $0.contains("(10%)") }))
        XCTAssertTrue(presentation.primaryDetails.contains(where: { $0.contains("Playable start buffer:") && $0.contains("1.0 MB") }))
        XCTAssertTrue(presentation.primaryDetails.contains(where: { $0.contains("Full file ETA:") }))
        XCTAssertFalse((presentation.primaryDetails + presentation.advancedDetails).contains(where: { $0.contains("unavailable") }))

        viewModel.setAdvancedDebugVisible(true)

        XCTAssertTrue(viewModel.bufferingPresentation.advancedDetails.contains(where: { $0.contains("Peers: 42") }))
        XCTAssertTrue(viewModel.bufferingPresentation.advancedDetails.contains(where: { $0.contains("Selected file: movie.mkv") }))
    }

    @MainActor
    func testBufferingPresentationDoesNotTreatWholeFileDownloadAsPlayableProgress() async throws {
        let release = TorrentRelease(
            id: "release",
            title: "Release",
            quality: .fullHD,
            seeders: 100,
            availability: 1
        )
        let session = TorrentSession(
            id: "session-zero-playable",
            releaseId: release.id,
            sourceId: release.sourceId,
            magnetURI: release.magnetURI,
            storageURL: URL(fileURLWithPath: "/tmp/streamly-test-cache"),
            selectedFileId: "movie.mkv",
            streamingURL: URL(string: "http://127.0.0.1:11470/stream/session-zero-playable/movie.mkv"),
            isSequentialDownloadEnabled: true
        )
        let torrentStatus = TorrentStatus(
            sessionId: session.id,
            state: .streaming,
            progress: TorrentProgress(
                downloadedBytes: 1_200_000_000,
                totalBytes: 12_000_000_000,
                bufferedBytes: 0,
                downloadSpeedBytesPerSecond: 3_400_000,
                uploadSpeedBytesPerSecond: 128_000
            ),
            health: TorrentHealth(seeders: 100, leechers: 8, connectedPeers: 24, availability: 2.0),
            selectedFileId: "movie.mkv",
            isSequentialDownloadEnabled: true,
            streamingURL: session.streamingURL
        )
        let viewModel = PlayerViewModel(
            service: BufferingPlaybackService(release: release),
            mediaSource: PlaybackMediaSource(release: release),
            torrentEngine: StaticTorrentStatusEngine(status: torrentStatus),
            torrentSession: session
        )

        await viewModel.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        let presentation = viewModel.bufferingPresentation
        XCTAssertEqual(try XCTUnwrap(presentation.progress), 0, accuracy: 0.001)
        XCTAssertEqual(presentation.message, "Waiting for playable pieces")
        XCTAssertFalse(presentation.message.contains("10%"))
        XCTAssertTrue(presentation.primaryDetails.contains(where: { $0.contains("Loaded:") && $0.contains("(10%)") }))
        XCTAssertTrue(presentation.primaryDetails.contains(where: { $0.contains("Playable start buffer: 0 B / 1.0 MB") }))
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

    @MainActor
    func testPlayerViewModelAutomaticallyFallsBackWhenStartupPlaybackFails() async throws {
        let selected = TorrentRelease(id: "weak-start", title: "Weak Startup", quality: .ultraHD, seeders: 2)
        let fallback = TorrentRelease(id: "healthy-start", title: "Healthy Startup", quality: .fullHD, seeders: 140)
        let service = StartupFailingPlaybackService()
        let recorder = FallbackRecorder()
        let source = PlaybackMediaSource(
            id: "imdb:movie:tt16431404",
            title: "Apex",
            url: URL(fileURLWithPath: "/tmp/weak-start.mkv"),
            release: selected
        )
        let viewModel = PlayerViewModel(
            service: service,
            mediaSource: source,
            fallbackReleases: [selected, fallback],
            fallbackHandler: { release in
                await recorder.record(release.id)
            }
        )

        await viewModel.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        let playedReleaseIDs = await service.playedReleaseIDs()
        let fallbackReleaseIDs = await recorder.releaseIDs()

        XCTAssertEqual(playedReleaseIDs, [selected.id])
        XCTAssertEqual(fallbackReleaseIDs, [fallback.id])
        XCTAssertEqual(viewModel.fallbackSuggestion?.reason, .failedToStart)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testPlayerViewModelAutomaticStartupFallbackPrefersStreamableHighSeederRelease() async throws {
        let selected = TorrentRelease(
            id: "selected-4k",
            title: "Selected 4K",
            quality: .ultraHD,
            seeders: 2,
            sizeBytes: 15_000_000_000
        )
        let lowSeeder4K = TorrentRelease(
            id: "low-seeder-4k",
            title: "Low Seeder 4K",
            quality: .ultraHD,
            seeders: 3,
            sizeBytes: 14_000_000_000
        )
        let highSeeder1080p = TorrentRelease(
            id: "high-seeder-1080p",
            title: "High Seeder 1080p",
            quality: .fullHD,
            seeders: 1_096,
            sizeBytes: 6_100_000_000
        )
        let service = StartupFailingPlaybackService()
        let recorder = FallbackRecorder()
        let source = PlaybackMediaSource(
            id: "imdb:movie:tt16431404",
            title: "Apex",
            url: URL(fileURLWithPath: "/tmp/selected-4k.mkv"),
            release: selected
        )
        let viewModel = PlayerViewModel(
            service: service,
            mediaSource: source,
            fallbackReleases: [selected, lowSeeder4K, highSeeder1080p],
            fallbackHandler: { release in
                await recorder.record(release.id)
            }
        )

        await viewModel.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        let fallbackReleaseIDs = await recorder.releaseIDs()
        XCTAssertEqual(fallbackReleaseIDs, [highSeeder1080p.id])
        XCTAssertEqual(viewModel.fallbackSuggestion?.nextBestRelease?.release.id, highSeeder1080p.id)
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

private actor SeekFailingPlaybackService: PlaybackServiceProtocol {
    private var legacyState: PlaybackState = .idle
    private var status = PlaybackStatus()

    var currentState: PlaybackState {
        get async { legacyState }
    }

    var currentStatus: PlaybackStatus {
        get async { status }
    }

    func play(_ source: PlaybackMediaSource) async throws {
        status = PlaybackStatus(media: source, state: .playing, currentTime: 0, duration: 120)
        legacyState = source.release.map { .playing($0) } ?? .preparing
    }

    func play(_ release: TorrentRelease) async throws {
        try await play(PlaybackMediaSource(release: release))
    }

    func pause() async throws {
        status = PlaybackStatus(media: status.media, state: .paused, currentTime: status.currentTime, duration: status.duration)
    }

    func resume() async throws {
        status = PlaybackStatus(media: status.media, state: .playing, currentTime: status.currentTime, duration: status.duration)
    }

    func stop() async throws {
        status = PlaybackStatus()
        legacyState = .idle
    }

    func seek(to time: Double) async throws {
        throw PlaybackServiceError.unsupported(operation: "seek")
    }

    func setVolume(_ volume: Double) async throws {}
    func setMuted(_ isMuted: Bool) async throws {}
    func setPlaybackSpeed(_ speed: Double) async throws {}
    func setAudioBoost(_ boost: Double) async throws {}
    func selectAudioTrack(id: String?) async throws {}
    func selectSubtitleTrack(id: String?) async throws {}
    func setSubtitleDelay(_ seconds: Double) async throws {}
    func setSubtitleFontSize(_ fontSize: Double) async throws {}
    func setSubtitleStyle(_ style: SubtitleVisualStyle) async throws {}
    func setFullscreen(_ isFullscreen: Bool) async throws {}
    func setPictureInPicture(_ isActive: Bool) async throws {}

    nonisolated func statusUpdates() -> AsyncThrowingStream<PlaybackStatus, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let status = await self.currentStatus
                continuation.yield(status)
                continuation.finish()
            }
        }
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

private actor SmartSubtitleServiceMock: SubtitleServiceProtocol {
    private var searchCount = 0
    private let localTracks: [SubtitleTrack]
    private let onlineResults: [SubtitleSearchResult]
    private let downloadedTrack: SubtitleTrack?

    init(
        localTracks: [SubtitleTrack] = [],
        onlineResults: [SubtitleSearchResult] = [],
        downloadedTrack: SubtitleTrack? = nil
    ) {
        self.localTracks = localTracks
        self.onlineResults = onlineResults
        self.downloadedTrack = downloadedTrack
    }

    func preferredSubtitles(for item: MediaItem) async throws -> [SubtitleTrack] {
        []
    }

    func localSubtitles(for query: SubtitleSearchQuery, directory: URL?) async throws -> [SubtitleTrack] {
        localTracks
    }

    func searchOnlineSubtitles(query: SubtitleSearchQuery, languages: [String]) async throws -> [SubtitleSearchResult] {
        searchCount += 1
        return onlineResults.filter { languages.isEmpty || languages.contains($0.languageCode) }
    }

    func downloadSubtitle(_ result: SubtitleSearchResult) async throws -> SubtitleTrack {
        downloadedTrack ?? SubtitleTrack(
            id: "cached:\(result.id)",
            languageCode: result.languageCode,
            displayName: result.title,
            source: result.source,
            localURL: URL(fileURLWithPath: "/tmp/\(result.id).srt")
        )
    }

    func searchCountValue() -> Int {
        searchCount
    }
}

private actor ThrowingSubtitleServiceMock: SubtitleServiceProtocol {
    func preferredSubtitles(for item: MediaItem) async throws -> [SubtitleTrack] {
        []
    }

    func searchOnlineSubtitles(query: SubtitleSearchQuery, languages: [String]) async throws -> [SubtitleSearchResult] {
        throw SubtitleServiceError.openSubtitlesCredentialsMissing
    }
}

private actor RecordingTimelinePreviewService: TimelinePreviewServiceProtocol {
    private let preview: TimelinePreview?
    private var recordedRequests: [TimelinePreviewRequest] = []

    init(preview: TimelinePreview?) {
        self.preview = preview
    }

    func preview(for request: TimelinePreviewRequest) async throws -> TimelinePreview? {
        recordedRequests.append(request)
        return preview
    }

    func clearPreviewCache() async throws {}

    func requests() -> [TimelinePreviewRequest] {
        recordedRequests
    }
}

private actor ConfigurableSubtitlePlaybackService: PlaybackServiceProtocol {
    private var status: PlaybackStatus
    private let audioTracks: [AudioTrack]
    private let subtitleTracks: [SubtitleTrack]
    private let duration: Double
    private let bufferingState: PlaybackBufferingState

    init(
        audioTracks: [AudioTrack],
        subtitleTracks: [SubtitleTrack],
        duration: Double = 7_200,
        bufferingState: PlaybackBufferingState = .ready
    ) {
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.duration = duration
        self.bufferingState = bufferingState
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
            duration: duration,
            bufferingState: bufferingState,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            selectedAudioTrackId: audioTracks.first?.id
        )
    }

    func play(_ release: TorrentRelease) async throws {
        try await play(PlaybackMediaSource(release: release))
    }

    func pause() async throws {}
    func resume() async throws {}
    func stop() async throws { status = PlaybackStatus() }
    func seek(to time: Double) async throws {
        status = statusFor(selectedSubtitleTrackId: status.selectedSubtitleTrackId, currentTime: time)
    }
    func setVolume(_ volume: Double) async throws {}
    func setMuted(_ isMuted: Bool) async throws {}
    func setPlaybackSpeed(_ speed: Double) async throws {}
    func selectAudioTrack(id: String?) async throws {
        status = statusFor(selectedAudioTrackId: id)
    }
    func selectSubtitleTrack(id: String?) async throws {
        status = statusFor(selectedSubtitleTrackId: id)
    }
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

    private func statusFor(
        selectedAudioTrackId: String?? = nil,
        selectedSubtitleTrackId: String?? = nil,
        currentTime: Double? = nil
    ) -> PlaybackStatus {
        PlaybackStatus(
            media: status.media,
            state: status.state,
            currentTime: currentTime ?? status.currentTime,
            duration: status.duration,
            bufferingState: status.bufferingState,
            volume: status.volume,
            isMuted: status.isMuted,
            playbackSpeed: status.playbackSpeed,
            audioTracks: status.audioTracks,
            subtitleTracks: status.subtitleTracks,
            selectedAudioTrackId: selectedAudioTrackId ?? status.selectedAudioTrackId,
            selectedSubtitleTrackId: selectedSubtitleTrackId ?? status.selectedSubtitleTrackId,
            isFullscreen: status.isFullscreen,
            isPictureInPictureActive: status.isPictureInPictureActive,
            qualityLabel: status.qualityLabel,
            sourceName: status.sourceName,
            chapters: status.chapters,
            audioBoost: status.audioBoost,
            subtitleDelaySeconds: status.subtitleDelaySeconds,
            subtitleFontSize: status.subtitleFontSize,
            subtitleStyle: status.subtitleStyle
        )
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

private actor StartupFailingPlaybackService: PlaybackServiceProtocol {
    private var playedIDs: [String] = []

    var currentState: PlaybackState {
        get async { .idle }
    }

    var currentStatus: PlaybackStatus {
        get async { PlaybackStatus() }
    }

    func play(_ source: PlaybackMediaSource) async throws {
        if let release = source.release {
            playedIDs.append(release.id)
        }
        throw PlaybackServiceError.unsupported(operation: "ffmpeg HLS startup timeout")
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
            continuation.finish()
        }
    }

    func playedReleaseIDs() -> [String] {
        playedIDs
    }
}

private actor FallbackRecorder {
    private var ids: [String] = []

    func record(_ id: String) {
        ids.append(id)
    }

    func releaseIDs() -> [String] {
        ids
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

private struct StaticTorrentStatusEngine: TorrentEngineProtocol {
    let status: TorrentStatus

    var temporaryStorageURL: URL {
        URL(fileURLWithPath: "/tmp/streamly-test-cache")
    }

    func searchReleases(for item: MediaItem) async throws -> [TorrentRelease] {
        []
    }

    func statusUpdates(sessionId: String) -> AsyncThrowingStream<TorrentStatus, Error> {
        AsyncThrowingStream { continuation in
            guard sessionId == status.sessionId else {
                continuation.finish(throwing: TorrentEngineError.sessionNotFound(sessionId))
                return
            }
            continuation.yield(status)
            continuation.finish()
        }
    }
}
