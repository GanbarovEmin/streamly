import Foundation

public struct RankingPreferences: Equatable, Sendable {
    public let preferredAudioLanguages: [String]
    public let preferredSubtitleLanguages: [String]
    public let supportsHDR: Bool

    public init(
        preferredAudioLanguages: [String] = [],
        preferredSubtitleLanguages: [String] = [],
        supportsHDR: Bool = false
    ) {
        self.preferredAudioLanguages = preferredAudioLanguages.map { $0.lowercased() }
        self.preferredSubtitleLanguages = preferredSubtitleLanguages.map { $0.lowercased() }
        self.supportsHDR = supportsHDR
    }
}

public enum ReleaseRankingReason: Equatable, Sendable {
    case quality(ReleaseQuality)
    case seeders(Int)
    case hdr(HDRFormat)
    case codec(VideoCodec)
    case preferredAudioLanguage(String)
    case preferredSubtitleLanguage(String)
    case trustedUploader
    case suspiciousSmallSize
    case unknownQualityPenalty

    public var explanation: String {
        switch self {
        case .quality(let quality):
            "Quality: \(quality.qualityLabel)"
        case .seeders(let seeders):
            "Seeders: \(seeders)"
        case .hdr(let hdr):
            "HDR: \(hdr.rawValue)"
        case .codec(let codec):
            "Codec: \(codec.rawValue)"
        case .preferredAudioLanguage(let language):
            "Preferred audio: \(language)"
        case .preferredSubtitleLanguage(let language):
            "Preferred subtitles: \(language)"
        case .trustedUploader:
            "Trusted uploader"
        case .suspiciousSmallSize:
            "Suspiciously small size penalty"
        case .unknownQualityPenalty:
            "Unknown quality penalty"
        }
    }
}

public struct RankedRelease: Equatable, Sendable {
    public let release: TorrentRelease
    public let score: Double
    public let reasons: [ReleaseRankingReason]

    public init(release: TorrentRelease, score: Double, reasons: [ReleaseRankingReason]) {
        self.release = release
        self.score = score
        self.reasons = reasons
    }

    public var explanation: String {
        reasons.map(\.explanation).joined(separator: "\n")
    }
}

public struct ReleaseRankingEngine: Sendable {
    private let preferences: RankingPreferences

    public init(preferences: RankingPreferences = RankingPreferences()) {
        self.preferences = preferences
    }

    public func rank(_ releases: [TorrentRelease]) -> [RankedRelease] {
        releases
            .map(score)
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                return lhs.release.id < rhs.release.id
            }
    }

    public func score(_ release: TorrentRelease) -> RankedRelease {
        var score = 0.0
        var reasons: [ReleaseRankingReason] = []

        score += qualityScore(release.quality)
        reasons.append(.quality(release.quality))

        if release.quality == .unknown {
            score -= 600
            reasons.append(.unknownQualityPenalty)
        }

        score += min(Double(release.seeders), 2_000) * 2.0
        reasons.append(.seeders(release.seeders))

        let hdrScore = scoreForHDR(release.hdr)
        if hdrScore > 0 {
            score += hdrScore
            reasons.append(.hdr(release.hdr))
        }

        let codecScore = scoreForCodec(release.codec)
        if codecScore > 0 {
            score += codecScore
            reasons.append(.codec(release.codec))
        }

        for language in preferences.preferredAudioLanguages where release.matchesAudioLanguage(language) {
            score += 350
            reasons.append(.preferredAudioLanguage(language))
            break
        }

        for language in preferences.preferredSubtitleLanguages where release.matchesSubtitleLanguage(language) {
            score += 180
            reasons.append(.preferredSubtitleLanguage(language))
            break
        }

        if release.trustedUploader == true {
            score += 220
            reasons.append(.trustedUploader)
        }

        if isSuspiciouslySmall(release) {
            score -= 900
            reasons.append(.suspiciousSmallSize)
        }

        return RankedRelease(release: release, score: score, reasons: reasons)
    }

    private func qualityScore(_ quality: ReleaseQuality) -> Double {
        switch quality {
        case .ultraHD:
            20_000
        case .fullHD:
            10_000
        case .hd:
            5_000
        case .standardDefinition:
            2_000
        case .unknown:
            0
        }
    }

    private func scoreForHDR(_ hdr: HDRFormat) -> Double {
        guard preferences.supportsHDR else { return 0 }

        return switch hdr {
        case .dolbyVision:
            900
        case .hdr10:
            650
        case .none, .unknown:
            0
        }
    }

    private func scoreForCodec(_ codec: VideoCodec) -> Double {
        switch codec {
        case .hevc, .h265:
            180
        case .av1:
            160
        case .h264:
            80
        case .mpeg4, .unknown:
            0
        }
    }

    private func isSuspiciouslySmall(_ release: TorrentRelease) -> Bool {
        guard let sizeBytes = release.sizeBytes else { return false }
        let sizeGB = Double(sizeBytes) / 1_000_000_000

        switch release.quality {
        case .ultraHD:
            return sizeGB < 8
        case .fullHD:
            return sizeGB < 2
        case .hd:
            return sizeGB < 0.8
        case .standardDefinition:
            return sizeGB < 0.35
        case .unknown:
            return sizeGB < 0.5
        }
    }
}

private extension TorrentRelease {
    func matchesAudioLanguage(_ language: String) -> Bool {
        audioLanguages.map { $0.lowercased() }.contains(language)
    }

    func matchesSubtitleLanguage(_ language: String) -> Bool {
        subtitleLanguages.map { $0.lowercased() }.contains(language)
    }
}
