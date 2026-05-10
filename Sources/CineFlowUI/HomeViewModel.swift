import CineFlowCore
import CineFlowDesignSystem
import Foundation

public enum HomeViewState: Equatable, Sendable {
    case loading
    case loaded
    case empty
    case failed(String)
}

public enum HomeSectionKind: Equatable, Sendable {
    case continueWatching
    case popularMovies
    case popularSeries
    case recentlyAdded
    case recommended
    case topQuality
}

public struct HomeFeaturedItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let metadataLine: String
    public let overview: String
    public let qualityBadge: String
    public let accentIndex: Int
}

public struct HomeSection: Identifiable, Equatable, Sendable {
    public let id: HomeSectionKind
    public let kind: HomeSectionKind
    public let title: String
    public let cardStyle: MediaCardStyle
    public let items: [CFMediaCardModel]

    public init(kind: HomeSectionKind, title: String, cardStyle: MediaCardStyle, items: [CFMediaCardModel]) {
        self.id = kind
        self.kind = kind
        self.title = title
        self.cardStyle = cardStyle
        self.items = items
    }
}

public struct HomeSeedItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let kind: SeedMediaKind
    public let year: Int
    public let rating: String
    public let runtime: String
    public let genre: String
    public let overview: String
    public let quality: String
    public let popularityRank: Int
    public let isFeatured: Bool
    public let isRecentlyAdded: Bool
    public let isRecommended: Bool
    public let progress: Double?

    public init(
        id: String,
        title: String,
        kind: SeedMediaKind,
        year: Int,
        rating: String,
        runtime: String,
        genre: String,
        overview: String,
        quality: String,
        popularityRank: Int,
        isFeatured: Bool = false,
        isRecentlyAdded: Bool = false,
        isRecommended: Bool = false,
        progress: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.year = year
        self.rating = rating
        self.runtime = runtime
        self.genre = genre
        self.overview = overview
        self.quality = quality
        self.popularityRank = popularityRank
        self.isFeatured = isFeatured
        self.isRecentlyAdded = isRecentlyAdded
        self.isRecommended = isRecommended
        self.progress = progress.map { min(max($0, 0), 1) }
    }
}

public enum SeedMediaKind: Equatable, Sendable {
    case movie
    case series
}

public enum HomeSeedError: LocalizedError, Equatable {
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "Seed data is unavailable."
        }
    }
}

