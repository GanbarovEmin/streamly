import CineFlowCore
import CineFlowDesignSystem
import Foundation

public enum HomeViewState: Equatable, Sendable {
    case loading
    case loaded
    case empty
    case failed(String)
}

public enum HomeSectionKind: String, CaseIterable, Equatable, Sendable {
    case newEpisodes
    case upcomingCalendar
    case collections
    case moodDiscovery
    case watchNext
    case continueWatching
    case popularMovies
    case popularSeries
    case trendingMovies
    case trendingSeries
    case recentlyAdded
    case recommended
    case moreLikeThis
    case fromFavoriteGenres
    case continueSeries
    case hiddenGems
    case popularInFavoriteGenres
    case notFinishedYet
    case topQuality
    case ultraHDR
    case favoriteGenres
    case unfinishedMovies
    case forgottenInLibrary
    case recommendedTonight
}

public extension HomeSectionKind {
    static let defaultHomeOrder: [HomeSectionKind] = [
        .continueWatching,
        .watchNext,
        .newEpisodes,
        .recommendedTonight,
        .recommended,
        .moreLikeThis,
        .fromFavoriteGenres,
        .continueSeries,
        .hiddenGems,
        .popularInFavoriteGenres,
        .notFinishedYet,
        .recentlyAdded,
        .trendingMovies,
        .trendingSeries,
        .topQuality,
        .ultraHDR,
        .favoriteGenres,
        .unfinishedMovies,
        .forgottenInLibrary,
        .collections,
        .moodDiscovery,
        .upcomingCalendar
    ]

    var personalizationID: String {
        rawValue
    }

    var defaultOrderIndex: Int {
        Self.defaultHomeOrder.firstIndex(of: self) ?? Int.max
    }
}

public struct HomeFeaturedItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let metadataLine: String
    public let overview: String
    public let qualityBadge: String
    public let accentIndex: Int
    public let backdropURL: URL?
}

public struct HomeSection: Identifiable, Equatable, Sendable {
    public let id: HomeSectionKind
    public let kind: HomeSectionKind
    public let personalizationID: String
    public let title: String
    public let cardStyle: MediaCardStyle
    public let items: [CFMediaCardModel]

    public init(kind: HomeSectionKind, title: String, cardStyle: MediaCardStyle, items: [CFMediaCardModel]) {
        self.id = kind
        self.kind = kind
        self.personalizationID = kind.personalizationID
        self.title = title
        self.cardStyle = cardStyle
        self.items = items
    }
}

public struct HomePersonalizationUndo: Equatable, Sendable {
    public let title: String
    fileprivate let previousTasteProfile: TasteProfileSettings
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
    public let artworkURL: URL?
    public let backdropURL: URL?

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
        progress: Double? = nil,
        artworkURL: URL? = nil,
        backdropURL: URL? = nil
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
        self.artworkURL = artworkURL
        self.backdropURL = backdropURL
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
    @Published public private(set) var episodeNotificationDigest: SeriesTrackingDigest = .empty
    @Published public private(set) var moodFilters: [MoodDiscoveryFilter] = MoodDiscoveryFilter.homeFilters
    @Published public private(set) var selectedMoodFilter: MoodDiscoveryFilter = .lightEvening
    @Published public private(set) var moodPick: MoodDiscoveryItem?
    @Published public private(set) var homePreferences = HomePreferences()
    @Published public private(set) var personalizationUndo: HomePersonalizationUndo?

    private let seedProvider: () async throws -> [HomeSeedItem]
    private let settingsRepository: (any SettingsRepositoryProtocol)?
    private let recommendationService: (any RecommendationServiceProtocol)?
    private let progressRepository: (any PlaybackProgressRepositoryProtocol)?
    private let libraryRepository: (any LibraryRepositoryProtocol)?
    private let watchNextProvider: (any WatchNextProviderProtocol)?
    private let newEpisodesProvider: (any NewEpisodesProviderProtocol)?
    private let upcomingCalendarProvider: (any UpcomingCalendarProviderProtocol)?
    private let moodEngine = MoodDiscoveryEngine()
    private var lastMoodCandidates: [MoodDiscoveryCandidate] = []
    private var lastMoodTasteProfile = MoodDiscoveryTasteProfile()
    private var allLoadedSections: [HomeSection] = []
    private var personalizationLookup: [String: HomePersonalizationSnapshot] = [:]
    private var actionMediaLookup: [String: MediaItem] = [:]

    public init(
        seedItems: [HomeSeedItem] = HomeSeedLibrary.developmentItems,
        settingsRepository: (any SettingsRepositoryProtocol)? = nil,
        recommendationService: (any RecommendationServiceProtocol)? = nil,
        progressRepository: (any PlaybackProgressRepositoryProtocol)? = nil,
        libraryRepository: (any LibraryRepositoryProtocol)? = nil,
        watchNextProvider: (any WatchNextProviderProtocol)? = nil,
        newEpisodesProvider: (any NewEpisodesProviderProtocol)? = nil,
        upcomingCalendarProvider: (any UpcomingCalendarProviderProtocol)? = nil
    ) {
        self.seedProvider = { seedItems }
        self.settingsRepository = settingsRepository
        self.recommendationService = recommendationService
        self.progressRepository = progressRepository
        self.libraryRepository = libraryRepository
        self.watchNextProvider = watchNextProvider
        self.newEpisodesProvider = newEpisodesProvider
        self.upcomingCalendarProvider = upcomingCalendarProvider
    }

