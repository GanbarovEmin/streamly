import Foundation

public enum MetadataMatchReason: Equatable, Sendable {
    case exactTitle
    case originalTitle
    case alternativeTitle
    case fuzzyTitle
    case yearMatch
    case yearMismatch(expected: Int, actual: Int?)
    case mediaTypeMatch
}

public struct MetadataMatchCandidate: Equatable, Sendable {
    public let item: MediaItem
    public let confidence: Double
    public let reasons: [MetadataMatchReason]

    public init(item: MediaItem, confidence: Double, reasons: [MetadataMatchReason]) {
        self.item = item
        self.confidence = min(max(confidence, 0), 1)
        self.reasons = reasons
    }
}

public struct MetadataArtworkCandidate: Codable, Equatable, Sendable {
    public let url: URL
    public let languageCode: String?
    public let score: Double

    public init(url: URL, languageCode: String? = nil, score: Double = 0) {
        self.url = url
        self.languageCode = languageCode
        self.score = score
    }
}

public struct SelectedMetadataArtwork: Equatable, Sendable {
    public let posterURL: URL?
    public let backdropURL: URL?
    public let usesBackdropFallback: Bool
    public let usesNoImagePlaceholder: Bool

    public init(
        posterURL: URL?,
        backdropURL: URL?,
        usesBackdropFallback: Bool,
        usesNoImagePlaceholder: Bool
    ) {
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.usesBackdropFallback = usesBackdropFallback
        self.usesNoImagePlaceholder = usesNoImagePlaceholder
    }
}

public enum MetadataArtworkSelector {
    public static func select(
        posters: [MetadataArtworkCandidate],
        backdrops: [MetadataArtworkCandidate],
        preferredLanguageCodes: [String]
    ) -> SelectedMetadataArtwork {
        let poster = bestCandidate(posters, preferredLanguageCodes: preferredLanguageCodes)
        let backdrop = bestCandidate(backdrops, preferredLanguageCodes: preferredLanguageCodes)
        let resolvedBackdrop = backdrop ?? poster

        return SelectedMetadataArtwork(
            posterURL: poster?.url,
            backdropURL: resolvedBackdrop?.url,
            usesBackdropFallback: backdrop == nil && poster != nil,
            usesNoImagePlaceholder: poster == nil && resolvedBackdrop == nil
        )
    }

    private static func bestCandidate(
        _ candidates: [MetadataArtworkCandidate],
        preferredLanguageCodes: [String]
    ) -> MetadataArtworkCandidate? {
        let normalizedPreferences = preferredLanguageCodes.map { $0.lowercased() }
        return candidates.max { lhs, rhs in
            let lhsScore = rankingScore(lhs, preferredLanguageCodes: normalizedPreferences)
            let rhsScore = rankingScore(rhs, preferredLanguageCodes: normalizedPreferences)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return lhs.url.absoluteString < rhs.url.absoluteString
        }
    }

    private static func rankingScore(
        _ candidate: MetadataArtworkCandidate,
        preferredLanguageCodes: [String]
    ) -> Double {
        let languageScore: Double
        if let languageCode = candidate.languageCode?.lowercased(),
           let index = preferredLanguageCodes.firstIndex(of: languageCode) {
            languageScore = 10 - Double(index)
        } else if candidate.languageCode == nil {
            languageScore = 1
        } else {
            languageScore = 0
        }
        return languageScore + candidate.score
    }
}

public protocol MetadataCacheControlProtocol {
    func refreshMetadata(for mediaID: String) async throws
    func clearMetadataCache(for mediaID: String) async throws
}
