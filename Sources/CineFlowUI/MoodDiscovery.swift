import CineFlowCore
import Foundation

public enum MoodDiscoveryFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case lightEvening
    case epic
    case shortMovie
    case backgroundSeries
    case highRated
    case new
    case fourKHDR
    case drama
    case action
    case comedy
    case runtime30To60
    case under90Minutes
    case longWeekendPicks

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lightEvening:
            "Light evening"
        case .epic:
            "Epic"
        case .shortMovie:
            "Short movie"
        case .backgroundSeries:
            "Series on background"
        case .highRated:
            "High rating"
        case .new:
            "New"
        case .fourKHDR:
            "4K/HDR"
        case .drama:
            "Drama"
        case .action:
            "Action"
        case .comedy:
            "Comedy"
        case .runtime30To60:
            "30-60 min"
        case .under90Minutes:
            "Under 90 min"
        case .longWeekendPicks:
            "Long weekend"
        }
    }

    public var searchQuery: String {
        switch self {
        case .lightEvening:
            "light evening"
        case .epic:
            "epic"
        case .shortMovie:
            "short movie"
        case .backgroundSeries:
            "background series"
        case .highRated:
            "high rated"
        case .new:
            "new"
        case .fourKHDR:
            "4K HDR"
        case .drama:
            "Drama"
        case .action:
            "Action"
        case .comedy:
            "Comedy"
        case .runtime30To60:
            "30-60 minutes"
        case .under90Minutes:
            "under 90 minutes"
        case .longWeekendPicks:
            "long weekend"
        }
    }

    public static let homeFilters: [MoodDiscoveryFilter] = [
        .lightEvening,
        .epic,
        .shortMovie,
        .backgroundSeries,
        .highRated,
        .fourKHDR,
        .drama,
        .action,
        .comedy,
        .runtime30To60,
        .under90Minutes,
        .longWeekendPicks
    ]
}

public enum MoodDiscoveryCandidateSource: String, Equatable, Sendable {
    case library
    case metadata
}

public struct MoodDiscoveryCandidate: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let kind: SeedMediaKind
    public let year: Int
    public let overview: String
    public let genres: [String]
    public let runtimeMinutes: Int?
    public let ratingScore: Double?
    public let qualityLabel: String
    public let artworkURL: URL?
    public let source: MoodDiscoveryCandidateSource

    public init(
        id: String,
        title: String,
        kind: SeedMediaKind,
        year: Int,
        overview: String,
        genres: [String],
        runtimeMinutes: Int?,
        ratingScore: Double?,
        qualityLabel: String,
        artworkURL: URL?,
        source: MoodDiscoveryCandidateSource
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.year = year
        self.overview = overview
        self.genres = genres
        self.runtimeMinutes = runtimeMinutes
        self.ratingScore = ratingScore
        self.qualityLabel = qualityLabel
        self.artworkURL = artworkURL
        self.source = source
    }

    public init(seedItem: HomeSeedItem, source: MoodDiscoveryCandidateSource = .metadata) {
        self.init(
            id: seedItem.id,
            title: seedItem.title,
            kind: seedItem.kind,
            year: seedItem.year,
            overview: seedItem.overview,
            genres: seedItem.genre.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            runtimeMinutes: Self.runtimeMinutes(from: seedItem.runtime),
            ratingScore: RatingAggregator.parseRating(seedItem.rating),
            qualityLabel: seedItem.quality,
            artworkURL: seedItem.artworkURL,
            source: source
        )
    }

    public init(mediaItem: MediaItem) {
        let metadata = mediaItem.metadata
        let releases = mediaItem.rankedReleases
        let bestRelease = releases.first
        let qualityLabel: String
        if let bestRelease {
            if bestRelease.hdr == .hdr10 || bestRelease.hdr == .dolbyVision {
                qualityLabel = "\(bestRelease.qualityLabel) HDR"
            } else {
                qualityLabel = bestRelease.qualityLabel
            }
        } else {
            qualityLabel = mediaItem.kind == .series ? "Series" : "Movie"
        }
        self.init(
            id: mediaItem.id,
            title: mediaItem.displayTitle,
            kind: mediaItem.kind == .series ? .series : .movie,
            year: metadata?.year ?? mediaItem.releaseYear ?? 0,
            overview: metadata?.overview ?? mediaItem.overview,
            genres: metadata?.genres ?? [],
            runtimeMinutes: metadata?.runtime,
            ratingScore: metadata?.rating,
            qualityLabel: qualityLabel,
            artworkURL: mediaItem.bestPosterURL,
            source: .library
        )
    }

    var hasUltraHDOrHDR: Bool {
        let normalized = qualityLabel.lowercased()
        return normalized.contains("2160") || normalized.contains("4k") || normalized.contains("hdr")
    }

    private static func runtimeMinutes(from value: String) -> Int? {
        let lowercased = value.lowercased()
        if lowercased.contains("season") {
            return nil
        }
        let hourPattern = #"(\d+)\s*h"#
        let minutePattern = #"(\d+)\s*m"#
        let hours = firstIntegerMatch(in: lowercased, pattern: hourPattern) ?? 0
        let minutes = firstIntegerMatch(in: lowercased, pattern: minutePattern) ?? 0
        let total = hours * 60 + minutes
        return total > 0 ? total : nil
    }

    private static func firstIntegerMatch(in value: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value)
        else { return nil }
        return Int(value[range])
    }
}