    public init(
        seedProvider: @escaping () async throws -> [HomeSeedItem],
        settingsRepository: (any SettingsRepositoryProtocol)? = nil,
        recommendationService: (any RecommendationServiceProtocol)? = nil,
        progressRepository: (any PlaybackProgressRepositoryProtocol)? = nil,
        libraryRepository: (any LibraryRepositoryProtocol)? = nil,
        watchNextProvider: (any WatchNextProviderProtocol)? = nil,
        newEpisodesProvider: (any NewEpisodesProviderProtocol)? = nil,
        upcomingCalendarProvider: (any UpcomingCalendarProviderProtocol)? = nil
    ) {
        self.seedProvider = seedProvider
        self.settingsRepository = settingsRepository
        self.recommendationService = recommendationService
        self.progressRepository = progressRepository
        self.libraryRepository = libraryRepository
        self.watchNextProvider = watchNextProvider
        self.newEpisodesProvider = newEpisodesProvider
        self.upcomingCalendarProvider = upcomingCalendarProvider
    }

    public convenience init(
        seedProvider: @escaping () throws -> [HomeSeedItem],
        settingsRepository: (any SettingsRepositoryProtocol)? = nil,
        recommendationService: (any RecommendationServiceProtocol)? = nil,
        progressRepository: (any PlaybackProgressRepositoryProtocol)? = nil,
        libraryRepository: (any LibraryRepositoryProtocol)? = nil,
        watchNextProvider: (any WatchNextProviderProtocol)? = nil,
        newEpisodesProvider: (any NewEpisodesProviderProtocol)? = nil,
        upcomingCalendarProvider: (any UpcomingCalendarProviderProtocol)? = nil
    ) {
        let asyncSeedProvider: () async throws -> [HomeSeedItem] = {
            try seedProvider()
        }
        self.init(
            seedProvider: asyncSeedProvider,
            settingsRepository: settingsRepository,
            recommendationService: recommendationService,
            progressRepository: progressRepository,
            libraryRepository: libraryRepository,
            watchNextProvider: watchNextProvider,
            newEpisodesProvider: newEpisodesProvider,
            upcomingCalendarProvider: upcomingCalendarProvider
        )
    }

    public convenience init(
        metadataService: any MetadataServiceProtocol,
        settingsRepository: (any SettingsRepositoryProtocol)? = nil,
        recommendationService: (any RecommendationServiceProtocol)? = nil,
        progressRepository: (any PlaybackProgressRepositoryProtocol)? = nil,
        libraryRepository: (any LibraryRepositoryProtocol)? = nil,
        watchNextProvider: (any WatchNextProviderProtocol)? = nil,
        newEpisodesProvider: (any NewEpisodesProviderProtocol)? = nil,
        upcomingCalendarProvider: (any UpcomingCalendarProviderProtocol)? = nil
    ) {
        self.init(
            seedProvider: {
                try await TMDBHomeContentProvider(metadataService: metadataService).loadHomeItems()
            },
            settingsRepository: settingsRepository,
            recommendationService: recommendationService,
            progressRepository: progressRepository,
            libraryRepository: libraryRepository,
            watchNextProvider: watchNextProvider ?? SeriesDetailWatchNextProvider(
                provider: TMDBSeriesDetailProvider(metadataService: metadataService)
            ),
            newEpisodesProvider: newEpisodesProvider,
            upcomingCalendarProvider: upcomingCalendarProvider
        )
    }

    public var selectedFeaturedItem: HomeFeaturedItem? {
        guard featuredItems.indices.contains(selectedFeaturedIndex) else { return featuredItems.first }
        return featuredItems[selectedFeaturedIndex]
    }

    public var prefetchArtworkURLs: [URL] {
        Array(sections.lazy.flatMap { section in
            section.items.compactMap(\.artworkURL)
        }.prefix(24))
    }

    public var artworkPrefetchKey: String {
        prefetchArtworkURLs.map(\.absoluteString).joined(separator: "|")
    }

