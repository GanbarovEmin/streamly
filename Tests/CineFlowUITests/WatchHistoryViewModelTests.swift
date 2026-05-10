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
