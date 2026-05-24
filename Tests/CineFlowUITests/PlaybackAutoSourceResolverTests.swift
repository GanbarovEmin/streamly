import XCTest
@testable import CineFlowCore
@testable import CineFlowSources
@testable import CineFlowUI

final class PlaybackAutoSourceResolverTests: XCTestCase {
    @MainActor
    func testRootViewModelUsesSourceManagerForHeroBestRelease() async throws {
        let recorder = QueryRecorder()
        let release = torrentRelease(id: "torrentio:matrix-root", title: "The Matrix 2160p")
        let manager = SourceManager(
            providers: [
                RecordingTorrentProvider(
                    sourceId: "torrentio",
                    defaultIsEnabled: true,
                    expectedQuery: "tt0133093",
                    release: release,
                    recorder: recorder
                )
            ],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        let viewModel = CineFlowRootViewModel(
            environment: AppEnvironment(
                metadataService: ResolverMetadataService(),
                torrentEngine: CoreMockTorrentEngine(),
                playbackService: CoreMockPlaybackService(),
                subtitleService: CoreMockSubtitleService(),
                libraryRepository: CoreMockLibraryRepository(),
                settingsRepository: CoreMockSettingsRepository(),
                diagnosticsService: CoreMockDiagnosticsService(),
                updateService: CoreMockUpdateService(),
                keychainService: MockKeychainService()
            ),
            sourceManager: manager
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.headline, "The Matrix")
        XCTAssertEqual(viewModel.bestReleaseTitle, "The Matrix 2160p")
        XCTAssertEqual(viewModel.bestReleaseSeeders, 120)
    }

    func testResolverEnablesTorrentioAndFindsMovieReleaseFromTMDBID() async throws {
        let recorder = QueryRecorder()
        let release = torrentRelease(id: "torrentio:matrix", title: "The Matrix 2160p")
        let manager = SourceManager(
            providers: [
                RecordingTorrentProvider(
                    sourceId: "torrentio",
                    defaultIsEnabled: false,
                    expectedQuery: "tt0133093",
                    release: release,
                    recorder: recorder
                )
            ],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        let resolver = PlaybackAutoSourceResolver(
            metadataService: ResolverMetadataService(),
            sourceManager: manager,
            diagnosticsService: CoreMockDiagnosticsService()
        )

        let initiallyActive = try await manager.activeProviders()
        XCTAssertTrue(initiallyActive.isEmpty)

        let resolution = await resolver.resolveBestRelease(mediaID: "tmdb:movie:603", selectionContext: nil)
        let recordedQueries = await recorder.queries()
        let activeProviderIDs = try await manager.activeProviders().map(\.sourceId)

        XCTAssertEqual(resolution?.release.id, release.id)
        XCTAssertEqual(resolution?.selectionContext?.displayTitle, "The Matrix")
        XCTAssertEqual(recordedQueries, ["tt0133093"])
        XCTAssertEqual(activeProviderIDs, ["torrentio"])
    }

    func testResolverRanksAutoPlaybackTowardHealthySmall1080pRelease() async throws {
        let recorder = QueryRecorder()
        let large4K = torrentRelease(
            id: "torrentio:project-hail-mary:large-4k",
            title: "Project Hail Mary 2160p 31GB",
            quality: .ultraHD,
            seeders: 800,
            sizeBytes: 31_000_000_000
        )
        let healthy1080p = torrentRelease(
            id: "torrentio:project-hail-mary:psa-1080p",
            title: "Project Hail Mary 1080p PSA",
            quality: .fullHD,
            seeders: 1_600,
            sizeBytes: 2_700_000_000
        )
        let manager = SourceManager(
            providers: [
                RecordingTorrentProvider(
                    sourceId: "torrentio",
                    defaultIsEnabled: true,
                    expectedQuery: "tt12042730",
                    releases: [large4K, healthy1080p],
                    recorder: recorder
                )
            ],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        let resolver = PlaybackAutoSourceResolver(
            metadataService: ResolverMetadataService(),
            sourceManager: manager,
            diagnosticsService: CoreMockDiagnosticsService()
        )

        let resolution = await resolver.resolveBestRelease(
            mediaID: "imdb:movie:tt12042730",
            selectionContext: nil,
            rankingPreferences: RankingPreferences(preferHighSeedersOverHighestQuality: true)
        )

        XCTAssertEqual(resolution?.release.id, healthy1080p.id)
        XCTAssertEqual(resolution?.fallbackReleases.map(\.id), [healthy1080p.id, large4K.id])
    }

    func testResolverBuildsSeriesEpisodeQueryWhenPlayerHasOnlySeriesID() async throws {
        let recorder = QueryRecorder()
        let release = torrentRelease(id: "torrentio:got-s1e1", title: "Game of Thrones S01E01")
        let manager = SourceManager(
            providers: [
                RecordingTorrentProvider(
                    sourceId: "torrentio",
                    defaultIsEnabled: true,
                    expectedQuery: "tt0944947:1:1",
                    release: release,
                    recorder: recorder
                )
            ],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        let resolver = PlaybackAutoSourceResolver(
            metadataService: ResolverMetadataService(),
            sourceManager: manager,
            diagnosticsService: CoreMockDiagnosticsService()
        )

        let noContext: PlaybackSelectionContext? = nil
        let resolution = await resolver.resolveBestRelease(mediaID: "tmdb:tv:1399", selectionContext: noContext)
        let recordedQueries = await recorder.queries()

        XCTAssertEqual(resolution?.release.id, release.id)
        XCTAssertEqual(resolution?.selectionContext?.seasonNumber, 1)
        XCTAssertEqual(resolution?.selectionContext?.episodeNumber, 1)
        XCTAssertEqual(resolution?.selectionContext?.episodeID, "tt0944947:1:1")
        XCTAssertEqual(recordedQueries, ["tt0944947:1:1"])
    }

    private func torrentRelease(
        id: String,
        title: String,
        quality: ReleaseQuality = .ultraHD,
        seeders: Int = 120,
        sizeBytes: Int64? = nil
    ) -> TorrentRelease {
        TorrentRelease(
            id: id,
            sourceId: "torrentio",
            sourceName: "Torrentio",
            title: title,
            magnetURI: "magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12",
            quality: quality,
            seeders: seeders,
            sizeBytes: sizeBytes
        )
    }
}

private actor QueryRecorder {
    private var values: [String] = []

    func record(_ query: String) {
        values.append(query)
    }

    func queries() -> [String] {
        values
    }
}

private struct RecordingTorrentProvider: TorrentSourceProviderProtocol {
    let sourceId: String
    let displayName = "Torrentio"
    let requiresAuthentication = false
    let isEnabled = true
    let defaultIsEnabled: Bool
    let expectedQuery: String
    let releases: [TorrentRelease]
    let recorder: QueryRecorder

    init(
        sourceId: String,
        defaultIsEnabled: Bool,
        expectedQuery: String,
        release: TorrentRelease,
        recorder: QueryRecorder
    ) {
        self.init(
            sourceId: sourceId,
            defaultIsEnabled: defaultIsEnabled,
            expectedQuery: expectedQuery,
            releases: [release],
            recorder: recorder
        )
    }

    init(
        sourceId: String,
        defaultIsEnabled: Bool,
        expectedQuery: String,
        releases: [TorrentRelease],
        recorder: QueryRecorder
    ) {
        self.sourceId = sourceId
        self.defaultIsEnabled = defaultIsEnabled
        self.expectedQuery = expectedQuery
        self.releases = releases
        self.recorder = recorder
    }

    func search(query: String, filters: TorrentSourceSearchFilters) async throws -> [TorrentRelease] {
        await recorder.record(query)
        return query == expectedQuery ? releases : []
    }

    func fetchDetails(releaseId: String) async throws -> TorrentReleaseDetails {
        guard let release = releases.first(where: { $0.id == releaseId }) ?? releases.first else {
            throw SourceProviderError.releaseNotFound(sourceId: sourceId, releaseId: releaseId)
        }
        return TorrentReleaseDetails(release: release, description: nil)
    }

    func validateSession() async throws -> SourceAuthenticationStatus {
        .notRequired
    }
}

private struct ResolverMetadataService: MetadataServiceProtocol {
    func search(query: String) async throws -> [MediaItem] {
        [
            MediaItem(
                id: "tmdb:movie:603",
                title: "The Matrix",
                kind: .movie,
                overview: "A hacker discovers the truth.",
                releaseYear: 1999,
                posterPath: nil
            )
        ]
    }

    func movieDetail(tmdbID: Int) async throws -> Movie {
        let metadata = MediaMetadata(
            tmdbId: tmdbID,
            imdbId: "tt0133093",
            title: "The Matrix",
            originalTitle: "The Matrix",
            overview: "A hacker discovers the truth.",
            year: 1999
        )
        let item = MediaItem(
            id: "tmdb:movie:\(tmdbID)",
            title: "The Matrix",
            kind: .movie,
            overview: metadata.overview,
            releaseYear: metadata.year,
            posterPath: nil,
            metadata: metadata
        )
        return Movie(id: item.id, mediaItem: item, metadata: metadata)
    }

    func seriesDetail(tmdbID: Int) async throws -> Series {
        let metadata = MediaMetadata(
            tmdbId: tmdbID,
            imdbId: "tt0944947",
            title: "Game of Thrones",
            originalTitle: "Game of Thrones",
            overview: "Noble families fight for control.",
            year: 2011
        )
        let item = MediaItem(
            id: "tmdb:tv:\(tmdbID)",
            title: "Game of Thrones",
            kind: .series,
            overview: metadata.overview,
            releaseYear: metadata.year,
            posterPath: nil,
            metadata: metadata
        )
        let episode = Episode(
            id: "tmdb:tv:\(tmdbID):season:1:episode:1",
            seriesID: item.id,
            seasonID: "tmdb:tv:\(tmdbID):season:1",
            episodeNumber: 1,
            title: "Winter Is Coming",
            airDate: Date(timeIntervalSince1970: 1_300_000_000)
        )
        let season = Season(
            id: "tmdb:tv:\(tmdbID):season:1",
            seriesID: item.id,
            seasonNumber: 1,
            title: "Season 1",
            episodes: [episode]
        )
        return Series(id: item.id, mediaItem: item, metadata: metadata, seasons: [season])
    }
}
