import Foundation

public enum ReleaseFallbackReason: String, Codable, Equatable, Sendable {
    case failedToStart
    case noSeeders
    case stalled
    case unsupportedFile
    case missingMediaFile

    public var userFacingSummary: String {
        switch self {
        case .failedToStart:
            "Selected release did not start."
        case .noSeeders:
            "Selected release has no seeders."
        case .stalled:
            "Stream stalled."
        case .unsupportedFile:
            "Selected file is not supported."
        case .missingMediaFile:
            "Torrent does not contain a playable media file."
        }
    }
}

public struct ReleaseFallbackSuggestion: Equatable, Sendable {
    public let selectedRelease: TorrentRelease
    public let reason: ReleaseFallbackReason
    public let candidates: [RankedRelease]

    public init(
        selectedRelease: TorrentRelease,
        reason: ReleaseFallbackReason,
        candidates: [RankedRelease]
    ) {
        self.selectedRelease = selectedRelease
        self.reason = reason
        self.candidates = candidates
    }

    public var nextBestRelease: RankedRelease? {
        candidates.first
    }
}

public enum ReleaseFallbackPlanner {
    public static func suggestion(
        for selectedRelease: TorrentRelease,
        in releases: [TorrentRelease],
        reason: ReleaseFallbackReason,
        preferences: RankingPreferences = RankingPreferences()
    ) -> ReleaseFallbackSuggestion? {
        let candidates = ReleaseRankingEngine(preferences: preferences)
            .rank(releases.filter { $0.id != selectedRelease.id })

        guard !candidates.isEmpty else { return nil }
        return ReleaseFallbackSuggestion(
            selectedRelease: selectedRelease,
            reason: reason,
            candidates: candidates
        )
    }

    public static func seedWarning(
        for selectedRelease: TorrentRelease,
        in releases: [TorrentRelease],
        preferences: RankingPreferences = RankingPreferences()
    ) -> ReleaseFallbackSuggestion? {
        guard selectedRelease.releaseHealth == .noSeeders else { return nil }
        return suggestion(
            for: selectedRelease,
            in: releases,
            reason: .noSeeders,
            preferences: preferences
        )
    }
}

public struct TorrentMediaFileSelection: Equatable, Sendable {
    public let selectedFile: TorrentFile
    public let manualOptions: [TorrentMediaFileOption]

    public init(selectedFile: TorrentFile, manualOptions: [TorrentMediaFileOption]) {
        self.selectedFile = selectedFile
        self.manualOptions = manualOptions
    }
}

public struct TorrentMediaFileOption: Identifiable, Equatable, Sendable {
    public let file: TorrentFile
    public let confidence: Double

    public var id: String { file.id }

    public init(file: TorrentFile, confidence: Double) {
        self.file = file
        self.confidence = confidence
    }
}

public enum TorrentMediaFileSelector {
    public static func selection(for release: TorrentRelease, files: [TorrentFile]) -> TorrentMediaFileSelection? {
        let candidates = files
            .filter(\.isMediaFile)
            .filter { !isLikelySample($0) }
            .map { TorrentMediaFileOption(file: $0, confidence: confidence(for: $0)) }
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                if lhs.file.lengthBytes != rhs.file.lengthBytes {
                    return lhs.file.lengthBytes > rhs.file.lengthBytes
                }
                return lhs.file.id < rhs.file.id
            }

        guard !candidates.isEmpty else { return nil }

        if let preferredFileIndex = release.preferredFileIndex,
           let preferred = candidates.first(where: { Int($0.file.id) == preferredFileIndex }) {
            return TorrentMediaFileSelection(selectedFile: preferred.file, manualOptions: candidates)
        }

        return TorrentMediaFileSelection(selectedFile: candidates[0].file, manualOptions: candidates)
    }

    private static func confidence(for file: TorrentFile) -> Double {
        let sizeGB = Double(file.lengthBytes) / 1_000_000_000
        var score = min(sizeGB, 25)
        let lowercasedName = file.name.lowercased()
        if lowercasedName.contains("sample") || lowercasedName.contains("trailer") {
            score -= 50
        }
        if lowercasedName.contains("extras") || lowercasedName.contains("featurette") {
            score -= 20
        }
        return score
    }

    private static func isLikelySample(_ file: TorrentFile) -> Bool {
        let haystack = "\(file.path)/\(file.name)".lowercased()
        if haystack.contains("sample") || haystack.contains("trailer") {
            return true
        }
        return file.lengthBytes < 250_000_000
    }
}