public struct MoodDiscoveryTasteProfile: Equatable, Sendable {
    public let preferredGenres: [String]
    public let libraryIDs: Set<String>
    public let continueWatchingIDs: Set<String>

    public init(preferredGenres: [String] = [], libraryIDs: [String] = [], continueWatchingIDs: [String] = []) {
        self.preferredGenres = preferredGenres
        self.libraryIDs = Set(libraryIDs)
        self.continueWatchingIDs = Set(continueWatchingIDs)
    }

    public static func from(libraryItems: [MediaItem], progressRecords: [PlaybackProgress]) -> MoodDiscoveryTasteProfile {
        let genres = libraryItems
            .flatMap { $0.metadata?.genres ?? [] }
            .reduce(into: [String: Int]()) { counts, genre in
                counts[genre, default: 0] += 1
            }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(4)
            .map(\.key)
        return MoodDiscoveryTasteProfile(
            preferredGenres: genres,
            libraryIDs: libraryItems.map(\.id),
            continueWatchingIDs: progressRecords.map(\.mediaID)
        )
    }
}

public struct MoodDiscoveryItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let kind: SeedMediaKind
    public let year: Int
    public let qualityLabel: String
    public let artworkURL: URL?
    public let reasons: [String]
    public let score: Double

    public var whySuggested: String {
        reasons.prefix(3).joined(separator: " · ")
    }
}

public struct MoodDiscoveryEngine: Sendable {
    public init() {}

    public func recommendations(
        from candidates: [MoodDiscoveryCandidate],
        filter: MoodDiscoveryFilter,
        tasteProfile: MoodDiscoveryTasteProfile = MoodDiscoveryTasteProfile(),
        limit: Int = 8
    ) -> [MoodDiscoveryItem] {
        candidates
            .compactMap { candidate in
                item(for: candidate, filter: filter, tasteProfile: tasteProfile)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.title < rhs.title
                }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map { $0 }
    }

