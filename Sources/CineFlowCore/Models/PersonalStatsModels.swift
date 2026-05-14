import Foundation

public struct PersonalStatsRankedItem: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let count: Int

    public var id: String { name }

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct PersonalBingeSession: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let endedAt: Date
    public let durationSeconds: Double
    public let itemCount: Int

    public init(startedAt: Date, endedAt: Date, durationSeconds: Double, itemCount: Int) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.itemCount = itemCount
    }
}

public enum YearRecapStatus: String, Codable, Equatable, Sendable {
    case collectingSignals
    case readyLater
}

public struct PersonalWatchStats: Codable, Equatable, Sendable {
    public let watchedMoviesCount: Int
    public let watchedEpisodesCount: Int
    public let monthlyWatchTimeSeconds: Double
    public let completionRate: Double
    public let longestBingeSession: PersonalBingeSession?
    public let favoriteGenres: [PersonalStatsRankedItem]
    public let favoriteActors: [PersonalStatsRankedItem]
    public let yearRecapStatus: YearRecapStatus
    public let sharesPrivateAnalytics: Bool

    public init(
        watchedMoviesCount: Int = 0,
        watchedEpisodesCount: Int = 0,
        monthlyWatchTimeSeconds: Double = 0,
        completionRate: Double = 0,
        longestBingeSession: PersonalBingeSession? = nil,
        favoriteGenres: [PersonalStatsRankedItem] = [],
        favoriteActors: [PersonalStatsRankedItem] = [],
        yearRecapStatus: YearRecapStatus = .collectingSignals,
        sharesPrivateAnalytics: Bool = false
    ) {
        self.watchedMoviesCount = watchedMoviesCount
        self.watchedEpisodesCount = watchedEpisodesCount
        self.monthlyWatchTimeSeconds = monthlyWatchTimeSeconds
        self.completionRate = min(max(completionRate, 0), 1)
        self.longestBingeSession = longestBingeSession
        self.favoriteGenres = favoriteGenres
        self.favoriteActors = favoriteActors
        self.yearRecapStatus = yearRecapStatus
        self.sharesPrivateAnalytics = sharesPrivateAnalytics
    }

    public static let empty = PersonalWatchStats()
}

public protocol PersonalStatsServiceProtocol {
    func personalStats(referenceDate: Date) async throws -> PersonalWatchStats
}
