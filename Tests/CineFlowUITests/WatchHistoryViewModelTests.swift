import CineFlowCore
import XCTest
@testable import CineFlowUI

final class WatchHistoryViewModelTests: XCTestCase {
    @MainActor
    func testContinueWatchingHidesCompletedItemsAndSortsByLastWatched() async throws {
        let repository = InMemoryPlaybackProgressRepository(records: [
            PlaybackProgress(
                mediaID: "tmdb:movie:603",
                positionSeconds: 45,
                durationSeconds: 100,
                lastWatchedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            PlaybackProgress(
                mediaID: "tmdb:tv:1399",
                episodeID: "got-s1-e2",
                positionSeconds: 95,
                durationSeconds: 100,
                lastWatchedAt: Date(timeIntervalSince1970: 1_800_010_000)
            ),
            PlaybackProgress(
                mediaID: "tmdb:movie:329865",
                positionSeconds: 50,
                durationSeconds: 100,
                lastWatchedAt: Date(timeIntervalSince1970: 1_800_020_000)
            )
        ])

        let viewModel = ContinueWatchingViewModel(repository: repository)
        await viewModel.load()

        XCTAssertEqual(viewModel.items.map(\.mediaID), ["tmdb:movie:329865", "tmdb:movie:603"])
        XCTAssertTrue(viewModel.items.allSatisfy { !$0.completed })
    }

    @MainActor
    func testContinueWatchingResolvesStoredMediaTitleAndArtwork() async throws {
        let posterURL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w500/matrix.jpg"))
        let mediaItem = Self.mediaItem(id: "tmdb:movie:603", title: "The Matrix", kind: .movie, posterURL: posterURL)
        let repository = InMemoryPlaybackProgressRepository(records: [
            PlaybackProgress(mediaID: mediaItem.id, positionSeconds: 45, durationSeconds: 100)
        ])
        let viewModel = ContinueWatchingViewModel(
            repository: repository,
            libraryRepository: CoreMockLibraryRepository(storedItems: [mediaItem])
        )

        await viewModel.load()

        let card = try XCTUnwrap(viewModel.cardItems.first?.model)
        XCTAssertEqual(card.title, "The Matrix")
        XCTAssertEqual(card.artworkURL, posterURL)
        XCTAssertFalse(card.title.contains("Фильм"))
    }

    @MainActor
    func testContinueWatchingUsesMetadataServiceForTechnicalPlaceholderTitle() async throws {
        let posterURL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w500/matrix.jpg"))
        let placeholder = MediaItem(
            id: "tmdb:movie:603",
            title: "tmdb:movie:603",
            kind: .movie,
            overview: "",
            releaseYear: 1999,
            posterPath: nil
        )
        let repository = InMemoryPlaybackProgressRepository(records: [
            PlaybackProgress(mediaID: placeholder.id, positionSeconds: 30, durationSeconds: 100)
        ])
        let viewModel = ContinueWatchingViewModel(
            repository: repository,
            libraryRepository: CoreMockLibraryRepository(storedItems: [placeholder]),
            metadataService: ViewingMetadataFixtureService(movie: Self.mediaItem(id: placeholder.id, title: "The Matrix", kind: .movie, posterURL: posterURL))
        )

        await viewModel.load()

        let card = try XCTUnwrap(viewModel.cardItems.first?.model)
        XCTAssertEqual(card.title, "The Matrix")
        XCTAssertEqual(card.artworkURL, posterURL)
    }

    @MainActor
    func testHistoryFiltersByMoviesAndSeriesAndClearHistory() async throws {
        let repository = InMemoryWatchHistoryRepository(entries: [
            WatchHistoryItem(
                mediaID: "tmdb:movie:603",
                positionSeconds: 45,
                durationSeconds: 100,
                lastWatchedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            WatchHistoryItem(
                mediaID: "tmdb:tv:1399",
                episodeID: "got-s1-e2",
                positionSeconds: 20,
                durationSeconds: 100,
                lastWatchedAt: Date(timeIntervalSince1970: 1_800_010_000)
            )
        ])

        let viewModel = WatchHistoryViewModel(repository: repository)
        await viewModel.load()

        viewModel.setFilter(.movies)
        XCTAssertEqual(viewModel.visibleEntries.map(\.mediaID), ["tmdb:movie:603"])

        viewModel.setFilter(.series)
        XCTAssertEqual(viewModel.visibleEntries.map(\.mediaID), ["tmdb:tv:1399"])

        await viewModel.clearHistory()

        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertTrue(viewModel.visibleEntries.isEmpty)
    }

    @MainActor
    func testHistoryResolvesRealTitleArtworkAndSeriesEpisodeMetadata() async throws {
        let moviePosterURL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w500/matrix.jpg"))
        let seriesPosterURL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w500/got.jpg"))
        let movie = Self.mediaItem(id: "tmdb:movie:603", title: "The Matrix", kind: .movie, posterURL: moviePosterURL)
        let series = Self.mediaItem(id: "tmdb:tv:1399", title: "Game of Thrones", kind: .series, posterURL: seriesPosterURL)
        let repository = InMemoryWatchHistoryRepository(entries: [
            WatchHistoryItem(
                id: "history-movie",
                mediaID: movie.id,
                positionSeconds: 45,
                durationSeconds: 100,
                lastWatchedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            WatchHistoryItem(
                id: "history-series",
                mediaID: series.id,
                episodeID: "got-s1-e2",
                positionSeconds: 20,
                durationSeconds: 100,
                lastWatchedAt: Date(timeIntervalSince1970: 1_800_010_000)
            )
        ])
        let viewModel = WatchHistoryViewModel(
            repository: repository,
            libraryRepository: CoreMockLibraryRepository(storedItems: [movie, series])
        )

        await viewModel.load()

        let movieEntry = try XCTUnwrap(viewModel.entries.first { $0.id == "history-movie" })
        let movieCard = viewModel.cardModel(for: movieEntry)
        XCTAssertEqual(movieCard.title, "The Matrix")
        XCTAssertEqual(movieCard.artworkURL, moviePosterURL)

        let seriesEntry = try XCTUnwrap(viewModel.entries.first { $0.id == "history-series" })
        let seriesCard = viewModel.cardModel(for: seriesEntry)
        XCTAssertEqual(seriesCard.title, "Game of Thrones")
        XCTAssertEqual(seriesCard.artworkURL, seriesPosterURL)
        XCTAssertTrue(seriesCard.metadata.contains("S01E02"))
        XCTAssertFalse(seriesCard.title.contains("Серия"))
    }

    private static func mediaItem(id: String, title: String, kind: MediaKind, posterURL: URL) -> MediaItem {
        let metadata = MediaMetadata(
            tmdbId: Int(id.split(separator: ":").last ?? "0") ?? 0,
            title: title,
            originalTitle: title,
            overview: "Fixture.",
            year: 1999,
            posterURL: posterURL
        )
        return MediaItem(
            id: id,
            title: title,
            kind: kind,
            overview: metadata.overview,
            releaseYear: metadata.year,
            posterPath: nil,
            metadata: metadata
        )
    }
}

private actor InMemoryPlaybackProgressRepository: PlaybackProgressRepositoryProtocol {
    private var records: [PlaybackProgress]

    init(records: [PlaybackProgress]) {
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

private actor InMemoryWatchHistoryRepository: WatchHistoryRepositoryProtocol {
    private var storedEntries: [WatchHistoryItem]

    init(entries: [WatchHistoryItem]) {
        storedEntries = entries
    }

    func record(_ progress: PlaybackProgress) async throws {
        storedEntries.append(WatchHistoryItem(progress: progress))
    }

    func entries(limit: Int) async throws -> [WatchHistoryItem] {
        Array(storedEntries.sorted { $0.lastWatchedAt > $1.lastWatchedAt }.prefix(limit))
    }

    func clear() async throws {
        storedEntries = []
    }
}

private struct ViewingMetadataFixtureService: MetadataServiceProtocol {
    let movie: MediaItem

    func search(query: String) async throws -> [MediaItem] {
        [movie]
    }

    func movieDetail(tmdbID: Int) async throws -> Movie {
        Movie(id: movie.id, mediaItem: movie, metadata: movie.metadata!)
    }
}