public enum HomeSeedLibrary {
    public static let developmentItems: [HomeSeedItem] = [
        HomeSeedItem(
            id: "tmdb:movie:693134",
            title: "Dune: Part Two",
            kind: .movie,
            year: 2024,
            rating: "PG-13",
            runtime: "2h 46m",
            genre: "Sci-Fi",
            overview: "Paul Atreides unites with Chani and the Fremen while choosing between revenge, prophecy, and the future of Arrakis.",
            quality: "2160p HDR",
            popularityRank: 1,
            isFeatured: true,
            isRecentlyAdded: true,
            isRecommended: true,
            progress: 0.42
        ),
        HomeSeedItem(
            id: "tmdb:tv:1399",
            title: "Game of Thrones",
            kind: .series,
            year: 2011,
            rating: "TV-MA",
            runtime: "8 seasons",
            genre: "Drama",
            overview: "Noble families fight for control while an ancient threat rises beyond the Wall.",
            quality: "1080p",
            popularityRank: 2,
            isFeatured: true,
            isRecommended: true,
            progress: 0.68
        ),
        HomeSeedItem(
            id: "tmdb:movie:155",
            title: "The Dark Knight",
            kind: .movie,
            year: 2008,
            rating: "PG-13",
            runtime: "2h 32m",
            genre: "Action",
            overview: "Batman faces a criminal mastermind who wants to pull Gotham into chaos.",
            quality: "2160p",
            popularityRank: 3,
            isFeatured: true,
            isRecentlyAdded: true,
            progress: 0.23
        ),
        HomeSeedItem(
            id: "tmdb:tv:66732",
            title: "Stranger Things",
            kind: .series,
            year: 2016,
            rating: "TV-14",
            runtime: "4 seasons",
            genre: "Mystery",
            overview: "A small town uncovers secret experiments, missing friends, and a hostile parallel dimension.",
            quality: "2160p",
            popularityRank: 4,
            isFeatured: true,
            isRecommended: true
        ),
        HomeSeedItem(
            id: "tmdb:movie:603",
            title: "The Matrix",
            kind: .movie,
            year: 1999,
            rating: "R",
            runtime: "2h 16m",
            genre: "Sci-Fi",
            overview: "A hacker discovers that reality is a simulated world controlled by machines.",
            quality: "2160p",
            popularityRank: 5,
            isRecommended: true
        ),
        HomeSeedItem(
            id: "tmdb:movie:329865",
            title: "Arrival",
            kind: .movie,
            year: 2016,
            rating: "PG-13",
            runtime: "1h 56m",
            genre: "Drama",
            overview: "A linguist races to understand visitors from another world before global fear turns into war.",
            quality: "2160p HDR",
            popularityRank: 6,
            isRecentlyAdded: true,
            isRecommended: true
        ),
        HomeSeedItem(
            id: "tmdb:tv:76479",
            title: "The Boys",
            kind: .series,
            year: 2019,
            rating: "TV-MA",
            runtime: "4 seasons",
            genre: "Action",
            overview: "Vigilantes expose a corporation that markets corrupt superheroes as global celebrities.",
            quality: "1080p",
            popularityRank: 7,
            isRecentlyAdded: true
        ),
        HomeSeedItem(
            id: "tmdb:movie:27205",
            title: "Inception",
            kind: .movie,
            year: 2010,
            rating: "PG-13",
            runtime: "2h 28m",
            genre: "Sci-Fi",
            overview: "A thief who steals secrets through dreams accepts a final job that asks him to plant an idea.",
            quality: "2160p",
            popularityRank: 8,
            isRecommended: true
        ),
        HomeSeedItem(
            id: "tmdb:tv:94997",
            title: "House of the Dragon",
            kind: .series,
            year: 2022,
            rating: "TV-MA",
            runtime: "2 seasons",
            genre: "Fantasy",
            overview: "House Targaryen descends toward civil war as rival heirs divide the realm.",
            quality: "2160p HDR",
            popularityRank: 9,
            isRecentlyAdded: true
        ),
        HomeSeedItem(
            id: "tmdb:movie:157336",
            title: "Interstellar",
            kind: .movie,
            year: 2014,
            rating: "PG-13",
            runtime: "2h 49m",
            genre: "Adventure",
            overview: "Explorers cross a wormhole to find a new home for humanity.",
            quality: "2160p HDR",
            popularityRank: 10,
            isRecommended: true
        ),
        HomeSeedItem(
            id: "tmdb:tv:208920",
            title: "Dune: Prophecy",
            kind: .series,
            year: 2024,
            rating: "TV-MA",
            runtime: "1 season",
            genre: "Sci-Fi",
            overview: "Sisters of the Bene Gesserit shape political power in the years before Paul Atreides.",
            quality: "2160p HDR",
            popularityRank: 11,
            isRecentlyAdded: true
        )
    ]
}

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public private(set) var state: HomeViewState = .loading
    @Published public private(set) var featuredItems: [HomeFeaturedItem] = []
    @Published public private(set) var selectedFeaturedIndex = 0
    @Published public private(set) var sections: [HomeSection] = []

    private let seedProvider: () throws -> [HomeSeedItem]
    private let progressRepository: (any PlaybackProgressRepositoryProtocol)?

    public init(
        seedItems: [HomeSeedItem] = HomeSeedLibrary.developmentItems,
        progressRepository: (any PlaybackProgressRepositoryProtocol)? = nil
    ) {
        self.seedProvider = { seedItems }
        self.progressRepository = progressRepository
    }

    public init(
        seedProvider: @escaping () throws -> [HomeSeedItem],
        progressRepository: (any PlaybackProgressRepositoryProtocol)? = nil
    ) {
        self.seedProvider = seedProvider
        self.progressRepository = progressRepository
    }

    public var selectedFeaturedItem: HomeFeaturedItem? {
        guard featuredItems.indices.contains(selectedFeaturedIndex) else { return featuredItems.first }
        return featuredItems[selectedFeaturedIndex]
    }

    public func load() async {
        state = .loading

        do {
            let items = try seedProvider()
            guard !items.isEmpty else {
                featuredItems = []
                selectedFeaturedIndex = 0
                sections = []
                state = .empty
                return
            }

            featuredItems = Array(items.filter(\.isFeatured).prefix(4)).enumerated().map { index, item in
                HomeFeaturedItem(
                    id: item.id,
                    title: item.title,
                    metadataLine: metadataLine(for: item),
                    overview: item.overview,
                    qualityBadge: item.quality,
                    accentIndex: index
                )
            }
            selectedFeaturedIndex = 0
            sections = try await buildSections(from: items)
            state = .loaded
        } catch {
            featuredItems = []
            selectedFeaturedIndex = 0
            sections = []
            state = .failed(CineFlowError.from(error, fallbackCategory: .metadata).userMessage)
        }
    }

    public func selectFeaturedItem(id: String) {
        guard let index = featuredItems.firstIndex(where: { $0.id == id }) else { return }
        selectedFeaturedIndex = index
    }

    private func buildSections(from items: [HomeSeedItem]) async throws -> [HomeSection] {
        let continueItems: [CFMediaCardModel]
        if let progressRepository {
            continueItems = try await progressRepository.continueWatching(includeCompleted: false).map(card(from:))
        } else {
            continueItems = cards(from: items.filter { $0.progress != nil }, limit: 6)
        }

        return [
            HomeSection(
                kind: .continueWatching,
                title: "Continue Watching",
                cardStyle: .landscape,
                items: Array(continueItems.prefix(6))
            ),
            HomeSection(
                kind: .popularMovies,
                title: "Popular - Movies",
                cardStyle: .poster,
                items: cards(from: ranked(items, kind: .movie), limit: 8)
            ),
            HomeSection(
                kind: .popularSeries,
                title: "Popular - Series",
                cardStyle: .poster,
                items: cards(from: ranked(items, kind: .series), limit: 8)
            ),
            HomeSection(
                kind: .recentlyAdded,
                title: "Recently Added to Library",
                cardStyle: .poster,
                items: cards(from: items.filter(\.isRecentlyAdded), limit: 8)
            ),
            HomeSection(
                kind: .recommended,
                title: "Recommended",
                cardStyle: .poster,
                items: cards(from: items.filter(\.isRecommended), limit: 8)
            ),
            HomeSection(
                kind: .topQuality,
                title: "Top Quality",
                cardStyle: .poster,
                items: cards(from: items.filter { $0.quality.contains("2160p") }, limit: 8)
            )
        ]
    }

    private func ranked(_ items: [HomeSeedItem], kind: SeedMediaKind) -> [HomeSeedItem] {
        items
            .filter { $0.kind == kind }
            .sorted { $0.popularityRank < $1.popularityRank }
    }

    private func cards(from items: [HomeSeedItem], limit: Int) -> [CFMediaCardModel] {
        Array(items.prefix(limit)).enumerated().map { index, item in
            CFMediaCardModel(
                id: item.id,
                title: item.title,
                metadata: metadataLine(for: item),
                badge: item.quality,
                progress: item.progress,
                accentIndex: index
            )
        }
    }

    private func card(from progress: PlaybackProgress) -> CFMediaCardModel {
        CFMediaCardModel(
            id: progress.episodeID ?? progress.mediaID,
            title: progress.episodeID ?? progress.mediaID,
            metadata: "\(Int(progress.progressPercent.rounded()))% watched",
            badge: progress.releaseID,
            progress: progress.progressPercent / 100,
            accentIndex: abs((progress.episodeID ?? progress.mediaID).hashValue)
        )
    }

    private func metadataLine(for item: HomeSeedItem) -> String {
        "\(item.year) · \(item.rating) · \(item.runtime) · \(item.genre)"
    }
}
