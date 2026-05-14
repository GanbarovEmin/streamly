import XCTest
@testable import CineFlowCore

final class CoreModelTests: XCTestCase {
    func testMediaItemKeepsCanonicalIdentityAndDisplayFields() {
        let posterURL = URL(string: "https://image.tmdb.org/t/p/w780/poster.jpg")!
        let backdropURL = URL(string: "https://image.tmdb.org/t/p/original/backdrop.jpg")!
        let metadata = MediaMetadata(
            tmdbId: 550,
            imdbId: "tt0137523",
            traktId: 727,
            title: "Fight Club",
            originalTitle: "Fight Club",
            overview: "A placeholder overview",
            year: 1999,
            genres: ["Drama"],
            runtime: 139,
            rating: 8.4,
            posterURL: posterURL,
            backdropURL: backdropURL
        )
        let item = MediaItem(
            id: "tmdb:movie:550",
            title: "Fight Club",
            kind: .movie,
            overview: "A placeholder overview",
            releaseYear: 1999,
            posterPath: "/poster.jpg",
            metadata: metadata
        )

        XCTAssertEqual(item.id, "tmdb:movie:550")
        XCTAssertEqual(item.title, "Fight Club")
        XCTAssertEqual(item.kind, .movie)
        XCTAssertEqual(item.releaseYear, 1999)
        XCTAssertEqual(item.posterPath, "/poster.jpg")
        XCTAssertEqual(item.displayTitle, "Fight Club")
        XCTAssertEqual(item.displayYear, "1999")
        XCTAssertEqual(item.bestPosterURL, posterURL)
        XCTAssertEqual(item.bestBackdropURL, backdropURL)
    }

    func testTorrentReleaseSortsByQualityThenSeeders() {
        let releases = [
            TorrentRelease(id: "a", title: "1080p low seeds", quality: .fullHD, seeders: 12),
            TorrentRelease(id: "b", title: "2160p fewer seeds", quality: .ultraHD, seeders: 3),
            TorrentRelease(id: "c", title: "2160p more seeds", quality: .ultraHD, seeders: 40)
        ]

        let ranked = releases.sortedByCineFlowRank()

        XCTAssertEqual(ranked.map(\.id), ["c", "b", "a"])
    }

    func testTorrentReleaseComputedProperties() {
        let release = TorrentRelease(
            id: "release-1",
            sourceId: "source-a",
            sourceName: "Source A",
            title: "Movie 2160p HEVC",
            magnetURI: "magnet:?xt=urn:btih:fixture",
            torrentFileURL: URL(string: "https://example.com/movie.torrent"),
            quality: .ultraHD,
            codec: .hevc,
            hdr: .hdr10,
            audioLanguages: ["ru", "en"],
            subtitleLanguages: ["ru", "en"],
            seeders: 120,
            leechers: 8,
            sizeBytes: 8_589_934_592,
            uploadDate: Date(timeIntervalSince1970: 1_700_000_000),
            trustedUploader: true
        )

        XCTAssertEqual(release.sourceId, "source-a")
        XCTAssertEqual(release.sourceName, "Source A")
        XCTAssertEqual(release.qualityLabel, "2160p")
        XCTAssertEqual(release.humanReadableSize, "8.59 GB")
        XCTAssertGreaterThan(release.rankScore, 4_000)
        XCTAssertEqual(release.audioLanguages, ["ru", "en"])
        XCTAssertEqual(release.subtitleLanguages, ["ru", "en"])
    }

    func testTorrentMediaFileSelectorUsesEpisodeContextBeforeManualChoice() {
        let release = TorrentRelease(
            id: "got-season-pack",
            title: "Game of Thrones Season 1",
            magnetURI: "magnet:?xt=urn:btih:got",
            quality: .ultraHD,
            seeders: 12
        )
        let context = PlaybackSelectionContext(
            mediaID: "imdb:series:tt0944947",
            displayTitle: "Game of Thrones",
            mediaKind: .series,
            seasonNumber: 1,
            episodeNumber: 1,
            episodeID: "tt0944947:1:1"
        )
        let files = [
            TorrentFile(
                id: "8",
                path: "Game.of.Thrones.S01.2160p/Game.of.Thrones.S01E08.2160p.mkv",
                name: "Game.of.Thrones.S01E08.2160p.mkv",
                lengthBytes: 9_700_000_000,
                isMediaFile: true
            ),
            TorrentFile(
                id: "1",
                path: "Game.of.Thrones.S01.2160p/Game.of.Thrones.S01E01.2160p.mkv",
                name: "Game.of.Thrones.S01E01.2160p.mkv",
                lengthBytes: 9_200_000_000,
                isMediaFile: true
            )
        ]

        let selection = TorrentMediaFileSelector.selection(for: release, files: files, selectionContext: context)

        XCTAssertEqual(selection?.selectedFile.id, "1")
        XCTAssertEqual(selection?.requiresManualConfirmation, false)
        XCTAssertEqual(selection?.manualOptions.map(\.file.id), ["1", "8"])
    }

