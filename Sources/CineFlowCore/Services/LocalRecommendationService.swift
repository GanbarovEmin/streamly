import Foundation

public enum RecommendationSectionKind: String, Codable, CaseIterable, Equatable, Sendable {
    case becauseYouWatched
    case moreLikeThis
    case fromFavoriteGenres
    case continueSeries
    case hiddenGems
    case popularInFavoriteGenres
    case notFinishedYet
}

public struct RecommendationSection: Equatable, Sendable {
    public let kind: RecommendationSectionKind
    public let title: String
    public let items: [MediaItem]
    public let explanationsByMediaID: [String: String]

    public init(
        kind: RecommendationSectionKind,
        title: String,
        items: [MediaItem],
        explanationsByMediaID: [String: String] = [:]
    ) {
        self.kind = kind
        self.title = title
        self.items = items
        self.explanationsByMediaID = explanationsByMediaID
    }

    public func explanation(for item: MediaItem) -> String {
        explanationsByMediaID[item.id] ?? ""
    }
}

public protocol RecommendationServiceProtocol {
    func homeRecommendations(limit: Int) async throws -> [RecommendationSection]
    func recommendations(for item: MediaItem, seedSimilar: [MediaItem], limit: Int) async throws -> [MediaItem]
}

public struct LocalRecommendationService: RecommendationServiceProtocol {
    private let libraryRepository: any LibraryRepositoryProtocol
    private let progressRepository: (any PlaybackProgressRepositoryProtocol)?
    private let metadataService: (any MetadataServiceProtocol)?
    private let settingsRepository: (any SettingsRepositoryProtocol)?

    public init(
        libraryRepository: any LibraryRepositoryProtocol,
        progressRepository: (any PlaybackProgressRepositoryProtocol)? = nil,
        metadataService: (any MetadataServiceProtocol)? = nil,
        settingsRepository: (any SettingsRepositoryProtocol)? = nil
    ) {
        self.libraryRepository = libraryRepository
        self.progressRepository = progressRepository
        self.metadataService = metadataService
        self.settingsRepository = settingsRepository
    }

