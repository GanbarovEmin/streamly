import CineFlowCore
import XCTest
@testable import CineFlowUI

@MainActor
final class NotificationCenterTests: XCTestCase {
    func testNotificationCenterSeparatesCriticalItemsAndSupportsReadAndClearAll() async {
        let store = InMemoryNotificationCenterStore()
        let viewModel = NotificationCenterViewModel(store: store)

        await store.addNotification(AppNotification(
            id: "update:v1.1",
            title: "Update available",
            message: "Streamly 1.1 is ready to install.",
            category: .update,
            severity: .informational,
            destination: .settingsSection(SettingsSectionID.updates.rawValue),
            createdAt: Date(timeIntervalSince1970: 20)
        ))
        await store.addNotification(AppNotification(
            id: "source:torrentio:auth",
            title: "Source sign-in expired",
            message: "Torrentio needs attention before searches can use it.",
            category: .sourceAuth,
            severity: .critical,
            destination: .settingsSection(SettingsSectionID.sources.rawValue),
            createdAt: Date(timeIntervalSince1970: 10)
        ))
        await store.addNotification(AppNotification(
            id: "episode:tmdb:tv:1399:s01e02",
            title: "New episode",
            message: "A new episode is available.",
            category: .newEpisode,
            severity: .informational,
            destination: .mediaDetail("tmdb:tv:1399"),
            createdAt: Date(timeIntervalSince1970: 30)
        ))

        await viewModel.load()

        XCTAssertEqual(viewModel.unreadCount, 3)
        XCTAssertEqual(viewModel.criticalNotifications.map(\.category), [.sourceAuth])
        XCTAssertEqual(viewModel.informationalNotifications.map(\.category), [.newEpisode, .update])
        XCTAssertEqual(viewModel.notification(withID: "update:v1.1")?.route, .settingsSection(id: SettingsSectionID.updates.rawValue))

        await viewModel.markAllRead()

        XCTAssertEqual(viewModel.unreadCount, 0)

        await viewModel.clearAll()

        XCTAssertTrue(viewModel.notifications.isEmpty)
    }

    func testNotificationCenterFiltersDisabledCategoriesFromLocalSettings() async {
        var settings = AppSettings()
        settings.notifications.setCategory(.announcement, isEnabled: false)
        let settingsRepository = NotificationCenterMemorySettingsRepository(settings: settings)
        let store = InMemoryNotificationCenterStore()
        let viewModel = NotificationCenterViewModel(store: store, settingsRepository: settingsRepository)

        await store.addNotification(AppNotification(
            id: "announcement:welcome",
            title: "Announcement",
            message: "A quiet app announcement.",
            category: .announcement,
            severity: .informational,
            destination: .home
        ))
        await store.addNotification(AppNotification(
            id: "cache:almost-full",
            title: "Cache almost full",
            message: "Streamly cache is close to its local limit.",
            category: .cache,
            severity: .critical,
            destination: .settingsSection(SettingsSectionID.cache.rawValue)
        ))

        await viewModel.load()

        XCTAssertEqual(viewModel.notifications.map(\.category), [.cache])
    }

    func testNotificationCenterIngestsSeriesDigestAsNewEpisodeNotification() async {
        let store = InMemoryNotificationCenterStore()
        let viewModel = NotificationCenterViewModel(store: store)
        let episode = NewSeriesEpisode(
            seriesID: "tmdb:tv:1399",
            seriesTitle: "Game of Thrones",
            episode: SeriesEpisode(
                id: "s01e02",
                seasonID: "season-1",
                seasonNumber: 1,
                episodeNumber: 2,
                title: "The Kingsroad",
                runtime: "55 min",
                overview: "Fixture"
            ),
            availability: .sourceAvailable(bestReleaseID: "got-s01e02", qualityLabel: "1080p", sourceName: "Torrentio"),
            releasedAt: Date(timeIntervalSince1970: 40)
        )
        let digest = SeriesTrackingDigest(items: [
            SeriesTrackingNotification(kind: .newEpisodeAvailable, episode: episode)
        ])

        await viewModel.ingest(digest)

        XCTAssertEqual(viewModel.notifications.map(\.category), [.newEpisode])
        XCTAssertEqual(viewModel.notifications.first?.route, .mediaDetail(id: episode.seriesID))
    }
}

private actor NotificationCenterMemorySettingsRepository: SettingsRepositoryProtocol {
    private var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var appSettings: AppSettings { settings }
    func setAppSettings(_ settings: AppSettings) async { self.settings = settings }
    var subtitleLanguagePriority: [String] { ["ru", "en"] }
    func setSubtitleLanguagePriority(_ languages: [String]) async {}
    var subtitleSettings: SubtitleSettings { SubtitleSettings() }
    func setSubtitleSettings(_ settings: SubtitleSettings) async {}
    func metadataCredential(forKey key: String) async -> String? { nil }
    func setMetadataCredential(_ value: String?, forKey key: String) async {}
}