    func testTorrentMediaFileSelectorFallsBackToTorrentioEpisodeID() {
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
                path: "Game of Thrones/Season 1",
                name: "S01E08. The Pointy End.mkv",
                lengthBytes: 9_700_000_000,
                isMediaFile: true
            ),
            TorrentFile(
                id: "1",
                path: "Game of Thrones/Season 1",
                name: "S01E01. Winter Is Coming.mkv",
                lengthBytes: 9_200_000_000,
                isMediaFile: true
            )
        ]

        let selection = TorrentMediaFileSelector.selection(for: release, files: files)

        XCTAssertEqual(selection?.selectedFile.id, "1")
        XCTAssertEqual(selection?.requiresManualConfirmation, false)
        XCTAssertEqual(selection?.manualOptions.map(\.file.id), ["1", "8"])
    }

    func testMediaItemSupportsMultipleReleases() {
        let item = MediaItem(
            id: "tmdb:movie:603",
            title: "The Matrix",
            kind: .movie,
            overview: "Fixture",
            releaseYear: 1999,
            posterPath: nil,
            torrentReleases: [
                TorrentRelease(id: "release-1080p", title: "The Matrix 1080p", quality: .fullHD, seeders: 200),
                TorrentRelease(id: "release-2160p", title: "The Matrix 2160p", quality: .ultraHD, seeders: 120)
            ]
        )

        XCTAssertEqual(item.torrentReleases.count, 2)
        XCTAssertEqual(item.rankedReleases.map(\.id), ["release-2160p", "release-1080p"])
    }

    func testMediaMetadataComputedFallbacks() {
        let metadata = MediaMetadata(
            tmdbId: 42,
            title: "",
            originalTitle: "Original Title",
            overview: "Fixture",
            year: nil
        )

        XCTAssertEqual(metadata.displayTitle, "Original Title")
        XCTAssertEqual(metadata.displayYear, "Unknown")
        XCTAssertNil(metadata.bestPosterURL)
        XCTAssertNil(metadata.bestBackdropURL)
    }

    func testUserFacingDomainModelsAreCodable() throws {
        let progress = PlaybackProgress(mediaID: "tmdb:movie:603", positionSeconds: 90, durationSeconds: 120)
        let encoded = try JSONEncoder().encode(progress)
        let decoded = try JSONDecoder().decode(PlaybackProgress.self, from: encoded)

        XCTAssertEqual(decoded.mediaID, progress.mediaID)
        XCTAssertEqual(decoded.positionSeconds, 90)
    }

    func testPlaybackProgressCompletionThresholdAndClamping() {
        let active = PlaybackProgress(mediaID: "tmdb:movie:603", positionSeconds: 90, durationSeconds: 100)
        let completed = PlaybackProgress(mediaID: "tmdb:movie:603", positionSeconds: 91, durationSeconds: 100)
        let overrun = PlaybackProgress(mediaID: "tmdb:movie:603", positionSeconds: 140, durationSeconds: 100)
        let negative = PlaybackProgress(mediaID: "tmdb:movie:603", positionSeconds: -12, durationSeconds: 100)

        XCTAssertEqual(active.progressPercent, 90, accuracy: 0.001)
        XCTAssertFalse(active.completed)
        XCTAssertEqual(completed.progressPercent, 91, accuracy: 0.001)
        XCTAssertTrue(completed.completed)
        XCTAssertEqual(overrun.progressPercent, 100, accuracy: 0.001)
        XCTAssertTrue(overrun.completed)
        XCTAssertEqual(negative.positionSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(negative.progressPercent, 0, accuracy: 0.001)
        XCTAssertFalse(negative.completed)
    }

    func testWatchHistoryCompletionCanFollowPlaybackProgressOrExplicitOverride() {
        let progress = PlaybackProgress(mediaID: "tmdb:movie:603", positionSeconds: 95, durationSeconds: 100)
        let historyFromProgress = WatchHistoryItem(progress: progress, id: "history-1")
        let manuallyActive = WatchHistoryItem(
            id: "history-2",
            mediaID: "tmdb:movie:603",
            positionSeconds: 95,
            durationSeconds: 100,
            completed: false
        )

        XCTAssertTrue(historyFromProgress.completed)
        XCTAssertEqual(historyFromProgress.progressPercent, 95, accuracy: 0.001)
        XCTAssertFalse(manuallyActive.completed)
        XCTAssertEqual(manuallyActive.progressPercent, 95, accuracy: 0.001)
    }

    func testAppSettingsExposeDefaultTorrentCacheLocation() {
        let settings = AppSettings()

        XCTAssertTrue(settings.storage.torrentCacheFolderPath.contains("Application Support"))
        XCTAssertTrue(settings.storage.torrentCacheFolderPath.contains("Streamly/TorrentCache"))
        XCTAssertNil(settings.storage.downloadsFolderPath)
        XCTAssertEqual(settings.storage.cacheRetentionDays, 30)
        XCTAssertEqual(settings.storage.maxCacheSizeBytes, 50 * 1_024 * 1_024 * 1_024)
        XCTAssertTrue(settings.storage.keepUnfinishedCache)
        XCTAssertFalse(settings.storage.removeCompletedCache)
        XCTAssertEqual(settings.storage.torrentBandwidthLimits, .unlimited)
    }

    func testHomePreferencesAreLocalFirstAndSyncReady() throws {
        var preferences = HomePreferences()

        XCTAssertEqual(preferences.layoutDensity, .comfortable)
        XCTAssertEqual(preferences.posterSize, .medium)
        XCTAssertEqual(preferences.sections.first?.sectionID, HomePreferences.defaultSectionIDs.first)
        XCTAssertTrue(preferences.isSectionEnabled("continueWatching"))
        XCTAssertEqual(preferences.schemaVersion, 1)
        XCTAssertEqual(preferences.syncRevision, 0)

        preferences.setSection("trendingMovies", isEnabled: false, updatedAt: Date(timeIntervalSince1970: 100))
        preferences.moveSection("recommended", to: 0, updatedAt: Date(timeIntervalSince1970: 120))
        preferences.layoutDensity = .compact
        preferences.posterSize = .large

        XCTAssertFalse(preferences.isSectionEnabled("trendingMovies"))
        XCTAssertEqual(preferences.orderedSections.first?.sectionID, "recommended")

        let decoded = try JSONDecoder().decode(HomePreferences.self, from: try JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded.layoutDensity, .compact)
        XCTAssertEqual(decoded.posterSize, .large)
        XCTAssertFalse(decoded.isSectionEnabled("trendingMovies"))
        XCTAssertEqual(decoded.orderedSections.first?.sectionID, "recommended")
        XCTAssertEqual(decoded.syncRevision, 2)
        XCTAssertEqual(decoded.updatedAt, Date(timeIntervalSince1970: 120))
    }

    func testAppSettingsDecodeOlderPayloadWithDefaultHomePreferences() throws {
        let data = Data(#"{"general":{"language":"system","launchAtLogin":true,"openLastScreenOnLaunch":false}}"#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(settings.general.launchAtLogin)
        XCTAssertEqual(settings.home, HomePreferences())
        XCTAssertTrue(settings.home.isSectionEnabled("continueWatching"))
        XCTAssertTrue(settings.home.isSectionEnabled("trendingMovies"))
        XCTAssertTrue(settings.notifications.betterReleaseNotificationsEnabled)
        XCTAssertTrue(settings.notifications.betterReleaseDigestMode)
        XCTAssertFalse(settings.notifications.macOSBetterReleaseNotificationsEnabled)
    }

    func testPlaybackSettingsExposeAutoplayNextEpisodePreference() throws {
        let settings = PlaybackSettings(autoplayNextEpisode: false)

        XCTAssertFalse(settings.autoplayNextEpisode)

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(PlaybackSettings.self, from: encoded)

        XCTAssertFalse(decoded.autoplayNextEpisode)
        XCTAssertTrue(PlaybackSettings().autoplayNextEpisode)
    }

    func testAutoPlaybackQualityPrefersHealthySeededReleases() {
        let settings = PlaybackSettings(
            preferredQuality: .auto,
            preferHighSeedersOverHighestQuality: false
        )

        let preferences = settings.rankingPreferences()

        XCTAssertTrue(preferences.preferHighSeedersOverHighestQuality)
    }

    func testStorageSettingsDecodeOlderPayloadWithSmartCacheDefaults() throws {
        let data = Data(#"{"torrentCacheFolderPath":"/tmp/torrents","downloadsFolderPath":null}"#.utf8)

        let settings = try JSONDecoder().decode(StorageSettings.self, from: data)

        XCTAssertEqual(settings.torrentCacheFolderPath, "/tmp/torrents")
        XCTAssertEqual(settings.cacheRetentionDays, 30)
        XCTAssertEqual(settings.maxCacheSizeBytes, 50 * 1_024 * 1_024 * 1_024)
        XCTAssertTrue(settings.smartCachePolicy.keepUnfinished)
        XCTAssertEqual(settings.torrentBandwidthLimits, .unlimited)
    }
}