    public func homeRecommendations(limit: Int) async throws -> [RecommendationSection] {
        let libraryItems = try await libraryRepository.items()
        let favoriteItems = try await libraryRepository.favorites()
        let watchedItems = try await libraryRepository.watchedItems()
        let ratedItems = try await libraryRepository.ratedItems()
        let progressRecords = try await progressRepository?.continueWatching(includeCompleted: false) ?? []
        let allProgressRecords = try await progressRepository?.continueWatching(includeCompleted: true) ?? progressRecords
        let listedItems = try await listedItems()
        let tasteProfile = await settingsRepository?.appSettings.tasteProfile ?? TasteProfileSettings()
        let context = RecommendationContext(
            libraryItems: libraryItems,
            favoriteItems: favoriteItems,
            watchedItems: watchedItems,
            ratedItems: ratedItems,
            listedItems: listedItems,
            progressRecords: progressRecords,
            allProgressRecords: allProgressRecords,
            tasteProfile: tasteProfile
        )

        var sections: [RecommendationSection] = []
        var usedIDs = Set<String>()
        let watchedSeeds = context.watchedItems.map(\.item) + context.progressSeedItems
        let combinedGenreScores = Self.genreScores(
            favorites: context.favoriteItems,
            watched: context.watchedItems,
            rated: context.ratedItems,
            listed: context.listedItems,
            progressSeeds: context.progressSeedItems,
            tasteProfile: tasteProfile
        )
        let watchedGenreScores = Self.genreScores(
            favorites: [],
            watched: context.watchedItems,
            rated: [],
            listed: [],
            progressSeeds: context.progressSeedItems,
            tasteProfile: TasteProfileSettings()
        )
        let favoriteGenreScores = Self.genreScores(
            favorites: context.favoriteItems,
            watched: [],
            rated: context.ratedItems,
            listed: context.listedItems,
            progressSeeds: [],
            tasteProfile: tasteProfile
        )
        let personScores = Self.personScores(
            favorites: context.favoriteItems,
            watched: context.watchedItems,
            rated: context.ratedItems,
            listed: context.listedItems,
            tasteProfile: tasteProfile
        )
        let excludedIDs = context.completedIDs.union(context.abandonedIDs)
        let discoveryExcludedIDs = excludedIDs.union(context.activeProgressIDs)

        let notFinished = context.allProgressRecords
            .filter { !$0.completed && $0.progressPercent >= 15 }
            .compactMap { context.mediaByID[$0.mediaID] }
            .filter { $0.kind == .movie }
            .filter { !tasteProfile.isHidden(mediaID: $0.id) }
            .filter { !tasteProfile.hidesAnyGenre(in: $0) }
            .uniquedByID()
        appendUnique(&sections, usedIDs: &usedIDs, kind: .notFinishedYet, title: "Not Finished Yet", items: notFinished, limit: limit) { item in
            "Paused at \(Int(context.progressByMediaID[item.id]?.progressPercent ?? 0))%."
        }

        let hiddenGems = rankedCandidates(
            from: context.libraryItems.filter { ($0.metadata?.rating ?? 0) >= 8.5 },
            seedItems: watchedSeeds,
            genreScores: combinedGenreScores,
            personScores: personScores,
            tasteProfile: tasteProfile,
            excluding: discoveryExcludedIDs.union(usedIDs),
            limit: limit
        )
        appendUnique(&sections, usedIDs: &usedIDs, kind: .hiddenGems, title: "Hidden Gems", items: hiddenGems, limit: limit) { item in
            explanation(for: item, seedItems: watchedSeeds, genreScores: combinedGenreScores, personScores: personScores, prefix: "Local gem")
        }

        let popularFavoriteGenres = rankedCandidates(
            from: context.libraryItems.filter { ($0.metadata?.rating ?? 0) >= 7.7 },
            seedItems: watchedSeeds + context.favoriteItems,
            genreScores: favoriteGenreScores,
            personScores: personScores,
            tasteProfile: tasteProfile,
            excluding: discoveryExcludedIDs.union(usedIDs),
            limit: limit
        )
        appendUnique(&sections, usedIDs: &usedIDs, kind: .popularInFavoriteGenres, title: "Popular in Your Favorite Genres", items: popularFavoriteGenres, limit: limit) { item in
            explanation(for: item, seedItems: watchedSeeds, genreScores: favoriteGenreScores, personScores: personScores, prefix: "Popular match")
        }

        let because = rankedCandidates(
            from: context.libraryItems,
            seedItems: watchedSeeds,
            genreScores: watchedGenreScores,
            personScores: personScores,
            tasteProfile: tasteProfile,
            excluding: Set(watchedSeeds.map(\.id)).union(discoveryExcludedIDs).union(usedIDs),
            limit: limit
        )
        appendUnique(&sections, usedIDs: &usedIDs, kind: .becauseYouWatched, title: "Because You Watched", items: because, limit: limit) { item in
            explanation(for: item, seedItems: watchedSeeds, genreScores: watchedGenreScores, personScores: personScores, prefix: "Because you watched")
        }

        let favoriteGenreItems = rankedCandidates(
            from: context.libraryItems,
            seedItems: context.favoriteItems + context.ratedItems.filter { $0.rating >= 8 }.map(\.item),
            genreScores: favoriteGenreScores,
            personScores: personScores,
            tasteProfile: tasteProfile,
            excluding: discoveryExcludedIDs.union(usedIDs),
            limit: limit
        )
        appendUnique(&sections, usedIDs: &usedIDs, kind: .fromFavoriteGenres, title: "From Your Favorite Genres", items: favoriteGenreItems, limit: limit) { item in
            explanation(for: item, seedItems: context.favoriteItems, genreScores: favoriteGenreScores, personScores: personScores, prefix: "Favorite genre")
        }

        let continueSeries = context.progressRecords
            .filter { !$0.completed }
            .compactMap { progress in context.mediaByID[progress.mediaID] }
            .filter { $0.kind == .series }
            .filter { !tasteProfile.isHidden(mediaID: $0.id) }
            .filter { !tasteProfile.hidesAnyGenre(in: $0) }
            .uniquedByID()
        appendUnique(&sections, usedIDs: &usedIDs, kind: .continueSeries, title: "Continue Series", items: continueSeries, limit: limit) { _ in
            "Unfinished series from local progress."
        }

        if let latestSeed = watchedSeeds.first,
           let metadataService,
           let metadataSimilar = try? await metadataService.similar(to: latestSeed.id) {
            let moreLikeThis = try await recommendations(for: latestSeed, seedSimilar: metadataSimilar, limit: limit)
            appendUnique(&sections, usedIDs: &usedIDs, kind: .moreLikeThis, title: "More Like This", items: moreLikeThis, limit: limit) { item in
                explanation(for: item, seedItems: [latestSeed], genreScores: combinedGenreScores, personScores: personScores, prefix: "More like \(latestSeed.displayTitle)")
            }
        } else if let latestSeed = watchedSeeds.first {
            let moreLikeThis = try await recommendations(for: latestSeed, seedSimilar: [], limit: limit)
            appendUnique(&sections, usedIDs: &usedIDs, kind: .moreLikeThis, title: "More Like This", items: moreLikeThis, limit: limit) { item in
                explanation(for: item, seedItems: [latestSeed], genreScores: combinedGenreScores, personScores: personScores, prefix: "More like \(latestSeed.displayTitle)")
            }
        }

        return sections
    }

