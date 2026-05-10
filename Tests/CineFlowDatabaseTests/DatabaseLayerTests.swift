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

    func testFullAppSettingsPersistAcrossReopen() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let settingsRepository = DatabaseSettingsRepository(databaseManager: databaseManager)

        var settings = AppSettings()
        settings.general.language = .russian
        settings.general.openLastScreenOnLaunch = true
        settings.appearance.reduceMotion = true
        settings.playback.preferredAudioLanguages = ["en", "ru"]
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

    func testSeedDevelopmentDataIsIdempotent() throws {
        let databaseManager = try DatabaseManager.inMemory()

        try DatabaseSeeder.seedDevelopmentData(in: databaseManager)
        try DatabaseSeeder.seedDevelopmentData(in: databaseManager)

        let count = try databaseManager.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM media_items") ?? 0
        }

        XCTAssertEqual(count, 2)
    }

    private func makeMovie(id: String, title: String) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            kind: .movie,
            overview: "Fixture",
            releaseYear: 1999,
            posterPath: nil
        )
    }
}