    public func load() async {
        state = .loading

        do {
            let appSettings = await settingsRepository?.appSettings ?? AppSettings()
            let preferences = appSettings.home
            let localRecommendationsEnabled = appSettings.recommendations.localRecommendationsEnabled
            let hiddenMediaIDs = appSettings.tasteProfile.hiddenMediaIDs
            homePreferences = preferences
            let items = try await seedProvider()
            guard !items.isEmpty else {
                featuredItems = []
                selectedFeaturedIndex = 0
                sections = []
                allLoadedSections = []
                episodeNotificationDigest = .empty
                moodPick = nil
                lastMoodCandidates = []
                lastMoodTasteProfile = MoodDiscoveryTasteProfile()
                actionMediaLookup = [:]
                state = .empty
                return
            }

            let progressRecords: [PlaybackProgress]
            let allProgressRecords: [PlaybackProgress]
            let libraryItems: [MediaItem]
            let favoriteItems: [MediaItem]
            let watchedItems: [WatchedMediaItem]
            let ratedItems: [RatedMediaItem]
            if let progressRepository {
                progressRecords = try await progressRepository.continueWatching(includeCompleted: false)
                allProgressRecords = try await progressRepository.continueWatching(includeCompleted: true)
            } else {
                progressRecords = []
                allProgressRecords = []
            }
            libraryItems = (try? await libraryRepository?.items()) ?? []
            favoriteItems = (try? await libraryRepository?.favorites()) ?? []
            watchedItems = (try? await libraryRepository?.watchedItems()) ?? []
            ratedItems = (try? await libraryRepository?.ratedItems()) ?? []
            personalizationLookup = Self.personalizationLookup(seedItems: items, libraryItems: libraryItems)
            let visibleItems = items.filter { !hiddenMediaIDs.contains($0.id) }
            let visibleProgressRecords = progressRecords.filter { !hiddenMediaIDs.contains($0.mediaID) }
            let visibleAllProgressRecords = allProgressRecords.filter { !hiddenMediaIDs.contains($0.mediaID) }
            let visibleLibraryItems = libraryItems.filter { !hiddenMediaIDs.contains($0.id) }
            let visibleFavoriteItems = favoriteItems.filter { !hiddenMediaIDs.contains($0.id) }
            let visibleWatchedItems = watchedItems.filter { !hiddenMediaIDs.contains($0.item.id) }
            let visibleRatedItems = ratedItems.filter { !hiddenMediaIDs.contains($0.item.id) }
            let watchNextItems = await watchNextProvider?.watchNextItems(progressRecords: visibleAllProgressRecords) ?? []
            let newEpisodes = await newEpisodesProvider?.newEpisodes() ?? []
            let upcomingItems = await upcomingCalendarProvider?.upcomingItems() ?? []
            let recommendationSections = localRecommendationsEnabled
                ? Self.filterRecommendationSections((try? await recommendationService?.homeRecommendations(limit: 8)) ?? [], hiddenMediaIDs: hiddenMediaIDs)
                : []
            actionMediaLookup = Self.mediaActionLookup(
                seedItems: visibleItems,
                mediaItems: visibleLibraryItems + recommendationSections.flatMap(\.items)
            )
            episodeNotificationDigest = await newEpisodesProvider?.notificationDigest(for: newEpisodes) ?? .empty
            let moodCandidates = Self.applyTasteProfile(appSettings.tasteProfile, to: MoodDiscoveryCandidateBuilder.candidates(seedItems: visibleItems, libraryItems: visibleLibraryItems))
            let moodTasteProfile = MoodDiscoveryTasteProfile.from(
                libraryItems: visibleLibraryItems,
                progressRecords: visibleAllProgressRecords
            )
            let moodItems = moodEngine.recommendations(
                from: moodCandidates,
                filter: selectedMoodFilter,
                tasteProfile: moodTasteProfile
            )
            let moodPick = moodEngine.pickForMe(from: moodCandidates, tasteProfile: moodTasteProfile)
            let collections = CollectionDiscoveryBuilder.automaticCollections(
                candidates: visibleItems.map(CollectionDiscoveryBuilder.mediaItem(from:)) + visibleLibraryItems,
                libraryIDs: Set(visibleLibraryItems.map(\.id)),
                watchlistIDs: []
            )
            lastMoodCandidates = moodCandidates
            lastMoodTasteProfile = moodTasteProfile
            self.moodPick = moodPick

            let usesProgressRepository = progressRepository != nil
            let content = await Task.detached(priority: .userInitiated) {
                HomeContentBuilder.build(
                    items: visibleItems,
                    progressRecords: visibleProgressRecords,
                    watchNextItems: watchNextItems,
                    newEpisodes: newEpisodes,
                    upcomingItems: upcomingItems,
                    collections: collections,
                    moodItems: moodItems,
                    recommendationSections: recommendationSections,
                    libraryItems: visibleLibraryItems,
                    favoriteItems: visibleFavoriteItems,
                    watchedItems: visibleWatchedItems,
                    ratedItems: visibleRatedItems,
                    usesProgressRepository: usesProgressRepository,
                    localRecommendationsEnabled: localRecommendationsEnabled
                )
            }.value
            featuredItems = content.featuredItems
            selectedFeaturedIndex = 0
            allLoadedSections = content.sections
            sections = Self.applyHomePreferences(preferences, to: content.sections)
            state = .loaded
        } catch {
            featuredItems = []
            selectedFeaturedIndex = 0
            sections = []
            allLoadedSections = []
            episodeNotificationDigest = .empty
            moodPick = nil
            lastMoodCandidates = []
            lastMoodTasteProfile = MoodDiscoveryTasteProfile()
            actionMediaLookup = [:]
            state = .failed(CineFlowError.from(error, fallbackCategory: .metadata).userMessage)
        }
    }

    public func refreshHomePreferences() async {
        guard let settingsRepository else { return }
        let preferences = await settingsRepository.appSettings.home
        guard preferences != homePreferences else { return }
        homePreferences = preferences
        sections = Self.applyHomePreferences(preferences, to: allLoadedSections)
    }

    private static func applyHomePreferences(_ preferences: HomePreferences, to sections: [HomeSection]) -> [HomeSection] {
        sections
            .filter { preferences.isSectionEnabled($0.personalizationID) }
            .sorted { lhs, rhs in
                let lhsOrder = preferences.order(for: lhs.personalizationID)
                let rhsOrder = preferences.order(for: rhs.personalizationID)
                if lhsOrder == rhsOrder {
                    return lhs.kind.defaultOrderIndex < rhs.kind.defaultOrderIndex
                }
                return lhsOrder < rhsOrder
            }
    }

    private static func applyTasteProfile(_ tasteProfile: TasteProfileSettings, to candidates: [MoodDiscoveryCandidate]) -> [MoodDiscoveryCandidate] {
        candidates.filter { candidate in
            guard !tasteProfile.isHidden(mediaID: candidate.id) else { return false }
            return !candidate.genres.contains { tasteProfile.preference(forGenre: $0) == .hidden }
        }
    }

    private static func filterRecommendationSections(
        _ sections: [RecommendationSection],
        hiddenMediaIDs: Set<String>
    ) -> [RecommendationSection] {
        sections.compactMap { section in
            let visibleItems = section.items.filter { !hiddenMediaIDs.contains($0.id) }
            guard !visibleItems.isEmpty else { return nil }
            return RecommendationSection(
                kind: section.kind,
                title: section.title,
                items: visibleItems,
                explanationsByMediaID: section.explanationsByMediaID
            )
        }
    }