    public func recommendations(for item: MediaItem, seedSimilar: [MediaItem], limit: Int) async throws -> [MediaItem] {
        let libraryItems = try await libraryRepository.items()
        let favoriteItems = try await libraryRepository.favorites()
        let watchedItems = try await libraryRepository.watchedItems()
        let ratedItems = try await libraryRepository.ratedItems()
        let listedItems = try await listedItems()
        let progressRecords = try await progressRepository?.continueWatching(includeCompleted: true) ?? []
        let completedIDs = Set(progressRecords.filter(\.completed).map(\.mediaID))
            .union(watchedItems.map(\.item.id))
        let abandonedIDs = Set(progressRecords.filter { !$0.completed && $0.progressPercent > 0 && $0.progressPercent < 15 }.map(\.mediaID))
        let tasteProfile = await settingsRepository?.appSettings.tasteProfile ?? TasteProfileSettings()
        let genreScores = Self.genreScores(
            favorites: favoriteItems,
            watched: watchedItems,
            rated: ratedItems,
            listed: listedItems,
            progressSeeds: [],
            tasteProfile: tasteProfile
        )
        let personScores = Self.personScores(
            favorites: favoriteItems,
            watched: watchedItems,
            rated: ratedItems,
            listed: listedItems,
            tasteProfile: tasteProfile
        )
        let candidates = (libraryItems + seedSimilar).uniquedByID()
        let ranked = rankedCandidates(
            from: candidates,
            seedItems: [item],
            genreScores: genreScores,
            personScores: personScores,
            tasteProfile: tasteProfile,
            excluding: Set([item.id]).union(completedIDs).union(abandonedIDs).union(tasteProfile.hiddenMediaIDs),
            limit: limit
        )
        return ranked
    }

    private func append(
        _ sections: inout [RecommendationSection],
        kind: RecommendationSectionKind,
        title: String,
        items: [MediaItem]
    ) {
        guard !items.isEmpty else { return }
        sections.append(RecommendationSection(kind: kind, title: title, items: items))
    }

    private func rankedCandidates(
        from candidates: [MediaItem],
        seedItems: [MediaItem],
        genreScores: [String: Double],
        personScores: [String: Double],
        tasteProfile: TasteProfileSettings,
        excluding excludedIDs: Set<String>,
        limit: Int
    ) -> [MediaItem] {
        let seedGenres = Set(seedItems.flatMap(Self.genres).map(Self.normalize))
        let seedPeople = Set(seedItems.flatMap(Self.people).map(\.id).map(Self.normalize))
        let rankedCandidates = candidates
            .uniquedByID()
            .filter { !excludedIDs.contains($0.id) }
            .filter { !tasteProfile.isHidden(mediaID: $0.id) }
            .filter { !tasteProfile.hidesAnyGenre(in: $0) }
            .map { item in
                rankedCandidate(
                    for: item,
                    seedGenres: seedGenres,
                    seedPeople: seedPeople,
                    genreScores: genreScores,
                    personScores: personScores,
                    tasteProfile: tasteProfile
                )
            }
            .filter { $0.relevance > 0 }
            .filter { $0.score > 0 }
        let sortedCandidates = rankedCandidates.sorted(by: Self.sortRankedCandidates)
        return Array(sortedCandidates.prefix(limit).map { $0.item })
    }

    private static func sortRankedCandidates(_ lhs: RankedRecommendationCandidate, _ rhs: RankedRecommendationCandidate) -> Bool {
        if lhs.score == rhs.score {
            return lhs.item.displayTitle < rhs.item.displayTitle
        }
        return lhs.score > rhs.score
    }

