import XCTest
import Foundation
@testable import CineFlowCore
import CineFlowLocalization
@testable import CineFlowUI

final class ShellNavigationTests: XCTestCase {
    func testSidebarRoutesExposeCineFlowSectionsInOrder() {
        XCTAssertEqual(
            AppRoute.sidebarRoutes.map { L10n.string($0.titleKey, language: .ru) },
            ["Главная", "Поиск", "Фильмы", "Сериалы", "Моя библиотека", "Продолжить", "Списки", "История", "Настройки"]
        )
    }

    func testShellStateStartsOnHomeWithExpectedTopControls() {
        let state = MainShellState()

        XCTAssertEqual(state.selectedRoute, .home)
        XCTAssertEqual(state.topControls.map { L10n.string($0.titleKey, language: .en) }, ["Updates", "Notifications", "Profile"])
    }

    @MainActor
    func testNavigationCoordinatorPushesDeepLinksAndGoesBack() {
        let coordinator = NavigationCoordinator()

        coordinator.navigate(to: .mediaDetail(id: "tmdb:movie:603"))
        coordinator.navigate(to: .player(mediaID: "tmdb:movie:603"))

        XCTAssertEqual(coordinator.currentRoute, .player(mediaID: "tmdb:movie:603"))
        XCTAssertEqual(coordinator.backStack, [.home, .mediaDetail(id: "tmdb:movie:603")])

        coordinator.goBack()

        XCTAssertEqual(coordinator.currentRoute, .mediaDetail(id: "tmdb:movie:603"))
        XCTAssertEqual(coordinator.backStack, [.home])
    }

    @MainActor
    func testNavigationCoordinatorCanOpenPlayerForTorrentRelease() {
        let coordinator = NavigationCoordinator()
        let release = TorrentRelease(
            id: "torrentio:tt0133093:hash:0",
            sourceId: "torrentio",
            sourceName: "Torrentio",
            title: "The Matrix 2160p",
            magnetURI: "magnet:?xt=urn:btih:hash",
            quality: .ultraHD,
            seeders: 334
        )

        coordinator.navigate(to: .player(mediaID: "tmdb:movie:603", release: release))

        XCTAssertEqual(coordinator.currentRoute, .player(mediaID: "tmdb:movie:603", release: release))
    }

    @MainActor
    func testSidebarNavigationPreservesDeepLinkBackStackRoot() {
        let coordinator = NavigationCoordinator()

        coordinator.selectSidebarRoute(.movies)
        coordinator.navigate(to: .mediaDetail(id: "tmdb:movie:603"))
        coordinator.selectSidebarRoute(.settings)

        XCTAssertEqual(coordinator.currentRoute, .settings)
        XCTAssertEqual(coordinator.selectedSidebarRoute, .settings)
        XCTAssertTrue(coordinator.backStack.isEmpty)
    }

    @MainActor
    func testFocusSearchCommandEmitsNewRequestID() {
        let coordinator = NavigationCoordinator()
        let previousID = coordinator.searchFocusRequestID

        coordinator.focusSearchField()

        XCTAssertGreaterThan(coordinator.searchFocusRequestID, previousID)
        XCTAssertEqual(coordinator.currentRoute, .search)
    }

    @MainActor
    func testSettingsImageCacheActionsUseEnvironmentService() async throws {
        let imageCache = TestImageCacheService(sizeBytes: 1_536)
        let viewModel = CineFlowRootViewModel(environment: AppEnvironment(
            metadataService: CoreMockMetadataService(),
            torrentEngine: CoreMockTorrentEngine(),
            playbackService: CoreMockPlaybackService(),
            subtitleService: CoreMockSubtitleService(),
            libraryRepository: CoreMockLibraryRepository(),
            settingsRepository: CoreMockSettingsRepository(),
            diagnosticsService: CoreMockDiagnosticsService(),
            updateService: CoreMockUpdateService(),
            imageCacheService: imageCache
        ))

        await viewModel.refreshImageCacheSize()
        XCTAssertEqual(viewModel.imageCacheSizeBytes, 1_536)

        await viewModel.clearUnusedImageCache()
        let didClearUnused = await imageCache.clearUnusedWasCalled()
        XCTAssertTrue(didClearUnused)

        await viewModel.clearImageCache()
        let didClearAll = await imageCache.clearAllWasCalled()
        XCTAssertEqual(viewModel.imageCacheSizeBytes, 0)
        XCTAssertTrue(didClearAll)
    }
}

private actor TestImageCacheService: ImageCacheServiceProtocol {
    private(set) var didClearAll = false
    private(set) var didClearUnused = false
    private var sizeBytes: Int64

    init(sizeBytes: Int64) {
        self.sizeBytes = sizeBytes
    }

    func imageData(for url: URL, kind: CachedImageKind) async throws -> Data {
        Data()
    }

    func cacheSizeBytes() async throws -> Int64 {
        sizeBytes
    }

    func clearAll() async throws {
        didClearAll = true
        sizeBytes = 0
    }

    func clearUnused(olderThan date: Date) async throws {
        didClearUnused = true
    }

    func clearAllWasCalled() -> Bool {
        didClearAll
    }

    func clearUnusedWasCalled() -> Bool {
        didClearUnused
    }
}