    private static func personalizationLookup(
        seedItems: [HomeSeedItem],
        libraryItems: [MediaItem]
    ) -> [String: HomePersonalizationSnapshot] {
        var snapshots: [String: HomePersonalizationSnapshot] = [:]
        for item in seedItems {
            snapshots[item.id] = HomePersonalizationSnapshot(id: item.id, title: item.title, genres: [item.genre])
        }
        for item in libraryItems {
            snapshots[item.id] = HomePersonalizationSnapshot(id: item.id, title: item.displayTitle, genres: item.metadata?.genres ?? [])
        }
        return snapshots
    }

    private static func mediaActionLookup(seedItems: [HomeSeedItem], mediaItems: [MediaItem]) -> [String: MediaItem] {
        var lookup: [String: MediaItem] = [:]
        for item in seedItems {
            lookup[item.id] = CollectionDiscoveryBuilder.mediaItem(from: item)
        }
        for item in mediaItems {
            lookup[item.id] = item
        }
        return lookup
    }

    public func selectFeaturedItem(id: String) {
        guard let index = featuredItems.firstIndex(where: { $0.id == id }) else { return }
        selectedFeaturedIndex = index
    }

    public func addUpcomingToWatchlist(itemID: String) async {
        guard let upcomingCalendarProvider, let libraryRepository else { return }
        try? await upcomingCalendarProvider.addToWatchlist(itemID: itemID, libraryRepository: libraryRepository)
    }

    public func addToLibrary(itemID: String) async {
        guard let libraryRepository, let item = actionMediaLookup[itemID] else { return }
        try? await libraryRepository.add(item)
    }

    public func addToWatchlist(itemID: String) async {
        guard let libraryRepository, let item = actionMediaLookup[itemID] else { return }
        guard let list = try? await libraryRepository.defaultList() else { return }
        try? await libraryRepository.add(item, to: list.id)
    }

    public func hideTitle(itemID: String) async {
        await applyHiddenSignal(itemID: itemID, reason: .hiddenTitle, undoTitle: "Undo Hide this title")
    }

    public func markNotInterested(itemID: String) async {
        await applyHiddenSignal(itemID: itemID, reason: .notInterested, undoTitle: "Undo Not interested")
    }

    public func removeFromRecommendations(itemID: String) async {
        await applyHiddenSignal(itemID: itemID, reason: .removedFromRecommendations, undoTitle: "Undo Remove from recommendations")
    }

    public func showLessOfPrimaryGenre(itemID: String) async {
        await updatePrimaryGenrePreference(itemID: itemID, preference: .less, undoTitle: "Undo Show less")
    }

    public func showMoreOfPrimaryGenre(itemID: String) async {
        await updatePrimaryGenrePreference(itemID: itemID, preference: .more, undoTitle: "Undo Show more")
    }

    public func undoLastPersonalizationAction() async {
        guard let settingsRepository, let undo = personalizationUndo else { return }
        var settings = await settingsRepository.appSettings
        settings.tasteProfile = undo.previousTasteProfile
        await settingsRepository.setAppSettings(settings)
        personalizationUndo = nil
        await load()
    }

    private func applyHiddenSignal(
        itemID: String,
        reason: HiddenRecommendationReason,
        undoTitle: String
    ) async {
        guard let settingsRepository else { return }
        let snapshot = personalizationLookup[itemID] ?? HomePersonalizationSnapshot(id: itemID, title: itemID, genres: [])
        var settings = await settingsRepository.appSettings
        personalizationUndo = HomePersonalizationUndo(title: undoTitle, previousTasteProfile: settings.tasteProfile)
        settings.tasteProfile.hideTitle(
            mediaID: snapshot.id,
            title: snapshot.title,
            genres: snapshot.genres,
            reason: reason
        )
        await settingsRepository.setAppSettings(settings)
        await load()
    }

    private func updatePrimaryGenrePreference(
        itemID: String,
        preference: TastePreferenceLevel,
        undoTitle: String
    ) async {
        guard let settingsRepository, let genre = personalizationLookup[itemID]?.genres.first else { return }
        var settings = await settingsRepository.appSettings
        personalizationUndo = HomePersonalizationUndo(title: undoTitle, previousTasteProfile: settings.tasteProfile)
        settings.tasteProfile.setGenre(genre, preference: preference)
        await settingsRepository.setAppSettings(settings)
        await load()
    }

    public func selectMoodFilter(_ filter: MoodDiscoveryFilter) {
        selectedMoodFilter = filter
        let moodItems = moodEngine.recommendations(
            from: lastMoodCandidates,
            filter: filter,
            tasteProfile: lastMoodTasteProfile
        )
        let moodSection = HomeContentBuilder.section(from: moodItems)
        if let index = sections.firstIndex(where: { $0.kind == .moodDiscovery }) {
            sections[index] = moodSection
        } else if !moodItems.isEmpty {
            sections.insert(moodSection, at: min(sections.count, 2))
        }
    }
}

private struct HomePersonalizationSnapshot: Equatable, Sendable {
    let id: String
    let title: String
    let genres: [String]
}

private struct HomePreparedContent: Sendable {
    let featuredItems: [HomeFeaturedItem]
    let sections: [HomeSection]
}