    private func rankedCandidate(
        for item: MediaItem,
        seedGenres: Set<String>,
        seedPeople: Set<String>,
        genreScores: [String: Double],
        personScores: [String: Double],
        tasteProfile: TasteProfileSettings
    ) -> RankedRecommendationCandidate {
        let genres = Set(Self.genres(item).map(Self.normalize))
        let people = Set(Self.people(item).map(\.id).map(Self.normalize))
        let genreAffinity = genres.reduce(0.0) { partial, genre in
            partial + (genreScores[genre] ?? 0)
        }
        let peopleAffinity = people.reduce(0.0) { partial, personID in
            partial + (personScores[personID] ?? 0)
        }
        let genreOverlap = Double(genres.intersection(seedGenres).count)
        let peopleOverlap = Double(people.intersection(seedPeople).count)
        let positiveGenreAffinity = Swift.max(0, genreAffinity)
        let positivePeopleAffinity = Swift.max(0, peopleAffinity)
        let relevance = genreOverlap + peopleOverlap + positiveGenreAffinity + positivePeopleAffinity
        return RankedRecommendationCandidate(
            item: item,
            score: score(
                item,
                seedGenres: seedGenres,
                seedPeople: seedPeople,
                genreScores: genreScores,
                personScores: personScores,
                tasteProfile: tasteProfile
            ),
            relevance: relevance
        )
    }

    private func score(
        _ item: MediaItem,
        seedGenres: Set<String>,
        seedPeople: Set<String>,
        genreScores: [String: Double],
        personScores: [String: Double],
        tasteProfile: TasteProfileSettings
    ) -> Double {
        let genres = Set(Self.genres(item).map(Self.normalize))
        let overlap = genres.intersection(seedGenres)
        let people = Set(Self.people(item).map(\.id).map(Self.normalize))
        let peopleOverlap = people.intersection(seedPeople)
        let genreAffinity = genres.reduce(0.0) { $0 + (genreScores[$1] ?? 0) }
        let peopleAffinity = people.reduce(0.0) { $0 + (personScores[$1] ?? 0) }
        let metadataRating = item.metadata?.rating ?? 0
        let releaseBoost = Double(item.releaseYear ?? item.metadata?.year ?? 0) / 10_000
        let kindBoost = tasteProfile.preferredMediaKinds.isEmpty || tasteProfile.preferredMediaKinds.contains(item.kind) ? 1.2 : -1.5
        return Double(overlap.count) * 6
            + Double(peopleOverlap.count) * 5
            + genreAffinity
            + peopleAffinity
            + metadataRating / 2
            + releaseBoost
            + kindBoost
    }

    private static func genreScores(
        favorites: [MediaItem],
        watched: [WatchedMediaItem],
        rated: [RatedMediaItem],
        listed: [MediaItem],
        progressSeeds: [MediaItem],
        tasteProfile: TasteProfileSettings
    ) -> [String: Double] {
        var scores: [String: Double] = [:]
        func add(_ item: MediaItem, weight: Double) {
            for genre in genres(item).map(normalize) {
                scores[genre, default: 0] += weight
            }
        }
        favorites.forEach { add($0, weight: 4) }
        watched.forEach { add($0.item, weight: 3) }
        rated.forEach { add($0.item, weight: $0.rating >= 7 ? Double($0.rating) / 2 : -Double(7 - $0.rating)) }
        listed.forEach { add($0, weight: 2) }
        progressSeeds.forEach { add($0, weight: 2) }
        for preference in tasteProfile.genrePreferences {
            switch preference.preference {
            case .more:
                scores[preference.normalizedGenre, default: 0] += 8
            case .less:
                scores[preference.normalizedGenre, default: 0] -= 5
            case .hidden:
                scores[preference.normalizedGenre, default: 0] -= 100
            }
        }
        return scores
    }

    private static func personScores(
        favorites: [MediaItem],
        watched: [WatchedMediaItem],
        rated: [RatedMediaItem],
        listed: [MediaItem],
        tasteProfile: TasteProfileSettings
    ) -> [String: Double] {
        var scores: [String: Double] = [:]
        func add(_ item: MediaItem, weight: Double) {
            for person in people(item) {
                scores[normalize(person.id), default: 0] += weight
            }
        }
        favorites.forEach { add($0, weight: 3) }
        watched.forEach { add($0.item, weight: 2) }
        rated.forEach { add($0.item, weight: $0.rating >= 7 ? Double($0.rating) / 3 : -Double(7 - $0.rating)) }
        listed.forEach { add($0, weight: 1.5) }
        tasteProfile.preferredActorIDs.forEach { scores[normalize($0), default: 0] += 6 }
        tasteProfile.preferredDirectorIDs.forEach { scores[normalize($0), default: 0] += 6 }
        return scores
    }

