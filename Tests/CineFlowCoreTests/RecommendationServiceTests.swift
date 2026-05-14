import XCTest
@testable import CineFlowCore

final class RecommendationServiceTests: XCTestCase {
    func testLocalRecommendationServiceBuildsSectionsFromLocalSignalsWithoutMetadataNetwork() async throws {
        let watched = recommendationItem(id: "tmdb:movie:1", title: "Watched Space", kind: .movie, genres: ["Sci-Fi"], rating: 8.0)
        let favorite = recommendationItem(id: "tmdb:movie:2", title: "Favorite Space", kind: .movie, genres: ["Sci-Fi", "Adventure"], rating: 9.0)
        let candidate = recommendationItem(id: "tmdb:movie:3", title: "Local Candidate", kind: .movie, genres: ["Sci-Fi"], rating: 7.6)
        let quietDrama = recommendationItem(id: "tmdb:movie:4", title: "Quiet Drama", kind: .movie, genres: ["Drama"], rating: 7.0)
        let series = recommendationItem(id: "tmdb:tv:5", title: "Tracked Series", kind: .series, genres: ["Sci-Fi"], rating: 8.2)
        let favoriteGenreCandidate = recommendationItem(id: "tmdb:movie:6", title: "Adventure Candidate", kind: .movie, genres: ["Adventure"], rating: 7.4)
        let repository = RecommendationMemoryLibraryRepository(storedItems: [watched, favorite, candidate, quietDrama, series, favoriteGenreCandidate])
        try await repository.markWatched(watched, positionSeconds: 0)
        try await repository.addFavorite(favorite)
        try await repository.setRating(favorite, rating: 9)
        let progressRepository = RecommendationMemoryProgressRepository(records: [
            PlaybackProgress(mediaID: series.id, episodeID: "s1e2", positionSeconds: 1_200, durationSeconds: 2_400)
        ])
        let service = LocalRecommendationService(
            libraryRepository: repository,
            progressRepository: progressRepository,
            metadataService: nil
        )

        let sections = try await service.homeRecommendations(limit: 6)

        XCTAssertTrue(sections.map(\.kind).contains(.becauseYouWatched))
        XCTAssertTrue(sections.map(\.kind).contains(.fromFavoriteGenres))
        XCTAssertTrue(sections.map(\.kind).contains(.continueSeries))
        XCTAssertTrue(sections.first { $0.kind == .becauseYouWatched }?.items.contains(candidate) == true)
        XCTAssertFalse(sections.first { $0.kind == .becauseYouWatched }?.items.contains(watched) == true)
        XCTAssertEqual(sections.first { $0.kind == .continueSeries }?.items.map(\.id), [series.id])
    }

    func testLocalRecommendationServiceUsesSeedSimilarAndFallsBackToLocalGenreMatchesForDetail() async throws {
        let seed = recommendationItem(id: "tmdb:movie:10", title: "Seed", kind: .movie, genres: ["Mystery"], rating: 8.1)
        let localMatch = recommendationItem(id: "tmdb:movie:11", title: "Local Mystery", kind: .movie, genres: ["Mystery"], rating: 8.0)
        let tmdbSimilar = recommendationItem(id: "tmdb:movie:12", title: "TMDB Similar", kind: .movie, genres: ["Mystery"], rating: 7.8)
        let repository = RecommendationMemoryLibraryRepository(storedItems: [seed, localMatch])
        let service = LocalRecommendationService(
            libraryRepository: repository,
            progressRepository: nil,
            metadataService: nil
        )

        let recommendations = try await service.recommendations(
            for: seed,
            seedSimilar: [tmdbSimilar],
            limit: 4
        )

        XCTAssertEqual(recommendations.map(\.id), [localMatch.id, tmdbSimilar.id])
    }