private enum HomeContentBuilder {
    static func build(
        items: [HomeSeedItem],
        progressRecords: [PlaybackProgress],
        watchNextItems: [WatchNextEpisode],
        newEpisodes: [NewSeriesEpisode],
        upcomingItems: [UpcomingCalendarItem],
        collections: [MediaCollection],
        moodItems: [MoodDiscoveryItem],
        recommendationSections: [RecommendationSection],
        libraryItems: [MediaItem],
        favoriteItems: [MediaItem],
        watchedItems: [WatchedMediaItem],
        ratedItems: [RatedMediaItem],
        usesProgressRepository: Bool,
        localRecommendationsEnabled: Bool
    ) -> HomePreparedContent {
        let featuredItems = Array(items.filter(\.isFeatured).prefix(4)).enumerated().map { index, item in
            HomeFeaturedItem(
                id: item.id,
                title: item.title,
                metadataLine: metadataLine(for: item),
                overview: item.overview,
                qualityBadge: item.quality,
                accentIndex: index,
                backdropURL: item.backdropURL
            )
        }

        let mediaByID = mediaLookup(from: libraryItems)
        let seedByID = seedLookup(from: items)
        let seedByTitle = seedTitleLookup(from: items)

        let continueItems: [CFMediaCardModel]
        if usesProgressRepository {
            continueItems = progressRecords.map { progress in
                let mediaItem = mediaByID[progress.mediaID]
                let seedItem = seedItem(
                    for: progress.mediaID,
                    title: mediaItem?.displayTitle,
                    seedByID: seedByID,
                    seedByTitle: seedByTitle
                )
                return card(from: progress, mediaItem: mediaItem, seedItem: seedItem)
            }
        } else {
            continueItems = cards(from: items.filter { $0.progress != nil }, limit: 6)
        }

        let watchNextCards: [CFMediaCardModel]
        if usesProgressRepository {
            watchNextCards = watchNextItems.map { item in
                card(
                    from: item,
                    mediaItem: mediaByID[item.seriesID],
                    seedItem: seedItem(
                        for: item.seriesID,
                        title: item.seriesTitle,
                        seedByID: seedByID,
                        seedByTitle: seedByTitle
                    )
                )
            }
        } else {
            watchNextCards = cards(from: items.filter { $0.kind == .series && $0.progress != nil }, limit: 6)
        }
        let newEpisodeCards = newEpisodes.map { item in
            card(
                from: item,
                mediaItem: mediaByID[item.seriesID],
                seedItem: seedItem(
                    for: item.seriesID,
                    title: item.seriesTitle,
                    seedByID: seedByID,
                    seedByTitle: seedByTitle
                )
            )
        }
        let upcomingCards = upcomingItems.map(card(from:))
        let personalProgressRecords = allPersonalProgressRecords(
            active: progressRecords,
            usesProgressRepository: usesProgressRepository,
            seedItems: items
        )
        let recommendedTonightCards = localRecommendationsEnabled ? cards(from: moodItems, titlePrefix: nil) : []
        let becauseYouWatchedCards = localRecommendationsEnabled ? becauseYouWatchedCards(from: items, progressRecords: progressRecords, limit: 8) : []
        let recentlyAddedCards = cards(from: items.filter(\.isRecentlyAdded), limit: 8)
        let trendingMovieCards = cards(from: ranked(items, kind: .movie), limit: 8)
        let trendingSeriesCards = cards(from: ranked(items, kind: .series), limit: 8)
        let bestQualityCards = cards(from: bestQualityItems(from: items), limit: 8)
        let ultraHDRCards = cards(from: ultraHDRItems(from: items), limit: 8)
        let favoriteGenreCards = localRecommendationsEnabled ? favoriteGenreCards(
            from: items,
            libraryItems: libraryItems,
            favoriteItems: favoriteItems,
            watchedItems: watchedItems,
            ratedItems: ratedItems,
            progressRecords: personalProgressRecords,
            limit: 8
        ) : []
        let unfinishedMovieCards = unfinishedMovieCards(
            from: items,
            libraryItems: libraryItems,
            progressRecords: personalProgressRecords,
            limit: 8
        )
        let forgottenLibraryCards = forgottenLibraryCards(
            from: libraryItems,
            progressRecords: personalProgressRecords,
            favoriteItems: favoriteItems,
            watchedItems: watchedItems,
            ratedItems: ratedItems,
            limit: 8
        )

        var sections: [HomeSection] = []
        let collectionCards = cards(from: collections)
        appendSection(&sections, kind: .continueWatching, title: "Continue Watching", cardStyle: .landscape, items: Array(continueItems.prefix(6)))
        appendSection(&sections, kind: .watchNext, title: "Watch Next", cardStyle: .landscape, items: Array(watchNextCards.prefix(6)))
        appendSection(&sections, kind: .newEpisodes, title: "New Episodes", cardStyle: .landscape, items: Array(newEpisodeCards.prefix(6)))
        appendSection(&sections, kind: .recommendedTonight, title: "Recommended Tonight", cardStyle: .landscape, items: Array(recommendedTonightCards.prefix(6)))
        appendRecommendationSections(recommendationSections, to: &sections)
        if !recommendationSections.contains(where: { $0.kind == .becauseYouWatched }) {
            appendSection(&sections, kind: .recommended, title: "Because You Watched", cardStyle: .poster, items: becauseYouWatchedCards)
        }
        appendSection(&sections, kind: .recentlyAdded, title: "Recently Added", cardStyle: .poster, items: recentlyAddedCards)
        appendSection(&sections, kind: .trendingMovies, title: "Trending Movies", cardStyle: .poster, items: trendingMovieCards)
        appendSection(&sections, kind: .trendingSeries, title: "Trending Series", cardStyle: .poster, items: trendingSeriesCards)
        appendSection(&sections, kind: .topQuality, title: "Best Quality Available", cardStyle: .poster, items: bestQualityCards)
        appendSection(&sections, kind: .ultraHDR, title: "4K/HDR Available", cardStyle: .poster, items: ultraHDRCards)
        if !recommendationSections.contains(where: { $0.kind == .fromFavoriteGenres }) {
            appendSection(&sections, kind: .favoriteGenres, title: "Favorite Genres", cardStyle: .poster, items: favoriteGenreCards)
        }
        appendSection(&sections, kind: .unfinishedMovies, title: "Unfinished Movies", cardStyle: .landscape, items: unfinishedMovieCards)
        appendSection(&sections, kind: .forgottenInLibrary, title: "Forgotten in Library", cardStyle: .poster, items: forgottenLibraryCards)
        appendSection(&sections, kind: .collections, title: "Collections", cardStyle: .landscape, items: Array(collectionCards.prefix(8)))
        if !moodItems.isEmpty {
            sections.append(section(from: moodItems))
        }
        appendSection(&sections, kind: .upcomingCalendar, title: "Upcoming Calendar", cardStyle: .landscape, items: Array(upcomingCards.prefix(8)))

        return HomePreparedContent(featuredItems: featuredItems, sections: sections)
    }

