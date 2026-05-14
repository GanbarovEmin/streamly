import CineFlowCore
import XCTest
@testable import CineFlowUI

final class BetterReleaseNotificationTests: XCTestCase {
    func testBetterReleaseNotificationsRespectSettingsDigestAndOncePerMedia() async throws {
        let initial = Self.media(
            id: "tmdb:movie:603",
            title: "The Matrix",
            releases: [
                TorrentRelease(id: "matrix-1080p", title: "The Matrix 1080p", quality: .fullHD, seeders: 20)
            ]
        )
        let improved = Self.media(
            id: initial.id,
            title: initial.title,
            releases: [
                TorrentRelease(id: "matrix-4k-hdr-ru", title: "The Matrix 2160p HDR RU", quality: .ultraHD, hdr: .hdr10, audioLanguages: ["ru", "en"], seeders: 120)
            ]
        )
        let libraryRepository = BetterReleaseMemoryLibraryRepository(items: [initial])
        let settingsRepository = BetterReleaseMemorySettingsRepository(settings: AppSettings())
        let store = InMemoryBetterReleaseNotificationStore()
        let service = BetterReleaseNotificationService(
            libraryRepository: libraryRepository,
            settingsRepository: settingsRepository,
            store: store
        )

        let baseline = try await service.scanForBetterReleases()
        XCTAssertTrue(baseline.notifications.isEmpty)

        await libraryRepository.replaceItems([improved])
        let digest = try await service.scanForBetterReleases()

        XCTAssertTrue(digest.isDigestMode)
        XCTAssertEqual(digest.notifications.map(\.mediaID), [initial.id])
        XCTAssertEqual(digest.notifications.first?.route, .mediaDetail(id: initial.id))
        XCTAssertEqual(
            Set(digest.notifications.first?.triggers ?? []),
            [.new4KRelease, .hdrVersionAvailable, .russianAudioAvailable, .betterSeededRelease, .healthierRelease]
        )

        let secondDigest = try await service.scanForBetterReleases()
        XCTAssertTrue(secondDigest.notifications.isEmpty)

        var disabledSettings = AppSettings()
        disabledSettings.notifications.betterReleaseNotificationsEnabled = false
        await settingsRepository.setAppSettings(disabledSettings)
        await libraryRepository.replaceItems([
            Self.media(
                id: "tmdb:movie:329865",
                title: "Arrival",
                releases: [
                    TorrentRelease(id: "arrival-4k", title: "Arrival 2160p", quality: .ultraHD, seeders: 80)
                ]
            )
        ])

        let disabledDigest = try await service.scanForBetterReleases()
        XCTAssertTrue(disabledDigest.notifications.isEmpty)
    }

    @MainActor
    func testNotificationCenterViewModelLoadsUnreadItemsAndMarksRead() async throws {
        let notification = BetterReleaseNotification(
            mediaID: "tmdb:movie:603",
            mediaTitle: "The Matrix",
            releaseID: "matrix-4k",
            triggers: [.new4KRelease],
            createdAt: Date()
        )
        let store = InMemoryBetterReleaseNotificationStore(notifications: [notification])
        let viewModel = BetterReleaseNotificationCenterViewModel(store: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.notifications.map(\.mediaID), [notification.mediaID])
        XCTAssertEqual(viewModel.unreadCount, 1)
        XCTAssertEqual(viewModel.notifications.first?.route, .mediaDetail(id: notification.mediaID))

        await viewModel.markRead(notification.id)

        XCTAssertEqual(viewModel.unreadCount, 0)
    }

    private static func media(id: String, title: String, releases: [TorrentRelease]) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            kind: .movie,
            overview: "Fixture",
            releaseYear: 1999,
            posterPath: nil,
            torrentReleases: releases
        )
    }
}

private actor BetterReleaseMemoryLibraryRepository: LibraryRepositoryProtocol {
    private var storedItems: [MediaItem]
    private var storedLists: [UserList] = []

    init(items: [MediaItem]) {
        storedItems = items
    }

    func replaceItems(_ items: [MediaItem]) {
        storedItems = items
    }

    func items() async throws -> [MediaItem] { storedItems }
    func add(_ item: MediaItem) async throws { storedItems.append(item) }
    func remove(mediaID: String) async throws { storedItems.removeAll { $0.id == mediaID } }
    func favorites() async throws -> [MediaItem] { [] }
    func addFavorite(_ item: MediaItem) async throws {}
    func removeFavorite(mediaID: String) async throws {}
    func watchedItems() async throws -> [WatchedMediaItem] { [] }
    func markWatched(_ item: MediaItem, positionSeconds: Double) async throws {}
    func ratedItems() async throws -> [RatedMediaItem] { [] }
    func setRating(_ item: MediaItem, rating: Int) async throws {}
    func lists() async throws -> [UserList] { storedLists }
    func defaultList() async throws -> UserList {
        if let existing = storedLists.first(where: \.isDefault) {
            return existing
        }
        let list = UserList(id: "default-watchlist", name: "Хочу посмотреть", isDefault: true)
        storedLists.append(list)
        return list
    }
    func createList(name: String) async throws -> UserList { try await createList(name: name, description: nil) }
    func createList(name: String, description: String?) async throws -> UserList {
        let list = UserList(name: name, description: description)
        storedLists.append(list)
        return list
    }
    func renameList(id: String, name: String, description: String?) async throws {}
    func deleteList(id: String) async throws {}
    func add(_ item: MediaItem, to listID: String) async throws {}
    func remove(_ mediaID: String, from listID: String) async throws {}
    func items(in listID: String) async throws -> [MediaItem] { [] }
}

private actor BetterReleaseMemorySettingsRepository: SettingsRepositoryProtocol {
    private var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var appSettings: AppSettings {
        get async { settings }
    }

    var subtitleLanguagePriority: [String] {
        get async { ["ru", "en"] }
    }

    var subtitleSettings: SubtitleSettings {
        get async { SubtitleSettings() }
    }

    func setAppSettings(_ settings: AppSettings) async {
        self.settings = settings
    }

    func setSubtitleLanguagePriority(_ languages: [String]) async {}
    func setSubtitleSettings(_ settings: SubtitleSettings) async {}
    func metadataCredential(forKey key: String) async -> String? { nil }
    func setMetadataCredential(_ value: String?, forKey key: String) async {}
    func clearAllLocalData() async {}
}