    public func pickForMe(
        from candidates: [MoodDiscoveryCandidate],
        tasteProfile: MoodDiscoveryTasteProfile = MoodDiscoveryTasteProfile()
    ) -> MoodDiscoveryItem? {
        let filtered = candidates.compactMap { candidate -> MoodDiscoveryItem? in
            var reasons: [String] = []
            var score = baseScore(for: candidate, tasteProfile: tasteProfile, reasons: &reasons)
            if candidate.kind == .movie {
                score += 8
            }
            if candidate.hasUltraHDOrHDR {
                score += 5
                reasons.append("4K/HDR available")
            }
            if let rating = candidate.ratingScore, rating >= 7.5 {
                score += rating
                reasons.append(String(format: "TMDB %.1f", rating))
            }
            guard !reasons.isEmpty else { return nil }
            return MoodDiscoveryItem(candidate: candidate, reasons: reasons, score: score)
        }
        return filtered.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.title < rhs.title
            }
            return lhs.score > rhs.score
        }.first
    }

    private func item(
        for candidate: MoodDiscoveryCandidate,
        filter: MoodDiscoveryFilter,
        tasteProfile: MoodDiscoveryTasteProfile
    ) -> MoodDiscoveryItem? {
        var reasons: [String] = []
        var score = baseScore(for: candidate, tasteProfile: tasteProfile, reasons: &reasons)

        switch filter {
        case .lightEvening:
            guard candidate.kind == .movie || candidate.kind == .series else { return nil }
            let lightGenres = ["Comedy", "Adventure", "Family", "Romance", "Animation"]
            if matchesAnyGenre(candidate, lightGenres) {
                score += 30
                reasons.append("light evening mood")
            } else if let runtime = candidate.runtimeMinutes, runtime <= 120 {
                score += 18
                reasons.append("easy runtime")
            } else {
                return nil
            }
        case .epic:
            guard candidate.hasUltraHDOrHDR || (candidate.runtimeMinutes ?? 0) >= 135 || matchesAnyGenre(candidate, ["Sci-Fi", "Fantasy", "Adventure", "Action"]) else { return nil }
            score += 34
            reasons.append("epic scale")
        case .shortMovie:
            guard candidate.kind == .movie, let runtime = candidate.runtimeMinutes, runtime <= 100 else { return nil }
            score += 30
            reasons.append("short movie")
        case .backgroundSeries:
            guard candidate.kind == .series else { return nil }
            score += 30
            reasons.append("series on the background")
            if matchesAnyGenre(candidate, ["Comedy", "Drama"]) {
                score += 8
            }
        case .highRated:
            guard let rating = candidate.ratingScore, rating >= 8.0 else { return nil }
            score += rating * 5
            reasons.append(String(format: "TMDB %.1f", rating))
        case .new:
            guard candidate.year >= 2023 else { return nil }
            score += 26
            reasons.append("new release")
        case .fourKHDR:
            guard candidate.hasUltraHDOrHDR else { return nil }
            score += 34
            reasons.append("4K/HDR available")
        case .drama:
            guard matchesAnyGenre(candidate, ["Drama"]) else { return nil }
            score += 28
            reasons.append("Drama")
        case .action:
            guard matchesAnyGenre(candidate, ["Action"]) else { return nil }
            score += 28
            reasons.append("Action")
        case .comedy:
            guard matchesAnyGenre(candidate, ["Comedy"]) else { return nil }
            score += 28
            reasons.append("Comedy")
        case .runtime30To60:
            guard let runtime = candidate.runtimeMinutes, (30...60).contains(runtime) else { return nil }
            score += 32
            reasons.append("30-60 minutes")
        case .under90Minutes:
            guard candidate.kind == .movie, let runtime = candidate.runtimeMinutes, runtime < 90 else { return nil }
            score += 34
            reasons.append("under 90 minutes")
        case .longWeekendPicks:
            guard (candidate.runtimeMinutes ?? 0) >= 130 || candidate.kind == .series else { return nil }
            score += 28
            reasons.append("long weekend pick")
        }

        return MoodDiscoveryItem(candidate: candidate, reasons: reasons, score: score)
    }

    private func baseScore(
        for candidate: MoodDiscoveryCandidate,
        tasteProfile: MoodDiscoveryTasteProfile,
        reasons: inout [String]
    ) -> Double {
        var score = 100 - Double(candidate.year == 0 ? 40 : max(0, 2026 - candidate.year)) * 0.35
        if candidate.source == .library || tasteProfile.libraryIDs.contains(candidate.id) {
            score += 22
            reasons.append("from your library")
        }
        if tasteProfile.continueWatchingIDs.contains(candidate.id) {
            score += 10
            reasons.append("continue-friendly")
        }
        let matchedGenres = candidate.genres.filter { genre in
            tasteProfile.preferredGenres.contains { $0.caseInsensitiveCompare(genre) == .orderedSame }
        }
        if let firstGenre = matchedGenres.first {
            score += 16
            reasons.append("matches your taste: \(firstGenre)")
        }
        if let rating = candidate.ratingScore {
            score += rating
        }
        return score
    }

    private func matchesAnyGenre(_ candidate: MoodDiscoveryCandidate, _ genres: [String]) -> Bool {
        candidate.genres.contains { candidateGenre in
            genres.contains { $0.caseInsensitiveCompare(candidateGenre) == .orderedSame }
        }
    }
}

private extension MoodDiscoveryItem {
    init(candidate: MoodDiscoveryCandidate, reasons: [String], score: Double) {
        self.init(
            id: candidate.id,
            title: candidate.title,
            kind: candidate.kind,
            year: candidate.year,
            qualityLabel: candidate.qualityLabel,
            artworkURL: candidate.artworkURL,
            reasons: reasons,
            score: score
        )
    }
}

public enum MoodDiscoveryCandidateBuilder {
    public static func candidates(seedItems: [HomeSeedItem], libraryItems: [MediaItem]) -> [MoodDiscoveryCandidate] {
        var candidatesByID = Dictionary(uniqueKeysWithValues: seedItems.map { ($0.id, MoodDiscoveryCandidate(seedItem: $0)) })
        for libraryItem in libraryItems {
            candidatesByID[libraryItem.id] = MoodDiscoveryCandidate(mediaItem: libraryItem)
        }
        return Array(candidatesByID.values)
    }
}
