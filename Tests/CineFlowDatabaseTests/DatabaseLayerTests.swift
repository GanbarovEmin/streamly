import CineFlowCore
import Foundation
import GRDB
import XCTest
@testable import CineFlowDatabase

final class DatabaseLayerTests: XCTestCase {
    func testInitialMigrationCreatesExpectedTablesAndKeepsCredentialsOutOfSQLite() throws {
        let databaseManager = try DatabaseManager.inMemory()

        let tables = try databaseManager.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }

        XCTAssertTrue(tables.contains("media_items"))
        XCTAssertTrue(tables.contains("source_accounts"))
        XCTAssertTrue(tables.contains("app_settings"))
        XCTAssertTrue(tables.contains("diagnostics_events"))
        XCTAssertTrue(tables.contains("cached_images"))
        XCTAssertTrue(tables.contains("user_media_sources"))

        let sourceAccountColumns = try databaseManager.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(source_accounts)").map { row in
                String(describing: row["name"] as String)
            }
        }

        XCTAssertTrue(sourceAccountColumns.contains("credential_keychain_id"))
        XCTAssertTrue(sourceAccountColumns.contains("authentication_status"))
        XCTAssertTrue(sourceAccountColumns.contains("last_validation_at"))
        XCTAssertFalse(sourceAccountColumns.contains { column in
            let normalized = column.lowercased()
            return normalized.contains("password") || normalized.contains("cookie") || normalized.contains("token")
        })

        let cachedImageColumns = try databaseManager.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(cached_images)").map { row in
                String(describing: row["name"] as String)
            }
        }

        XCTAssertTrue(cachedImageColumns.contains("file_size"))
        XCTAssertTrue(cachedImageColumns.contains("created_at"))
        XCTAssertTrue(cachedImageColumns.contains("last_accessed_at"))
    }

    func testMediaLibraryAndPersistenceAcrossReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let databaseURL = directory.appendingPathComponent("CineFlow.sqlite")
        var databaseManager: DatabaseManager? = try DatabaseManager(path: databaseURL.path)
        let item = makeMovie(id: "tmdb:movie:603", title: "The Matrix")

        try await DatabaseLibraryRepository(databaseManager: databaseManager!).add(item)
        databaseManager = nil

        let reopenedManager = try DatabaseManager(path: databaseURL.path)
        let reopenedItems = try await DatabaseLibraryRepository(databaseManager: reopenedManager).items()

        XCTAssertEqual(reopenedItems.map(\.id), [item.id])
        XCTAssertEqual(reopenedItems.first?.title, "The Matrix")
    }

    func testLibraryActionsPersistAcrossReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let databaseURL = directory.appendingPathComponent("CineFlow.sqlite")
        var databaseManager: DatabaseManager? = try DatabaseManager(path: databaseURL.path)
        let item = makeMovie(id: "tmdb:movie:603", title: "The Matrix")
        let repository = DatabaseLibraryRepository(databaseManager: databaseManager!)

        try await repository.add(item)
        try await repository.addFavorite(item)
        try await repository.markWatched(item, positionSeconds: 3_400)
        try await repository.setRating(item, rating: 9)
        let list = try await repository.createList(name: "Sci-Fi")
        try await repository.add(item, to: list.id)
        databaseManager = nil

        let reopenedRepository = try DatabaseLibraryRepository(databaseManager: DatabaseManager(path: databaseURL.path))
        let reopenedItems = try await reopenedRepository.items().map(\.id)
        let reopenedFavorites = try await reopenedRepository.favorites().map(\.id)
        let reopenedWatched = try await reopenedRepository.watchedItems().map(\.item.id)
        let reopenedRatings = try await reopenedRepository.ratedItems().map(\.rating)
        let reopenedLists = try await reopenedRepository.lists()
        let reopenedListItems = try await reopenedRepository.items(in: list.id).map(\.id)

        XCTAssertEqual(reopenedItems, [item.id])
        XCTAssertEqual(reopenedFavorites, [item.id])
        XCTAssertEqual(reopenedWatched, [item.id])
        XCTAssertEqual(reopenedRatings, [9])
        XCTAssertEqual(reopenedLists.first?.itemIDs, [item.id])
        XCTAssertEqual(reopenedListItems, [item.id])
    }

    func testUserListsCrudDefaultListAndItemRemovalPersistAcrossReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let databaseURL = directory.appendingPathComponent("CineFlow.sqlite")
        var databaseManager: DatabaseManager? = try DatabaseManager(path: databaseURL.path)
        let repository = DatabaseLibraryRepository(databaseManager: databaseManager!)
        let movie = makeMovie(id: "tmdb:movie:603", title: "The Matrix")

        let defaultList = try await repository.defaultList()
        XCTAssertEqual(defaultList.name, "Хочу посмотреть")
        XCTAssertEqual(defaultList.description, "Фильмы и сериалы, которые вы хотите посмотреть позже.")
        XCTAssertEqual(defaultList.itemIDs, [])

        let customList = try await repository.createList(name: "Семейное", description: "Для вечернего просмотра")
        try await repository.add(movie, to: customList.id)
        try await repository.renameList(id: customList.id, name: "Семейное кино", description: "Обновленное описание")
        try await repository.remove(movie.id, from: customList.id)
        try await repository.add(movie, to: defaultList.id)
        databaseManager = nil

        let reopenedRepository = try DatabaseLibraryRepository(databaseManager: DatabaseManager(path: databaseURL.path))
        let reopenedLists = try await reopenedRepository.lists()
        let renamedList = try XCTUnwrap(reopenedLists.first { $0.id == customList.id })
        let reopenedDefault = try XCTUnwrap(reopenedLists.first { $0.id == defaultList.id })
        let customItems = try await reopenedRepository.items(in: customList.id)
        let defaultItems = try await reopenedRepository.items(in: defaultList.id)

        XCTAssertEqual(renamedList.name, "Семейное кино")
        XCTAssertEqual(renamedList.description, "Обновленное описание")
        XCTAssertEqual(renamedList.itemsCount, 0)
        XCTAssertGreaterThanOrEqual(renamedList.updatedAt, renamedList.createdAt)
        XCTAssertTrue(customItems.isEmpty)
        XCTAssertEqual(reopenedDefault.itemsCount, 1)
        XCTAssertEqual(defaultItems.map(\.id), [movie.id])

        try await reopenedRepository.deleteList(id: customList.id)
        let afterDelete = try await reopenedRepository.lists()
        XCTAssertFalse(afterDelete.contains { $0.id == customList.id })
    }

    func testWatchlistItemPreferencesPersistAcrossReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let databaseURL = directory.appendingPathComponent("CineFlow.sqlite")
        var databaseManager: DatabaseManager? = try DatabaseManager(path: databaseURL.path)
        let repository = DatabaseLibraryRepository(databaseManager: databaseManager!)
        let movie = MediaItem(
            id: "tmdb:movie:603",
            title: "The Matrix",
            kind: .movie,
            overview: "Fixture",
            releaseYear: 1999,
            posterPath: nil,
            torrentReleases: [
                TorrentRelease(id: "matrix-1080p", title: "The Matrix 1080p", quality: .fullHD, seeders: 50)
            ]
        )

        let watchlist = try await repository.defaultList()
        try await repository.add(movie, to: watchlist.id)
        let reminderDate = Date().addingTimeInterval(5 * 24 * 60 * 60)
        try await repository.updateWatchlistItem(
            listID: watchlist.id,
            mediaID: movie.id,
            priority: .high,
            remindLaterAt: reminderDate
        )
        databaseManager = nil

        let reopenedRepository = try DatabaseLibraryRepository(databaseManager: DatabaseManager(path: databaseURL.path))
        let items = try await reopenedRepository.watchlistItems(in: watchlist.id)

        XCTAssertEqual(items.map(\.mediaID), [movie.id])
        XCTAssertEqual(items.first?.priority, .high)
        XCTAssertEqual(items.first?.initialQuality, .fullHD)
        XCTAssertEqual(items.first?.remindLaterAt?.timeIntervalSince1970 ?? 0, reminderDate.timeIntervalSince1970, accuracy: 1.5)
    }

    func testPlaybackHistoryListsRatingsCacheAndSettingsCRUD() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let item = makeMovie(id: "tmdb:movie:329865", title: "Arrival")

        try await MediaRepository(databaseManager: databaseManager).upsert(item)

        let progressRepository = PlaybackProgressRepository(databaseManager: databaseManager)
        try await progressRepository.setProgress(mediaID: item.id, positionSeconds: 120, durationSeconds: 7200)
        let progress = try await progressRepository.progress(mediaID: item.id)
        XCTAssertEqual(progress?.positionSeconds, 120)

        let historyRepository = WatchHistoryRepository(databaseManager: databaseManager)
        try await historyRepository.record(mediaID: item.id, positionSeconds: 360)
        let historyEntries = try await historyRepository.entries()
        XCTAssertEqual(historyEntries.first?.mediaID, item.id)

        let listsRepository = UserListsRepository(databaseManager: databaseManager)
        let list = try await listsRepository.createList(name: "Sci-Fi")
        try await listsRepository.addItem(mediaID: item.id, to: list.id)
        let listItems = try await listsRepository.items(in: list.id)
        XCTAssertEqual(listItems.map(\.id), [item.id])

        let ratingsRepository = RatingsRepository(databaseManager: databaseManager)
        try await ratingsRepository.setRating(mediaID: item.id, rating: 9)
        let rating = try await ratingsRepository.rating(mediaID: item.id)
        XCTAssertEqual(rating, 9)

        let cacheRepository = CacheRepository(databaseManager: databaseManager)
        try await cacheRepository.setMetadata(cacheKey: "tmdb:movie:329865", provider: "tmdb", payloadJSON: #"{"title":"Arrival"}"#)
        try await cacheRepository.setCachedImage(url: "https://image.tmdb.org/arrival.jpg", localPath: "/tmp/arrival.jpg")
        let metadata = try await cacheRepository.metadata(cacheKey: "tmdb:movie:329865")
        let cachedImage = try await cacheRepository.cachedImage(url: "https://image.tmdb.org/arrival.jpg")
        XCTAssertEqual(metadata, #"{"title":"Arrival"}"#)
        XCTAssertEqual(cachedImage, "/tmp/arrival.jpg")

        let settingsRepository = DatabaseSettingsRepository(databaseManager: databaseManager)
        await settingsRepository.setSubtitleLanguagePriority(["en", "ru"])
        let languages = await settingsRepository.subtitleLanguagePriority
        XCTAssertEqual(languages, ["en", "ru"])
    }

    func testUserMediaSourcesPersistAndFilterByMediaID() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = DatabaseUserMediaSourceRepository(databaseManager: databaseManager)
        let movieFile = URL(fileURLWithPath: "/tmp/matrix.mkv")
        let seriesFile = URL(fileURLWithPath: "/tmp/series.mkv")

        try await repository.save(
            UserMediaSource(
                id: "source-movie",
                mediaID: "tmdb:movie:603",
                displayName: "The Matrix",
                kind: .localFile,
                url: movieFile
            )
        )
        try await repository.save(
            UserMediaSource(
                id: "source-series",
                mediaID: "tmdb:tv:1399",
                displayName: "Game of Thrones",
                kind: .localFile,
                url: seriesFile
            )
        )

        let movieSources = try await repository.sources(for: "tmdb:movie:603")
        let storedSource = try await repository.source(id: "source-movie")

        XCTAssertEqual(movieSources.map(\.id), ["source-movie"])
        XCTAssertEqual(storedSource?.displayName, "The Matrix")
        XCTAssertEqual(storedSource?.url, movieFile)
        XCTAssertEqual(storedSource?.playbackMediaSource?.sourceName, "Local file")

        try await repository.delete(id: "source-movie")
        let deletedSource = try await repository.source(id: "source-movie")
        XCTAssertNil(deletedSource)
    }

    func testApplicationSupportMigrationMovesLegacyCineFlowDirectoryToStreamly() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyDirectory = baseURL.appendingPathComponent("CineFlow", isDirectory: true)
        let legacyDatabase = legacyDirectory.appendingPathComponent("CineFlow.sqlite")
        let streamlyDirectory = baseURL.appendingPathComponent("Streamly", isDirectory: true)
        let streamlyDatabase = streamlyDirectory.appendingPathComponent(DatabaseManager.fileName)

        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try Data("legacy db".utf8).write(to: legacyDatabase)
        defer {
            try? FileManager.default.removeItem(at: baseURL)
        }

        try DatabaseManager.migrateLegacyApplicationSupportIfNeeded(baseURL: baseURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: streamlyDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: streamlyDatabase.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: streamlyDirectory.appendingPathComponent("CineFlow.sqlite").path))
    }

    func testFullAppSettingsPersistAcrossReopen() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let settingsRepository = DatabaseSettingsRepository(databaseManager: databaseManager)

        var settings = AppSettings()
        settings.general.language = .russian
        settings.general.openLastScreenOnLaunch = true
        settings.appearance.reduceMotion = true
        settings.playback.preferredAudioLanguages = ["en", "ru"]
        settings.playback.preferredQuality = .p1080
        settings.playback.hdrPreference = .avoidHDR
        settings.playback.codecPreference = .avoidUnsupportedAV1
        settings.playback.maxFileSizeBytes = 12_000_000_000
        settings.playback.preferHighSeedersOverHighestQuality = true
        settings.playback.hardwareAccelerationEnabled = false
        settings.playback.startFromLastPosition = false
        settings.playback.defaultFullscreen = true
        settings.playback.seekStepSeconds = 30
        settings.updates.automaticChecksEnabled = false

        await settingsRepository.setAppSettings(settings)

        let reopenedRepository = DatabaseSettingsRepository(databaseManager: databaseManager)
        let reopened = await reopenedRepository.appSettings

        XCTAssertEqual(reopened.general.language, .russian)
        XCTAssertEqual(reopened.general.openLastScreenOnLaunch, true)
        XCTAssertEqual(reopened.appearance.darkModeOnly, true)
        XCTAssertEqual(reopened.appearance.accentColorName, "neonPurple")
        XCTAssertEqual(reopened.appearance.reduceMotion, true)
        XCTAssertEqual(reopened.playback.preferredAudioLanguages, ["en", "ru"])
        XCTAssertEqual(reopened.playback.preferredQuality, .p1080)
        XCTAssertEqual(reopened.playback.hdrPreference, .avoidHDR)
        XCTAssertEqual(reopened.playback.codecPreference, .avoidUnsupportedAV1)
        XCTAssertEqual(reopened.playback.maxFileSizeBytes, 12_000_000_000)
        XCTAssertEqual(reopened.playback.preferHighSeedersOverHighestQuality, true)
        XCTAssertEqual(reopened.playback.hardwareAccelerationEnabled, false)
        XCTAssertEqual(reopened.playback.startFromLastPosition, false)
        XCTAssertEqual(reopened.playback.defaultFullscreen, true)
        XCTAssertEqual(reopened.playback.seekStepSeconds, 30)
        XCTAssertEqual(reopened.updates.automaticChecksEnabled, false)
        XCTAssertEqual(reopened.privacy.telemetryEnabled, false)
    }

    func testPlaybackProgressStoresResumeMetadataAndCompletionState() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let item = makeMovie(id: "tmdb:movie:603", title: "The Matrix")
        try await MediaRepository(databaseManager: databaseManager).upsert(item)

        let progressRepository = PlaybackProgressRepository(databaseManager: databaseManager)
        try await progressRepository.saveProgress(
            PlaybackProgress(
                mediaID: item.id,
                episodeID: nil,
                releaseID: "matrix-2160p",
                positionSeconds: 91,
                durationSeconds: 100,
                lastWatchedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        let storedProgress = try await progressRepository.progress(mediaID: item.id)
        let progress = try XCTUnwrap(storedProgress)

        XCTAssertEqual(progress.mediaID, item.id)
        XCTAssertEqual(progress.releaseID, "matrix-2160p")
        XCTAssertEqual(progress.positionSeconds, 91)
        XCTAssertEqual(progress.durationSeconds, 100)
        XCTAssertEqual(progress.progressPercent, 91, accuracy: 0.001)
        XCTAssertTrue(progress.completed)
        let activeContinueWatching = try await progressRepository.continueWatching(includeCompleted: false)
        let allContinueWatching = try await progressRepository.continueWatching(includeCompleted: true)
        XCTAssertTrue(activeContinueWatching.isEmpty)
        XCTAssertEqual(allContinueWatching.map(\.mediaID), [item.id])
    }

    func testPlaybackProgressCreatesPlaceholderForSourceOnlyMedia() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let progressRepository = PlaybackProgressRepository(databaseManager: databaseManager)
        let historyRepository = WatchHistoryRepository(databaseManager: databaseManager)

        try await progressRepository.saveProgress(
            PlaybackProgress(
                mediaID: "imdb:movie:tt16431404",
                releaseID: "torrentio:apex",
                positionSeconds: 12,
                durationSeconds: 6000
            )
        )
        try await historyRepository.record(
            PlaybackProgress(
                mediaID: "imdb:movie:tt16431404",
                releaseID: "torrentio:apex",
                positionSeconds: 12,
                durationSeconds: 6000
            )
        )

        let storedProgress = try await progressRepository.progress(mediaID: "imdb:movie:tt16431404")
        let historyEntries = try await historyRepository.entries()

        XCTAssertEqual(storedProgress?.mediaID, "imdb:movie:tt16431404")
        XCTAssertEqual(historyEntries.first?.mediaID, "imdb:movie:tt16431404")
    }

    func testPlaybackProgressKeepsSeparateSeriesEpisodes() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let series = MediaItem(
            id: "tmdb:tv:1399",
            title: "Game of Thrones",
            kind: .series,
            overview: "Fixture",
            releaseYear: 2011,
            posterPath: nil
        )
        try await MediaRepository(databaseManager: databaseManager).upsert(series)

        let progressRepository = PlaybackProgressRepository(databaseManager: databaseManager)
        try await progressRepository.saveProgress(
            PlaybackProgress(mediaID: series.id, episodeID: "s1e1", positionSeconds: 20, durationSeconds: 100)
        )
        try await progressRepository.saveProgress(
            PlaybackProgress(mediaID: series.id, episodeID: "s1e2", positionSeconds: 30, durationSeconds: 100)
        )

        let firstEpisode = try await progressRepository.progress(mediaID: series.id, episodeID: "s1e1")
        let secondEpisode = try await progressRepository.progress(mediaID: series.id, episodeID: "s1e2")

        XCTAssertEqual(firstEpisode?.positionSeconds, 20)
        XCTAssertEqual(secondEpisode?.positionSeconds, 30)
    }

    func testWatchHistoryRecordsProgressMetadataGroupsAndClears() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let matrix = makeMovie(id: "tmdb:movie:603", title: "The Matrix")
        let arrival = makeMovie(id: "tmdb:movie:329865", title: "Arrival")
        try await MediaRepository(databaseManager: databaseManager).upsert(matrix)
        try await MediaRepository(databaseManager: databaseManager).upsert(arrival)

        let historyRepository = WatchHistoryRepository(databaseManager: databaseManager)
        try await historyRepository.record(
            PlaybackProgress(
                mediaID: matrix.id,
                episodeID: nil,
                releaseID: "matrix-2160p",
                positionSeconds: 40,
                durationSeconds: 100,
                lastWatchedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        try await historyRepository.record(
            PlaybackProgress(
                mediaID: arrival.id,
                episodeID: nil,
                releaseID: nil,
                positionSeconds: 95,
                durationSeconds: 100,
                lastWatchedAt: Date(timeIntervalSince1970: 1_800_086_400)
            )
        )

        let entries = try await historyRepository.entries(limit: 10)

        XCTAssertEqual(entries.map(\.mediaID), [arrival.id, matrix.id])
        XCTAssertEqual(entries.first?.progressPercent, 95)
        XCTAssertTrue(entries.first?.completed == true)

        try await historyRepository.clear()

        let clearedEntries = try await historyRepository.entries(limit: 10)
        XCTAssertTrue(clearedEntries.isEmpty)
    }

    func testLibraryExportIncludesPortableDataAndExcludesPrivateState() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = DatabaseLibraryRepository(databaseManager: databaseManager)
        let progressRepository = PlaybackProgressRepository(databaseManager: databaseManager)
        let sourceRepository = DatabaseUserMediaSourceRepository(databaseManager: databaseManager)
        let service = DatabaseLibraryPortabilityService(databaseManager: databaseManager)
        let movie = makeMovie(id: "tmdb:movie:603", title: "The Matrix")

        try await repository.add(movie)
        try await repository.addFavorite(movie)
        try await repository.setRating(movie, rating: 9)
        try await repository.markWatched(movie, positionSeconds: 3_400)
        let list = try await repository.createList(name: "Sci-Fi", description: "Owned by the user")
        try await repository.add(movie, to: list.id)
        try await progressRepository.saveProgress(
            PlaybackProgress(
                mediaID: movie.id,
                releaseID: "matrix-2160p",
                positionSeconds: 120,
                durationSeconds: 7_200
            )
        )
        try await sourceRepository.save(
            UserMediaSource(
                id: "private-local-file",
                mediaID: movie.id,
                displayName: "Private file",
                kind: .localFile,
                url: URL(fileURLWithPath: "/Users/local/movie.mkv")
            )
        )

        let data = try await service.exportLibraryJSON()
        let text = String(decoding: data, as: UTF8.self)
        let snapshot = try JSONDecoder.libraryPortability.decode(LibraryExportSnapshot.self, from: data)

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.mediaItems.map(\.id), [movie.id])
        XCTAssertEqual(snapshot.libraryItems.map(\.mediaID), [movie.id])
        XCTAssertEqual(snapshot.favoriteMediaIDs, [movie.id])
        XCTAssertEqual(snapshot.lists.map(\.name), ["Sci-Fi"])
        XCTAssertEqual(snapshot.watchHistory.map(\.mediaID), [movie.id])
        XCTAssertEqual(snapshot.ratings.map(\.rating), [9])
        XCTAssertEqual(snapshot.playbackProgress.map(\.releaseID), ["matrix-2160p"])
        XCTAssertFalse(text.contains("source_accounts"))
        XCTAssertFalse(text.contains("user_media_sources"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("cookie"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("credential"))
    }

    func testLibraryImportPreviewValidatesReferencesAndRatings() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let service = DatabaseLibraryPortabilityService(databaseManager: databaseManager)
        let invalid = LibraryExportSnapshot(
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
            mediaItems: [],
            libraryItems: [LibraryItem(mediaID: "missing:movie:1")],
            favoriteMediaIDs: [],
            lists: [],
            watchHistory: [],
            ratings: [UserRating(mediaID: "missing:movie:1", rating: 11)],
            playbackProgress: []
        )
        let data = try JSONEncoder.libraryPortability.encode(invalid)

        let preview = try await service.previewImport(data)

        XCTAssertFalse(preview.canImport)
        XCTAssertTrue(preview.validationIssues.contains { $0.contains("Missing media item: missing:movie:1") })
        XCTAssertTrue(preview.validationIssues.contains { $0.contains("Rating must be between 1 and 10") })
    }

    func testLibraryImportMergesWithoutDuplicateListsHistoryRatingsOrProgress() async throws {
        let sourceManager = try DatabaseManager.inMemory()
        let sourceRepository = DatabaseLibraryRepository(databaseManager: sourceManager)
        let sourceProgress = PlaybackProgressRepository(databaseManager: sourceManager)
        let sourceService = DatabaseLibraryPortabilityService(databaseManager: sourceManager)
        let matrix = makeMovie(id: "tmdb:movie:603", title: "The Matrix")

        try await sourceRepository.add(matrix)
        try await sourceRepository.addFavorite(matrix)
        try await sourceRepository.setRating(matrix, rating: 9)
        try await sourceRepository.markWatched(matrix, positionSeconds: 3_400)
        let sourceList = try await sourceRepository.createList(name: "Sci-Fi", description: "Imported list")
        try await sourceRepository.add(matrix, to: sourceList.id)
        try await sourceProgress.saveProgress(
            PlaybackProgress(
                mediaID: matrix.id,
                releaseID: "matrix-2160p",
                positionSeconds: 500,
                durationSeconds: 7_200,
                lastWatchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        let exportData = try await sourceService.exportLibraryJSON()

        let targetManager = try DatabaseManager.inMemory()
        let targetRepository = DatabaseLibraryRepository(databaseManager: targetManager)
        let targetService = DatabaseLibraryPortabilityService(databaseManager: targetManager)
        let existingList = try await targetRepository.createList(name: "Sci-Fi", description: "Existing list")
        try await targetRepository.add(matrix, to: existingList.id)
        try await targetRepository.setRating(matrix, rating: 8)

        let preview = try await targetService.previewImport(exportData)
        let result = try await targetService.importLibraryJSON(exportData, options: LibraryImportOptions(createBackupBeforeImport: true))
        _ = try await targetService.importLibraryJSON(exportData, options: LibraryImportOptions(createBackupBeforeImport: false))

        let lists = try await targetRepository.lists()
        let matchingLists = lists.filter { $0.name == "Sci-Fi" }
        let listItems = try await targetRepository.items(in: existingList.id)
        let historyEntries = try await WatchHistoryRepository(databaseManager: targetManager).entries(limit: 20)
        let ratingValue = try await RatingsRepository(databaseManager: targetManager).rating(mediaID: matrix.id)
        let progressValue = try await PlaybackProgressRepository(databaseManager: targetManager).progress(mediaID: matrix.id, episodeID: nil)
        let importedRating = try XCTUnwrap(ratingValue)
        let importedProgress = try XCTUnwrap(progressValue)

        XCTAssertTrue(preview.canImport)
        XCTAssertEqual(result.backupData == nil, false)
        XCTAssertEqual(matchingLists.count, 1)
        XCTAssertEqual(listItems.map(\.id), [matrix.id])
        XCTAssertEqual(historyEntries.count, 1)
        XCTAssertEqual(importedRating, 9)
        XCTAssertEqual(importedProgress.releaseID, "matrix-2160p")
        XCTAssertEqual(importedProgress.positionSeconds, 500)
    }

    func testPersonalStatsAreComputedLocallyFromWatchHistoryProgressAndMetadata() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let mediaRepository = MediaRepository(databaseManager: databaseManager)
        let historyRepository = WatchHistoryRepository(databaseManager: databaseManager)
        let progressRepository = PlaybackProgressRepository(databaseManager: databaseManager)
        let service = DatabasePersonalStatsService(databaseManager: databaseManager)
        let firstNight = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-05T19:00:00Z"))
        let firstEpisode = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-05T20:00:00Z"))
        let secondEpisode = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-05T21:00:00Z"))
        let partialMovie = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-20T22:00:00Z"))
        let matrix = makeMovie(
            id: "tmdb:movie:603",
            title: "The Matrix",
            genres: ["Sci-Fi", "Action"],
            cast: [CastMember(id: "keanu", name: "Keanu Reeves", characterName: "Neo")]
        )
        let arrival = makeMovie(
            id: "tmdb:movie:329865",
            title: "Arrival",
            genres: ["Sci-Fi", "Drama"],
            cast: [CastMember(id: "amy", name: "Amy Adams")]
        )
        let series = MediaItem(
            id: "tmdb:tv:1399",
            title: "Game of Thrones",
            kind: .series,
            overview: "Fixture",
            releaseYear: 2011,
            posterPath: nil,
            metadata: MediaMetadata(
                tmdbId: 1399,
                title: "Game of Thrones",
                originalTitle: "Game of Thrones",
                overview: "Fixture",
                year: 2011,
                genres: ["Drama", "Fantasy"],
                cast: [CastMember(id: "pedro", name: "Pedro Pascal")]
            )
        )

        try await mediaRepository.upsert(matrix)
        try await mediaRepository.upsert(arrival)
        try await mediaRepository.upsert(series)
        try await historyRepository.record(
            PlaybackProgress(
                mediaID: matrix.id,
                positionSeconds: 7_200,
                durationSeconds: 7_200,
                progressPercent: 100,
                lastWatchedAt: firstNight,
                completed: true
            )
        )
        try await historyRepository.record(
            PlaybackProgress(
                mediaID: series.id,
                episodeID: "s1e1",
                positionSeconds: 3_600,
                durationSeconds: 3_600,
                progressPercent: 100,
                lastWatchedAt: firstEpisode,
                completed: true
            )
        )
        try await historyRepository.record(
            PlaybackProgress(
                mediaID: series.id,
                episodeID: "s1e2",
                positionSeconds: 3_600,
                durationSeconds: 3_600,
                progressPercent: 100,
                lastWatchedAt: secondEpisode,
                completed: true
            )
        )
        try await historyRepository.record(
            PlaybackProgress(
                mediaID: arrival.id,
                positionSeconds: 3_000,
                durationSeconds: 6_000,
                progressPercent: 50,
                lastWatchedAt: partialMovie,
                completed: false
            )
        )
        try await progressRepository.saveProgress(
            PlaybackProgress(
                mediaID: arrival.id,
                positionSeconds: 3_000,
                durationSeconds: 6_000,
                progressPercent: 50,
                lastWatchedAt: partialMovie,
                completed: false
            )
        )

        let stats = try await service.personalStats(referenceDate: partialMovie)
        let reopenedMatrix = try await mediaRepository.item(id: matrix.id)

        XCTAssertEqual(reopenedMatrix?.metadata?.genres, ["Sci-Fi", "Action"])
        XCTAssertEqual(stats.watchedMoviesCount, 1)
        XCTAssertEqual(stats.watchedEpisodesCount, 2)
        XCTAssertEqual(stats.monthlyWatchTimeSeconds, 17_400, accuracy: 0.001)
        XCTAssertEqual(stats.completionRate, 0.75, accuracy: 0.001)
        XCTAssertEqual(stats.longestBingeSession?.itemCount, 3)
        XCTAssertEqual(stats.longestBingeSession?.durationSeconds ?? 0, 14_400, accuracy: 0.001)
        XCTAssertEqual(stats.favoriteGenres.prefix(2).map(\.name), ["Drama", "Fantasy"])
        XCTAssertEqual(stats.favoriteActors.first?.name, "Pedro Pascal")
        XCTAssertEqual(stats.yearRecapStatus, .collectingSignals)
        XCTAssertFalse(stats.sharesPrivateAnalytics)
    }

    func testImageCacheMetadataTracksSizeAccessAndClearOperations() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let cacheRepository = CacheRepository(databaseManager: databaseManager)
        let oldAccess = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_000))
        let recentAccess = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_800_000_000))

        try await cacheRepository.upsertCachedImage(
            url: "https://image.tmdb.org/old.jpg",
            localPath: "/tmp/old.jpg",
            fileSize: 40,
            createdAt: oldAccess,
            lastAccessedAt: oldAccess
        )
        try await cacheRepository.upsertCachedImage(
            url: "https://image.tmdb.org/recent.jpg",
            localPath: "/tmp/recent.jpg",
            fileSize: 60,
            createdAt: recentAccess,
            lastAccessedAt: recentAccess
        )

        let initialCacheSize = try await cacheRepository.imageCacheSizeBytes()
        XCTAssertEqual(initialCacheSize, 100)

        let oldRecord = try await cacheRepository.cachedImageRecord(url: "https://image.tmdb.org/old.jpg", touch: true)
        XCTAssertEqual(oldRecord?.localPath, "/tmp/old.jpg")
        XCTAssertGreaterThan(oldRecord?.lastAccessedAt ?? oldAccess, oldAccess)

        let unused = try await cacheRepository.cachedImageRecordsUnused(before: recentAccess)
        XCTAssertEqual(unused.map(\.url), ["https://image.tmdb.org/old.jpg"])

        try await cacheRepository.removeCachedImage(url: "https://image.tmdb.org/old.jpg")
        let reducedCacheSize = try await cacheRepository.imageCacheSizeBytes()
        XCTAssertEqual(reducedCacheSize, 60)

        try await cacheRepository.clearImageCache()
        let clearedCacheSize = try await cacheRepository.imageCacheSizeBytes()
        XCTAssertEqual(clearedCacheSize, 0)
    }

    func testMetadataCacheReportsSizeAndCanClearRecords() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let cacheRepository = CacheRepository(databaseManager: databaseManager)

        try await cacheRepository.setMetadata(cacheKey: "tmdb:movie:1", provider: "tmdb", payloadJSON: #"{"title":"One"}"#)
        try await cacheRepository.setMetadata(cacheKey: "cinemeta:movie:2", provider: "cinemeta", payloadJSON: #"{"title":"Two"}"#)

        let records = try await cacheRepository.metadataCacheRecords()
        let size = try await cacheRepository.metadataCacheSizeBytes()

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(size, Int64(#"{"title":"One"}"#.count + #"{"title":"Two"}"#.count))

        try await cacheRepository.removeMetadata(cacheKey: "tmdb:movie:1")
        let remainingKeys = try await cacheRepository.metadataCacheRecords().map(\.cacheKey)
        XCTAssertEqual(remainingKeys, ["cinemeta:movie:2"])

        try await cacheRepository.clearMetadataCache()
        let clearedMetadataSize = try await cacheRepository.metadataCacheSizeBytes()
        XCTAssertEqual(clearedMetadataSize, 0)
    }

    func testSmartCacheManagerSummarizesProtectsAndCleansLocalCache() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let cacheRepository = CacheRepository(databaseManager: databaseManager)
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let torrentRoot = workspace.appendingPathComponent("TorrentCache", isDirectory: true)
        let subtitleRoot = workspace.appendingPathComponent("Subtitles", isDirectory: true)
        let activeTitle = torrentRoot.appendingPathComponent("Active.Movie", isDirectory: true)
        let oldTitle = torrentRoot.appendingPathComponent("Old.Movie", isDirectory: true)
        let unfinishedTitle = torrentRoot.appendingPathComponent("Unfinished.Movie", isDirectory: true)
        let oldSubtitle = subtitleRoot.appendingPathComponent("Old.Movie.ru.srt")
        let imageURL = workspace.appendingPathComponent("poster.jpg")
        defer { try? FileManager.default.removeItem(at: workspace) }

        try FileManager.default.createDirectory(at: activeTitle, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oldTitle, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unfinishedTitle, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subtitleRoot, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 20).write(to: activeTitle.appendingPathComponent("movie.mkv"))
        try Data(repeating: 2, count: 30).write(to: oldTitle.appendingPathComponent("movie.mkv"))
        try Data(repeating: 3, count: 40).write(to: unfinishedTitle.appendingPathComponent("movie.part"))
        try Data(repeating: 4, count: 10).write(to: oldSubtitle)
        try Data(repeating: 5, count: 15).write(to: imageURL)

        let oldDate = Date(timeIntervalSinceNow: -40 * 24 * 60 * 60)
        for url in [oldTitle, unfinishedTitle, oldSubtitle] {
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
        }
        try await cacheRepository.upsertCachedImage(
            url: "https://image.tmdb.org/poster.jpg",
            localPath: imageURL.path,
            fileSize: 15,
            createdAt: ISO8601DateFormatter().string(from: oldDate),
            lastAccessedAt: ISO8601DateFormatter().string(from: oldDate)
        )
        try await cacheRepository.setMetadata(cacheKey: "tmdb:movie:old", provider: "tmdb", payloadJSON: #"{"title":"Old"}"#)

        let suiteName = "streamly.smart-cache.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = LocalSmartCacheManager(cacheRepository: cacheRepository, userDefaults: defaults)
        let scope = SmartCacheScope(torrentCacheURL: torrentRoot, subtitleCacheURL: subtitleRoot)
        let protection = SmartCacheProtection(activeFileURLs: [activeTitle.appendingPathComponent("movie.mkv")])
        let policy = SmartCachePolicy(retentionDays: 30, maxSizeBytes: 64, keepUnfinished: true, removeCompleted: true)

        let initialSummary = try await manager.summary(policy: policy, scope: scope, protection: protection)

        XCTAssertEqual(initialSummary.buckets.first(where: { $0.category == .torrents })?.sizeBytes, 90)
        XCTAssertTrue(initialSummary.titleItems.first(where: { $0.title == "Active" })?.isActive == true)
        XCTAssertTrue(initialSummary.titleItems.first(where: { $0.title == "Unfinished" })?.isCompleted == false)

        let oldTitleID = try XCTUnwrap(initialSummary.titleItems.first(where: { $0.title == "Old" })?.id)
        try await manager.setKeepForLater(itemID: oldTitleID, keep: true)
        let protectedClean = try await manager.runAutoClean(policy: policy, scope: scope, protection: protection)

        XCTAssertGreaterThanOrEqual(protectedClean.protectedItemCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: activeTitle.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldTitle.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unfinishedTitle.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldSubtitle.path))
        let clearedImageSize = try await cacheRepository.imageCacheSizeBytes()
        XCTAssertEqual(clearedImageSize, 0)

        try await manager.setKeepForLater(itemID: oldTitleID, keep: false)
        _ = try await manager.clearTitleCache(itemID: oldTitleID, scope: scope, protection: protection)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldTitle.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: activeTitle.path))
    }

    func testSeedDevelopmentDataIsIdempotent() throws {
        let databaseManager = try DatabaseManager.inMemory()

        try DatabaseSeeder.seedDevelopmentData(in: databaseManager)
        try DatabaseSeeder.seedDevelopmentData(in: databaseManager)

        let count = try databaseManager.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM media_items") ?? 0
        }

        XCTAssertEqual(count, 2)
    }

    private func makeMovie(
        id: String,
        title: String,
        genres: [String] = [],
        cast: [CastMember] = []
    ) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            kind: .movie,
            overview: "Fixture",
            releaseYear: 1999,
            posterPath: nil,
            metadata: MediaMetadata(
                tmdbId: abs(id.hashValue % 100_000),
                title: title,
                originalTitle: title,
                overview: "Fixture",
                year: 1999,
                genres: genres,
                cast: cast
            )
        )
    }
}