    private static func appendRecommendationSections(
        _ recommendationSections: [RecommendationSection],
        to sections: inout [HomeSection]
    ) {
        for recommendationSection in recommendationSections {
            let kind: HomeSectionKind
            switch recommendationSection.kind {
            case .becauseYouWatched:
                kind = .recommended
            case .moreLikeThis:
                kind = .moreLikeThis
            case .fromFavoriteGenres:
                kind = .fromFavoriteGenres
            case .continueSeries:
                kind = .continueSeries
            case .hiddenGems:
                kind = .hiddenGems
            case .popularInFavoriteGenres:
                kind = .popularInFavoriteGenres
            case .notFinishedYet:
                kind = .notFinishedYet
            }
            appendSection(
                &sections,
                kind: kind,
                title: recommendationSection.title,
                cardStyle: (kind == .continueSeries || kind == .notFinishedYet) ? .landscape : .poster,
                items: cards(from: recommendationSection.items, limit: 8)
            )
        }
    }

    private static func appendSection(
        _ sections: inout [HomeSection],
        kind: HomeSectionKind,
        title: String,
        cardStyle: MediaCardStyle,
        items: [CFMediaCardModel]
    ) {
        guard !items.isEmpty else { return }
        sections.append(HomeSection(kind: kind, title: title, cardStyle: cardStyle, items: items))
    }

    static func section(from items: [MoodDiscoveryItem]) -> HomeSection {
        HomeSection(
            kind: .moodDiscovery,
            title: "What to Watch Today?",
            cardStyle: .landscape,
            items: Array(items.prefix(8)).enumerated().map { index, item in
                CFMediaCardModel(
                    id: item.id,
                    title: item.title,
                    metadata: "Why: \(item.whySuggested)",
                    badge: item.qualityLabel,
                    progress: nil,
                    accentIndex: index,
                    artworkURL: item.artworkURL
                )
            }
        )
    }

    private static func cards(from collections: [MediaCollection]) -> [CFMediaCardModel] {
        collections.enumerated().map { index, collection in
            CFMediaCardModel(
                id: collection.id,
                title: collection.title,
                metadata: "\(collection.kind.title) · \(collection.itemCountLabel)",
                badge: collection.kind.title,
                progress: nil,
                accentIndex: index,
                artworkURL: collection.posterCollageURLs.first
            )
        }
    }

    private static func cards(from items: [MoodDiscoveryItem], titlePrefix: String?) -> [CFMediaCardModel] {
        items.enumerated().map { index, item in
            let title = titlePrefix.map { "\($0): \(item.title)" } ?? item.title
            return CFMediaCardModel(
                id: item.id,
                title: title,
                metadata: item.whySuggested,
                badge: item.qualityLabel,
                progress: nil,
                accentIndex: index,
                artworkURL: item.artworkURL
            )
        }
    }

    private static func cards(from mediaItems: [MediaItem], limit: Int) -> [CFMediaCardModel] {
        Array(mediaItems.prefix(limit)).enumerated().map { index, item in
            CFMediaCardModel(
                id: item.id,
                title: item.displayTitle,
                metadata: metadataLine(for: item),
                badge: item.rankedReleases.first?.quality.qualityLabel,
                progress: nil,
                accentIndex: index,
                artworkURL: item.bestBackdropURL ?? item.bestPosterURL,
                genres: item.metadata?.genres ?? []
            )
        }
    }

    private static func ranked(_ items: [HomeSeedItem], kind: SeedMediaKind) -> [HomeSeedItem] {
        items
            .filter { $0.kind == kind }
            .sorted { $0.popularityRank < $1.popularityRank }
    }

    private static func cards(from items: [HomeSeedItem], limit: Int) -> [CFMediaCardModel] {
        Array(items.prefix(limit)).enumerated().map { index, item in
            CFMediaCardModel(
                id: item.id,
                title: item.title,
                metadata: metadataLine(for: item),
                badge: item.quality,
                progress: item.progress,
                accentIndex: index,
                artworkURL: item.artworkURL,
                genres: [item.genre]
            )
        }
    }

    private static func bestQualityItems(from items: [HomeSeedItem]) -> [HomeSeedItem] {
        items
            .filter { qualityScore(for: $0.quality) >= 3 }
            .sorted {
                let left = qualityScore(for: $0.quality)
                let right = qualityScore(for: $1.quality)
                return left == right ? $0.popularityRank < $1.popularityRank : left > right
            }
    }

    private static func ultraHDRItems(from items: [HomeSeedItem]) -> [HomeSeedItem] {
        items
            .filter { isUltraHDR($0.quality) }
            .sorted {
                let left = qualityScore(for: $0.quality)
                let right = qualityScore(for: $1.quality)
                return left == right ? $0.popularityRank < $1.popularityRank : left > right
            }
    }