    func testExpandedRecommendationsUseTasteListsPeopleProgressAndAvoidDuplicates() async throws {
        let completed = recommendationItem(
            id: "tmdb:movie:20",
            title: "Completed Space",
            kind: .movie,
            genres: ["Sci-Fi"],
            rating: 8.4,
            cast: [CastMember(id: "actor:a", name: "A. Actor")]
        )
        let abandoned = recommendationItem(id: "tmdb:movie:21", title: "Abandoned Space", kind: .movie, genres: ["Sci-Fi"], rating: 8.9)
        let hiddenGem = recommendationItem(
            id: "tmdb:movie:22",
            title: "Quiet Gem",
            kind: .movie,
            genres: ["Sci-Fi"],
            rating: 8.8,
            cast: [CastMember(id: "actor:a", name: "A. Actor")]
        )
        let popularGenre = recommendationItem(id: "tmdb:movie:23", title: "Popular Genre", kind: .movie, genres: ["Sci-Fi"], rating: 8.2)
        let unfinished = recommendationItem(id: "tmdb:movie:24", title: "Paused Movie", kind: .movie, genres: ["Drama"], rating: 7.2)
        let hiddenGenre = recommendationItem(id: "tmdb:movie:25", title: "Hidden Horror", kind: .movie, genres: ["Horror"], rating: 9.0)
        let listed = recommendationItem(id: "tmdb:movie:26", title: "Listed Space", kind: .movie, genres: ["Sci-Fi"], rating: 7.9)
        let repository = RecommendationMemoryLibraryRepository(storedItems: [completed, abandoned, hiddenGem, popularGenre, unfinished, hiddenGenre, listed])
        try await repository.markWatched(completed, positionSeconds: 7_200)
        try await repository.setRating(completed, rating: 10)
        try await repository.add(listed, to: "watchlist")
        let progressRepository = RecommendationMemoryProgressRepository(records: [
            PlaybackProgress(mediaID: completed.id, positionSeconds: 7_200, durationSeconds: 7_200, completed: true),
            PlaybackProgress(mediaID: abandoned.id, positionSeconds: 300, durationSeconds: 7_200),
            PlaybackProgress(mediaID: unfinished.id, positionSeconds: 3_000, durationSeconds: 7_200)
        ])
        var settings = AppSettings()
        settings.tasteProfile.setGenre("Sci-Fi", preference: .more)
        settings.tasteProfile.setGenre("Horror", preference: .hidden)
        let settingsRepository = CoreMockSettingsRepository(settings: settings)
        let service = LocalRecommendationService(
            libraryRepository: repository,
            progressRepository: progressRepository,
            metadataService: nil,
            settingsRepository: settingsRepository
        )

        let sections = try await service.homeRecommendations(limit: 6)
        let allRecommendedIDs = sections.flatMap { $0.items.map(\.id) }

        XCTAssertTrue(sections.map(\.kind).contains(.hiddenGems))
        XCTAssertTrue(sections.map(\.kind).contains(.popularInFavoriteGenres))
        XCTAssertTrue(sections.map(\.kind).contains(.notFinishedYet))
        XCTAssertEqual(Set(allRecommendedIDs).count, allRecommendedIDs.count)
        XCTAssertFalse(allRecommendedIDs.contains(completed.id))
        XCTAssertFalse(allRecommendedIDs.contains(abandoned.id))
        XCTAssertFalse(allRecommendedIDs.contains(hiddenGenre.id))
        XCTAssertEqual(sections.first { $0.kind == .notFinishedYet }?.items.map(\.id), [unfinished.id])
        XCTAssertTrue(sections.first { $0.kind == .hiddenGems }?.items.contains(hiddenGem) == true)
        XCTAssertTrue(sections.first { $0.kind == .popularInFavoriteGenres }?.explanation(for: popularGenre).contains("Sci-Fi") == true)
        XCTAssertTrue(sections.first { $0.kind == .hiddenGems }?.explanation(for: hiddenGem).contains("A. Actor") == true)
    }

    func testTasteProfileSettingsPersistManualGenreControls() throws {
        var profile = TasteProfileSettings()

        profile.setGenre("Sci-Fi", preference: .more)
        profile.setGenre("Horror", preference: .hidden)
        profile.preferredMediaKinds = [.movie]
        profile.preferredDuration = .featureLength

        let decoded = try JSONDecoder().decode(TasteProfileSettings.self, from: try JSONEncoder().encode(profile))

        XCTAssertEqual(decoded.preference(forGenre: "sci-fi"), .more)
        XCTAssertEqual(decoded.preference(forGenre: "Horror"), .hidden)
        XCTAssertEqual(decoded.preferredMediaKinds, [.movie])
        XCTAssertEqual(decoded.preferredDuration, .featureLength)
        XCTAssertGreaterThan(decoded.syncRevision, 0)
    }

    func testNegativeRecommendationSignalsExcludeTitlesWithoutDeletingLibraryData() async throws {
        let hidden = recommendationItem(id: "tmdb:movie:31", title: "Hidden Space", kind: .movie, genres: ["Sci-Fi"], rating: 8.9)
        let notInterested = recommendationItem(id: "tmdb:movie:32", title: "Not Interested Space", kind: .movie, genres: ["Sci-Fi"], rating: 8.7)
        let removed = recommendationItem(id: "tmdb:movie:33", title: "Removed Space", kind: .movie, genres: ["Sci-Fi"], rating: 8.4)
        let visible = recommendationItem(id: "tmdb:movie:34", title: "Visible Space", kind: .movie, genres: ["Sci-Fi"], rating: 8.1)
        let watched = recommendationItem(id: "tmdb:movie:35", title: "Watched Space", kind: .movie, genres: ["Sci-Fi"], rating: 8.0)
        let repository = RecommendationMemoryLibraryRepository(storedItems: [hidden, notInterested, removed, visible, watched])
        try await repository.markWatched(watched, positionSeconds: 7_200)
        var settings = AppSettings()
        settings.tasteProfile.hideTitle(mediaID: hidden.id, title: hidden.displayTitle, genres: ["Sci-Fi"], reason: .hiddenTitle, updatedAt: Date(timeIntervalSince1970: 10))
        settings.tasteProfile.hideTitle(mediaID: notInterested.id, title: notInterested.displayTitle, genres: ["Sci-Fi"], reason: .notInterested, updatedAt: Date(timeIntervalSince1970: 20))
        settings.tasteProfile.hideTitle(mediaID: removed.id, title: removed.displayTitle, genres: ["Sci-Fi"], reason: .removedFromRecommendations, updatedAt: Date(timeIntervalSince1970: 30))
        let settingsRepository = CoreMockSettingsRepository(settings: settings)
        let service = LocalRecommendationService(
            libraryRepository: repository,
            progressRepository: nil,
            metadataService: nil,
            settingsRepository: settingsRepository
        )

        let sections = try await service.homeRecommendations(limit: 8)
        let recommendedIDs = Set(sections.flatMap { $0.items.map(\.id) })
        let libraryIDs = Set(try await repository.items().map(\.id))

        XCTAssertTrue(recommendedIDs.contains(visible.id))
        XCTAssertFalse(recommendedIDs.contains(hidden.id))
        XCTAssertFalse(recommendedIDs.contains(notInterested.id))
        XCTAssertFalse(recommendedIDs.contains(removed.id))
        XCTAssertTrue(libraryIDs.isSuperset(of: [hidden.id, notInterested.id, removed.id]))
    }
}

