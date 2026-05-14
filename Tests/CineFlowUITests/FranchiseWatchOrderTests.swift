import CineFlowCore
import XCTest
@testable import CineFlowUI

final class FranchiseWatchOrderTests: XCTestCase {
    func testKnownFranchiseSupportsReleaseChronologicalAndRecommendedOrders() {
        let collection = Self.starWarsCollection()

        let release = FranchiseWatchOrderResolver.plan(
            for: collection,
            selectedMode: .release,
            progressRecords: []
        )
        XCTAssertEqual(release?.items.map(\.mediaItem.displayTitle), [
            "Star Wars: A New Hope",
            "Star Wars: The Empire Strikes Back",
            "Star Wars: The Phantom Menace",
            "Star Wars: Revenge of the Sith"
        ])

        let chronological = FranchiseWatchOrderResolver.plan(
            for: collection,
            selectedMode: .chronological,
            progressRecords: []
        )
        XCTAssertEqual(chronological?.items.map(\.mediaItem.displayTitle), [
            "Star Wars: The Phantom Menace",
            "Star Wars: Revenge of the Sith",
            "Star Wars: A New Hope",
            "Star Wars: The Empire Strikes Back"
        ])

        let recommended = FranchiseWatchOrderResolver.plan(
            for: collection,
            selectedMode: .recommended,
            progressRecords: []
        )
        XCTAssertEqual(recommended?.items.first?.mediaItem.displayTitle, "Star Wars: A New Hope")
        XCTAssertEqual(recommended?.availableModes, [.release, .chronological, .recommended])
    }

    func testProgressAndNextMovieUseSelectedFranchiseOrder() throws {
        let collection = Self.starWarsCollection()
        let progress = [
            PlaybackProgress(mediaID: "tmdb:movie:1893", positionSeconds: 7_200, durationSeconds: 7_200),
            PlaybackProgress(mediaID: "tmdb:movie:1895", positionSeconds: 7_200, durationSeconds: 7_200)
        ]

        let plan = try XCTUnwrap(FranchiseWatchOrderResolver.plan(
            for: collection,
            selectedMode: .chronological,
            progressRecords: progress
        ))

        XCTAssertEqual(plan.completedCount, 2)
        XCTAssertEqual(plan.totalCount, 4)
        XCTAssertEqual(plan.progressFraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(plan.nextItem?.mediaItem.displayTitle, "Star Wars: A New Hope")
    }

    func testUnknownFranchiseDoesNotExposeUntrustedWatchOrderRecommendation() {
        let collection = MediaCollection(
            id: "user-random-weekend",
            title: "Weekend",
            description: "Manual user list",
            kind: .userCreated,
            items: [
                Self.media(id: "tmdb:movie:1", title: "A Movie", year: 2021),
                Self.media(id: "tmdb:movie:2", title: "Another Movie", year: 1998)
            ].map { CollectionMediaItem(mediaItem: $0) }
        )

        XCTAssertNil(FranchiseWatchOrderResolver.plan(
            for: collection,
            selectedMode: .recommended,
            progressRecords: []
        ))
    }

    @MainActor
    func testCollectionDetailViewModelLetsUserChoosePreferredWatchOrder() async {
        let repository = InMemoryFranchiseProgressRepository(records: [
            PlaybackProgress(mediaID: "tmdb:movie:1893", positionSeconds: 7_200, durationSeconds: 7_200),
            PlaybackProgress(mediaID: "tmdb:movie:1895", positionSeconds: 7_200, durationSeconds: 7_200)
        ])
        let viewModel = CollectionDetailViewModel(
            collectionID: "automatic-star-wars",
            provider: InMemoryFranchiseCollectionProvider(collections: [Self.starWarsCollection()]),
            progressRepository: repository
        )

        await viewModel.load()
        viewModel.setWatchOrder(.chronological)

        XCTAssertEqual(viewModel.watchOrderPlan?.selectedMode, .chronological)
        XCTAssertEqual(viewModel.nextFranchiseItem?.mediaItem.displayTitle, "Star Wars: A New Hope")
        XCTAssertEqual(viewModel.watchOrderPlan?.progressLabel, "2 of 4 watched")
    }

    private static func starWarsCollection() -> MediaCollection {
        let items = [
            media(id: "tmdb:movie:11", title: "Star Wars: A New Hope", year: 1977),
            media(id: "tmdb:movie:1893", title: "Star Wars: The Phantom Menace", year: 1999),
            media(id: "tmdb:movie:1895", title: "Star Wars: Revenge of the Sith", year: 2005),
            media(id: "tmdb:movie:1891", title: "Star Wars: The Empire Strikes Back", year: 1980)
        ]

        return CollectionDiscoveryBuilder.automaticCollections(
            candidates: items,
            libraryIDs: [],
            watchlistIDs: []
        ).first { $0.id == "automatic-star-wars" }!
    }

    private static func media(id: String, title: String, year: Int) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            kind: .movie,
            overview: "\(title) overview",
            releaseYear: year,
            posterPath: nil,
            metadata: MediaMetadata(
                tmdbId: Int(id.split(separator: ":").last ?? "0") ?? 0,
                title: title,
                originalTitle: title,
                overview: "\(title) overview",
                year: year
            )
        )
    }
}

private struct InMemoryFranchiseCollectionProvider: CollectionDiscoveryProviderProtocol {
    let collections: [MediaCollection]

    func collections() async -> [MediaCollection] {
        collections
    }

    func collection(id: String) async -> MediaCollection? {
        collections.first { $0.id == id }
    }
}

private actor InMemoryFranchiseProgressRepository: PlaybackProgressRepositoryProtocol {
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
        records.filter { includeCompleted || !$0.completed }
    }

    func clearProgress(mediaID: String, episodeID: String?) async throws {
        records.removeAll { $0.mediaID == mediaID && $0.episodeID == episodeID }
    }
}
