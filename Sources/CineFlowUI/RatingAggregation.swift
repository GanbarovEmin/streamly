import Foundation

public enum RatingSource: String, Equatable, Sendable {
    case tmdb
    case imdb
    case trakt
    case user
}

public struct RatingSourceValue: Identifiable, Equatable, Sendable {
    public let source: RatingSource
    public let value: Double
    public let label: String

    public var id: RatingSource { source }

    public init(source: RatingSource, value: Double, label: String) {
        self.source = source
        self.value = value
        self.label = label
    }
}

public enum RatingBadgeKind: String, Equatable, Sendable {
    case highlyRated
    case mixed
    case new
    case classic
}

public struct RatingQualityBadge: Identifiable, Equatable, Sendable {
    public let kind: RatingBadgeKind
    public let title: String

    public var id: RatingBadgeKind { kind }

    public init(kind: RatingBadgeKind, title: String) {
        self.kind = kind
        self.title = title
    }
}

public struct RatingSummary: Equatable, Sendable {
    public let sources: [RatingSourceValue]
    public let badges: [RatingQualityBadge]

    public init(sources: [RatingSourceValue], badges: [RatingQualityBadge]) {
        self.sources = sources
        self.badges = badges
    }

    public static let empty = RatingSummary(sources: [], badges: [])
}

public enum RatingAggregator {
    public static func summary(
        tmdbRating: String?,
        imdbRating: String? = nil,
        traktRating: String? = nil,
        userRating: Int? = nil,
        year: Int? = nil,
        currentYear: Int = Calendar.current.component(.year, from: Date())
    ) -> RatingSummary {
        var sources: [RatingSourceValue] = []
        if let value = parseRating(tmdbRating) {
            sources.append(RatingSourceValue(source: .tmdb, value: value, label: String(format: "TMDB %.1f", value)))
        }
        if let value = parseRating(imdbRating) {
            sources.append(RatingSourceValue(source: .imdb, value: value, label: String(format: "IMDb %.1f", value)))
        }
        if let value = parseRating(traktRating) {
            sources.append(RatingSourceValue(source: .trakt, value: value, label: String(format: "Trakt %.1f", value)))
        }
        if let userRating {
            let bounded = min(max(userRating, 1), 10)
            sources.append(RatingSourceValue(source: .user, value: Double(bounded), label: "You \(bounded)/10"))
        }

        let providerRatings = sources
            .filter { $0.source != .user }
            .map(\.value)
        let representativeRating = providerRatings.max() ?? userRating.map(Double.init)
        let badges = qualityBadges(rating: representativeRating, year: year, currentYear: currentYear)
        return RatingSummary(sources: sources, badges: badges)
    }

    public static func parseRating(_ rawValue: String?) -> Double? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.localizedCaseInsensitiveCompare("N/A") != .orderedSame else { return nil }

        let numeric = trimmed
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: " ")
            .compactMap { Double($0) }
            .first
        return numeric.flatMap { value in
            guard value.isFinite, value > 0 else { return nil }
            return min(value, 10)
        }
    }

    private static func qualityBadges(rating: Double?, year: Int?, currentYear: Int) -> [RatingQualityBadge] {
        var badges: [RatingQualityBadge] = []
        if let rating {
            if rating >= 8.0 {
                badges.append(RatingQualityBadge(kind: .highlyRated, title: "Highly Rated"))
            } else if rating < 6.5 {
                badges.append(RatingQualityBadge(kind: .mixed, title: "Mixed"))
            }
        }

        if let year, year > 0 {
            let age = currentYear - year
            if age <= 1 {
                badges.append(RatingQualityBadge(kind: .new, title: "New"))
            } else if age >= 25, (rating ?? 0) >= 7.5 {
                badges.append(RatingQualityBadge(kind: .classic, title: "Classic"))
            }
        }

        return badges
    }
}