private func recommendationItem(
    id: String,
    title: String,
    kind: MediaKind,
    genres: [String],
    rating: Double,
    cast: [CastMember] = []
) -> MediaItem {
    MediaItem(
        id: id,
        title: title,
        kind: kind,
        overview: "Fixture.",
        releaseYear: 2024,
        posterPath: nil,
        metadata: MediaMetadata(
            tmdbId: abs(id.hashValue % 10_000),
            title: title,
            originalTitle: title,
            overview: "Fixture.",
            year: 2024,
            genres: genres,
            rating: rating,
            cast: cast
        )
    )
}

private final class RecommendationMemoryLibraryRepository: LibraryRepositoryProtocol {
    private var storedItems: [MediaItem]
    private var storedFavorites: [MediaItem] = []
    private var storedWatchedItems: [WatchedMediaItem] = []
    private var storedRatedItems: [RatedMediaItem] = []
    private var storedLists: [UserList] = [
        UserList(id: "watchlist", name: "Watchlist", isDefault: true)
    ]

    init(storedItems: [MediaItem]) {
        self.storedItems = storedItems
    }

    func items() async throws -> [MediaItem] { storedItems }
    func add(_ item: MediaItem) async throws { upsert(item) }
    func remove(mediaID: String) async throws { storedItems.removeAll { $0.id == mediaID } }
    func favorites() async throws -> [MediaItem] { storedFavorites }
    func addFavorite(_ item: MediaItem) async throws { upsert(item); storedFavorites.append(item) }
    func removeFavorite(mediaID: String) async throws { storedFavorites.removeAll { $0.id == mediaID } }
    func watchedItems() async throws -> [WatchedMediaItem] { storedWatchedItems }
    func markWatched(_ item: MediaItem, positionSeconds: Double) async throws { upsert(item); storedWatchedItems.append(WatchedMediaItem(item: item, positionSeconds: positionSeconds)) }
    func ratedItems() async throws -> [RatedMediaItem] { storedRatedItems }
    func setRating(_ item: MediaItem, rating: Int) async throws { upsert(item); storedRatedItems.append(RatedMediaItem(item: item, rating: rating)) }
    func lists() async throws -> [UserList] { storedLists }
    func defaultList() async throws -> UserList { storedLists[0] }
    func createList(name: String) async throws -> UserList {
        try await createList(name: name, description: nil)
    }
    func createList(name: String, description: String?) async throws -> UserList {
        let list = UserList(name: name, description: description)
        storedLists.append(list)
        return list
    }
    func renameList(id: String, name: String, description: String?) async throws {}
    func deleteList(id: String) async throws {}
    func add(_ item: MediaItem, to listID: String) async throws {
        upsert(item)
        storedLists = storedLists.map { list in
            guard list.id == listID, !list.itemIDs.contains(item.id) else { return list }
            return UserList(
                id: list.id,
                name: list.name,
                description: list.description,
                itemIDs: list.itemIDs + [item.id],
                createdAt: list.createdAt,
                updatedAt: Date(),
                isDefault: list.isDefault
            )
        }
    }
    func remove(_ mediaID: String, from listID: String) async throws {}
    func items(in listID: String) async throws -> [MediaItem] {
        guard let list = storedLists.first(where: { $0.id == listID }) else { return [] }
        return storedItems.filter { list.itemIDs.contains($0.id) }
    }

    private func upsert(_ item: MediaItem) {
        storedItems.removeAll { $0.id == item.id }
        storedItems.append(item)
    }
}

private actor RecommendationMemoryProgressRepository: PlaybackProgressRepositoryProtocol {
    private var records: [PlaybackProgress]

    init(records: [PlaybackProgress]) {
        self.records = records
    }

    func saveProgress(_ progress: PlaybackProgress) async throws {
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