    private static func favoriteGenreCards(
        from items: [HomeSeedItem],
        libraryItems: [MediaItem],
        favoriteItems: [MediaItem],
        watchedItems: [WatchedMediaItem],
        ratedItems: [RatedMediaItem],
        progressRecords: [PlaybackProgress],
        limit: Int
    ) -> [CFMediaCardModel] {
        let preferredGenres = preferredGenres(
            libraryItems: libraryItems,
            favoriteItems: favoriteItems,
            watchedItems: watchedItems,
            ratedItems: ratedItems,
            progressRecords: progressRecords
        )
        guard !preferredGenres.isEmpty else { return [] }
        let activeIDs = Set(progressRecords.map(\.mediaID))
        let matchingItems = items.filter { item in
            !activeIDs.contains(item.id) && preferredGenres.contains(item.genre)
        }
        return cards(from: matchingItems, limit: limit)
    }

    private static func mediaLookup(from items: [MediaItem]) -> [String: MediaItem] {
        var lookup: [String: MediaItem] = [:]
        for item in items where lookup[item.id] == nil {
            lookup[item.id] = item
        }
        return lookup
    }

    private static func seedLookup(from items: [HomeSeedItem]) -> [String: HomeSeedItem] {
        var lookup: [String: HomeSeedItem] = [:]
        for item in items where lookup[item.id] == nil {
            lookup[item.id] = item
        }
        return lookup
    }

    private static func seedTitleLookup(from items: [HomeSeedItem]) -> [String: HomeSeedItem] {
        var lookup: [String: HomeSeedItem] = [:]
        for item in items {
            let key = normalizedTitle(item.title)
            if !key.isEmpty, lookup[key] == nil {
                lookup[key] = item
            }
        }
        return lookup
    }

    private static func seedItem(
        for id: String,
        title: String?,
        seedByID: [String: HomeSeedItem],
        seedByTitle: [String: HomeSeedItem]
    ) -> HomeSeedItem? {
        if let item = seedByID[id] {
            return item
        }
        guard let title else { return nil }
        return seedByTitle[normalizedTitle(title)]
    }