    private static func genres(_ item: MediaItem) -> [String] {
        item.metadata?.genres ?? []
    }

    private static func people(_ item: MediaItem) -> [CastMember] {
        item.metadata?.cast ?? []
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func appendUnique(
        _ sections: inout [RecommendationSection],
        usedIDs: inout Set<String>,
        kind: RecommendationSectionKind,
        title: String,
        items: [MediaItem],
        limit: Int,
        explanation: (MediaItem) -> String
    ) {
        let unique = items.filter { usedIDs.insert($0.id).inserted }.prefix(limit)
        guard !unique.isEmpty else { return }
        let sectionItems = Array(unique)
        sections.append(RecommendationSection(
            kind: kind,
            title: title,
            items: sectionItems,
            explanationsByMediaID: Dictionary(uniqueKeysWithValues: sectionItems.map { ($0.id, explanation($0)) })
        ))
    }

    private func explanation(
        for item: MediaItem,
        seedItems: [MediaItem],
        genreScores: [String: Double],
        personScores: [String: Double],
        prefix: String
    ) -> String {
        let seedGenres = Set(seedItems.flatMap(Self.genres).map(Self.normalize))
        let matchingGenres = Self.genres(item).filter { seedGenres.contains(Self.normalize($0)) || (genreScores[Self.normalize($0)] ?? 0) > 0 }
        let matchingPeople = Self.people(item).filter { (personScores[Self.normalize($0.id)] ?? 0) > 0 }.map(\.name)
        var reasons: [String] = []
        if let genre = matchingGenres.first {
            reasons.append(genre)
        }
        if let person = matchingPeople.first {
            reasons.append(person)
        }
        if let rating = item.metadata?.rating, rating >= 8 {
            reasons.append(String(format: "rated %.1f", rating))
        }
        return reasons.isEmpty ? prefix : "\(prefix): \(reasons.prefix(3).joined(separator: ", "))"
    }

    private func listedItems() async throws -> [MediaItem] {
        let lists = try await libraryRepository.lists()
        var items: [MediaItem] = []
        for list in lists {
            items.append(contentsOf: try await libraryRepository.items(in: list.id))
        }
        return items.uniquedByID()
    }
}

private struct RecommendationContext {
    let libraryItems: [MediaItem]
    let favoriteItems: [MediaItem]
    let watchedItems: [WatchedMediaItem]
    let ratedItems: [RatedMediaItem]
    let listedItems: [MediaItem]
    let progressRecords: [PlaybackProgress]
    let allProgressRecords: [PlaybackProgress]
    let tasteProfile: TasteProfileSettings

    var mediaByID: [String: MediaItem] {
        Dictionary(uniqueKeysWithValues: libraryItems.map { ($0.id, $0) })
    }

    var progressSeedItems: [MediaItem] {
        progressRecords.compactMap { mediaByID[$0.mediaID] }
    }

    var progressByMediaID: [String: PlaybackProgress] {
        allProgressRecords.reduce(into: [:]) { result, progress in
            result[progress.mediaID] = progress
        }
    }

    var completedIDs: Set<String> {
        Set(allProgressRecords.filter(\.completed).map(\.mediaID))
            .union(watchedItems.map(\.item.id))
    }

    var abandonedIDs: Set<String> {
        Set(allProgressRecords.filter { !$0.completed && $0.progressPercent > 0 && $0.progressPercent < 15 }.map(\.mediaID))
    }

    var activeProgressIDs: Set<String> {
        Set(allProgressRecords.filter { !$0.completed && $0.progressPercent >= 15 }.map(\.mediaID))
    }
}

private struct RankedRecommendationCandidate {
    let item: MediaItem
    let score: Double
    let relevance: Double
}

private extension Array where Element == MediaItem {
    func uniquedByID() -> [MediaItem] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}

private extension TasteProfileSettings {
    func hidesAnyGenre(in item: MediaItem) -> Bool {
        (item.metadata?.genres ?? []).contains { preference(forGenre: $0) == .hidden }
    }
}