    private static func normalizedTitle(_ title: String) -> String {
        String(title.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static func unfinishedMovieCards(
        from seedItems: [HomeSeedItem],
        libraryItems: [MediaItem],
        progressRecords: [PlaybackProgress],
        limit: Int
    ) -> [CFMediaCardModel] {
        let mediaByID = mediaLookup(from: libraryItems)
        let seedByID = seedLookup(from: seedItems)
        let seedByTitle = seedTitleLookup(from: seedItems)
        let cards = progressRecords
            .filter { !$0.completed && $0.episodeID == nil && (mediaByID[$0.mediaID]?.kind == .movie || seedByID[$0.mediaID]?.kind == .movie) }
            .sorted { $0.lastWatchedAt > $1.lastWatchedAt }
            .prefix(limit)
            .map { progress -> CFMediaCardModel in
                let mediaItem = mediaByID[progress.mediaID]
                let seedItem = seedItem(
                    for: progress.mediaID,
                    title: mediaItem?.displayTitle,
                    seedByID: seedByID,
                    seedByTitle: seedByTitle
                )
                return card(from: progress, mediaItem: mediaItem, seedItem: seedItem)
            }
        return Array(cards)
    }

    private static func forgottenLibraryCards(
        from libraryItems: [MediaItem],
        progressRecords: [PlaybackProgress],
        favoriteItems: [MediaItem],
        watchedItems: [WatchedMediaItem],
        ratedItems: [RatedMediaItem],
        limit: Int
    ) -> [CFMediaCardModel] {
        let activeIDs = Set(progressRecords.map(\.mediaID))
        let favoriteIDs = Set(favoriteItems.map(\.id))
        let watchedIDs = Set(watchedItems.map(\.id))
        let ratedIDs = Set(ratedItems.map(\.id))
        let usedIDs = activeIDs.union(favoriteIDs).union(watchedIDs).union(ratedIDs)
        return cards(
            from: libraryItems.filter { !usedIDs.contains($0.id) },
            limit: limit
        )
    }

    private static func becauseYouWatchedCards(
        from items: [HomeSeedItem],
        progressRecords: [PlaybackProgress],
        limit: Int
    ) -> [CFMediaCardModel] {
        let activeIDs = Set(progressRecords.map(\.mediaID))
        let watchedGenres = Set(items.filter { activeIDs.contains($0.id) }.map(\.genre))
        let matchingItems = items.filter { item in
            !activeIDs.contains(item.id) && (item.isRecommended || watchedGenres.contains(item.genre))
        }
        return cards(from: matchingItems, limit: limit)
    }

    private static func allPersonalProgressRecords(
        active progressRecords: [PlaybackProgress],
        usesProgressRepository: Bool,
        seedItems: [HomeSeedItem]
    ) -> [PlaybackProgress] {
        guard !usesProgressRepository else { return progressRecords }
        return seedItems.compactMap { item in
            guard let progress = item.progress else { return nil }
            return PlaybackProgress(
                mediaID: item.id,
                positionSeconds: progress * 100,
                durationSeconds: 100,
                progressPercent: progress * 100
            )
        }
    }

    private static func card(
        from progress: PlaybackProgress,
        mediaItem: MediaItem?,
        seedItem: HomeSeedItem?
    ) -> CFMediaCardModel {
        CFMediaCardModel(
            id: progress.mediaID,
            title: title(for: progress, mediaItem: mediaItem, seedItem: seedItem),
            metadata: "\(Int(progress.progressPercent.rounded()))% watched",
            badge: mediaItem?.rankedReleases.first?.quality.qualityLabel ?? seedItem?.quality,
            progress: progress.progressPercent / 100,
            accentIndex: abs(progress.mediaID.hashValue),
            artworkURL: artworkURL(mediaItem: mediaItem, seedItem: seedItem),
            genres: genres(mediaItem: mediaItem, seedItem: seedItem)
        )
    }

    private static func card(
        from item: WatchNextEpisode,
        mediaItem: MediaItem?,
        seedItem: HomeSeedItem?
    ) -> CFMediaCardModel {
        CFMediaCardModel(
            id: item.seriesID,
            title: item.seriesTitle,
            metadata: "\(item.ctaTitle) · \(item.episode.title)",
            badge: "\(Int(item.seasonProgress.progressFraction * 100))% season",
            progress: item.progress,
            accentIndex: abs(item.seriesID.hashValue),
            artworkURL: artworkURL(mediaItem: mediaItem, seedItem: seedItem),
            genres: genres(mediaItem: mediaItem, seedItem: seedItem)
        )
    }

    private static func card(
        from item: NewSeriesEpisode,
        mediaItem: MediaItem?,
        seedItem: HomeSeedItem?
    ) -> CFMediaCardModel {
        CFMediaCardModel(
            id: item.seriesID,
            title: item.seriesTitle,
            metadata: "\(episodeLabel(for: item.episode)) · \(item.episode.title) · \(item.sourceBadgeText)",
            badge: item.metadataBadgeText,
            progress: nil,
            accentIndex: abs(item.id.hashValue),
            artworkURL: artworkURL(mediaItem: mediaItem, seedItem: seedItem),
            genres: genres(mediaItem: mediaItem, seedItem: seedItem)
        )
    }

    private static func title(
        for progress: PlaybackProgress,
        mediaItem: MediaItem?,
        seedItem: HomeSeedItem?
    ) -> String {
        if let title = mediaItem?.displayTitle,
           !title.isEmpty,
           !isTechnicalMediaIdentifier(title) {
            return title
        }
        if let title = seedItem?.title, !title.isEmpty {
            return title
        }
        if let title = mediaItem?.displayTitle, !title.isEmpty {
            return title
        }
        return progress.episodeID == nil ? "Фильм" : "Серия"
    }

    private static func isTechnicalMediaIdentifier(_ title: String) -> Bool {
        let normalized = title.lowercased()
        return normalized.hasPrefix("tmdb:")
            || normalized.hasPrefix("imdb:")
            || normalized.range(of: #"^tt\d+$"#, options: .regularExpression) != nil
    }

    private static func artworkURL(mediaItem: MediaItem?, seedItem: HomeSeedItem?) -> URL? {
        mediaItem?.bestBackdropURL
            ?? mediaItem?.bestPosterURL
            ?? seedItem?.backdropURL
            ?? seedItem?.artworkURL
    }

    private static func genres(mediaItem: MediaItem?, seedItem: HomeSeedItem?) -> [String] {
        if let genres = mediaItem?.metadata?.genres, !genres.isEmpty {
            return genres
        }
        if let genre = seedItem?.genre, !genre.isEmpty {
            return [genre]
        }
        return []
    }

    private static func card(from item: UpcomingCalendarItem) -> CFMediaCardModel {
        CFMediaCardModel(
            id: item.id,
            title: item.title,
            metadata: "\(item.badgeText) · \(item.subtitle) · \(item.watchlistActionTitle)",
            badge: item.badgeText,
            progress: nil,
            accentIndex: abs(item.id.hashValue),
            artworkURL: item.posterURL
        )
    }

    private static func metadataLine(for item: HomeSeedItem) -> String {
        "\(item.year) · \(item.rating) · \(item.runtime) · \(item.genre)"
    }

    private static func metadataLine(for item: MediaItem) -> String {
        let kind = item.kind == .movie ? "Movie" : "Series"
        let genres = item.metadata?.genres.prefix(2).joined(separator: ", ")
        let year = item.displayYear
        if let genres, !genres.isEmpty {
            return "\(year) · \(kind) · \(genres)"
        }
        return "\(year) · \(kind)"
    }

    private static func preferredGenres(
        libraryItems: [MediaItem],
        favoriteItems: [MediaItem],
        watchedItems: [WatchedMediaItem],
        ratedItems: [RatedMediaItem],
        progressRecords: [PlaybackProgress]
    ) -> Set<String> {
        var scores: [String: Int] = [:]
        func add(_ item: MediaItem, weight: Int) {
            for genre in item.metadata?.genres ?? [] {
                scores[genre, default: 0] += weight
            }
        }

        favoriteItems.forEach { add($0, weight: 4) }
        ratedItems.filter { $0.rating >= 7 }.forEach { add($0.item, weight: 3) }
        watchedItems.forEach { add($0.item, weight: 2) }
        let progressIDs = Set(progressRecords.map(\.mediaID))
        libraryItems.filter { progressIDs.contains($0.id) }.forEach { add($0, weight: 2) }
        if scores.isEmpty {
            libraryItems.forEach { add($0, weight: 1) }
        }

        return Set(scores.sorted { left, right in
            left.value == right.value ? left.key < right.key : left.value > right.value
        }.prefix(3).map(\.key))
    }

    private static func qualityScore(for quality: String) -> Int {
        let normalized = quality.lowercased()
        var score = 0
        if normalized.contains("2160") || normalized.contains("4k") {
            score += 4
        } else if normalized.contains("1080") {
            score += 3
        } else if normalized.contains("720") {
            score += 2
        }
        if normalized.contains("hdr") || normalized.contains("dolby") {
            score += 2
        }
        return score
    }

    private static func isUltraHDR(_ quality: String) -> Bool {
        let normalized = quality.lowercased()
        return normalized.contains("2160") || normalized.contains("4k") || normalized.contains("hdr")
    }

    private static func episodeLabel(for episode: SeriesEpisode) -> String {
        String(format: "S%02dE%02d", episode.seasonNumber, episode.episodeNumber)
    }
}
