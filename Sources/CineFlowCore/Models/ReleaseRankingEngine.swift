import Foundation

public struct RankingPreferences: Equatable, Sendable {
    public let preferredAudioLanguages: [String]
    public let preferredSubtitleLanguages: [String]
    public let supportsHDR: Bool
    public let preferredQuality: PreferredQuality
    public let hdrPreference: HDRPreference
    public let codecPreference: CodecPreference
    public let maxFileSizeBytes: Int64?
    public let preferHighSeedersOverHighestQuality: Bool

    public init(
        preferredAudioLanguages: [String] = [],
        preferredSubtitleLanguages: [String] = [],
        supportsHDR: Bool = false,
        preferredQuality: PreferredQuality = .auto,
        hdrPreference: HDRPreference = .auto,
        codecPreference: CodecPreference = .auto,
        maxFileSizeBytes: Int64? = nil,
        preferHighSeedersOverHighestQuality: Bool = false
    ) {
        self.preferredAudioLanguages = preferredAudioLanguages.map { $0.lowercased() }
        self.preferredSubtitleLanguages = preferredSubtitleLanguages.map { $0.lowercased() }
        self.supportsHDR = supportsHDR
        self.preferredQuality = preferredQuality
        self.hdrPreference = hdrPreference
        self.codecPreference = codecPreference
        self.maxFileSizeBytes = maxFileSizeBytes.map { max(0, $0) }
        self.preferHighSeedersOverHighestQuality = preferHighSeedersOverHighestQuality
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
    case releaseHealth(ReleaseHealth)
    case preferredQuality(PreferredQuality)
    case maxFileSizeLimit(Int64)
    case hdrPreference(HDRPreference)
    case codecPreference(CodecPreference)
    case highSeedersPreference
    case fitsSizePreference(Int64)
    case startupRiskPenalty

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
        case .releaseHealth(let health):
            "Health: \(health.label)"
        case .preferredQuality(let quality):
            "Preferred quality: \(quality.title)"
        case .maxFileSizeLimit(let bytes):
            "Max file size: \(bytes) bytes"
        case .hdrPreference(let preference):
            "HDR preference: \(preference.title)"
        case .codecPreference(let preference):
            "Codec preference: \(preference.title)"
        case .highSeedersPreference:
            "Prefer high seeders"
        case .fitsSizePreference(let bytes):
            "Fits max file size: \(bytes) bytes"
        case .startupRiskPenalty:
            "Startup risk: large low-seeded release"
        }
    }
}

public enum ReleaseRankingLabel: String, Codable, CaseIterable, Equatable, Sendable {
    case best
    case fastest
    case smallest
    case bestRussianAudio
    case best4K

    public var title: String {
        switch self {
        case .best:
            "Best"
        case .fastest:
            "Fastest"
        case .smallest:
            "Smallest"
        case .bestRussianAudio:
            "Best Russian Audio"
        case .best4K:
            "Best 4K"
        }
    }
}

public struct RankedRelease: Equatable, Sendable {
    public let release: TorrentRelease
    public let score: Double
    public let reasons: [ReleaseRankingReason]
    public let labels: [ReleaseRankingLabel]

    public init(
        release: TorrentRelease,
        score: Double,
        reasons: [ReleaseRankingReason],
        labels: [ReleaseRankingLabel] = []
    ) {
        self.release = release
        self.score = score
        self.reasons = reasons
        self.labels = labels
    }

    public var explanation: String {
        reasons.map(\.explanation).joined(separator: "\n")
    }

    public var conciseReasons: [String] {
        var values: [String] = []

        appendUnique("best overall match", to: &values, when: labels.contains(.best))
        appendUnique("highest seeders", to: &values, when: labels.contains(.fastest))
        appendUnique("smallest file", to: &values, when: labels.contains(.smallest))

        for reason in reasons {
            switch reason {
            case .quality(.ultraHD):
                appendUnique("4K quality", to: &values)
            case .quality(.fullHD):
                appendUnique("1080p quality", to: &values)
            case .quality(.hd):
                appendUnique("720p quality", to: &values)
            case .hdr(let hdr) where hdr != .none && hdr != .unknown:
                appendUnique("HDR", to: &values)
            case .hdrPreference(.preferHDR):
                appendUnique("HDR", to: &values)
            case .codec(.hevc), .codec(.h265), .codecPreference(.preferHEVC):
                appendUnique("HEVC codec", to: &values)
            case .preferredAudioLanguage(let language) where Self.isRussian(language):
                appendUnique("Russian audio", to: &values)
            case .preferredAudioLanguage(let language):
                appendUnique("\(language.uppercased()) audio", to: &values)
            case .preferredSubtitleLanguage(let language) where Self.isEnglish(language):
                appendUnique("English subtitles", to: &values)
            case .preferredSubtitleLanguage(let language):
                appendUnique("\(language.uppercased()) subtitles", to: &values)
            case .trustedUploader:
                appendUnique("trusted source", to: &values)
            case .releaseHealth(.excellent), .releaseHealth(.good):
                appendUnique("healthy release", to: &values)
            case .fitsSizePreference:
                appendUnique("fits size preference", to: &values)
            default:
                break
            }
        }

        return Array(values.prefix(9))
    }

    public var tooltipExplanation: String {
        let reasons = conciseReasons
        guard !reasons.isEmpty else {
            return "Why this release\nScore: \(Int(score.rounded()))"
        }
        return "Why this release\n" + reasons.map { "• \($0)" }.joined(separator: "\n")
    }

    public var advancedDetails: [String] {
        var details = [
            "Score: \(Int(score.rounded()))",
            "Source: \(release.sourceName)",
            "Quality: \(release.qualityLabel)",
            "Seeders: \(release.seeders)",
            "Size: \(release.humanReadableSize)"
        ]

        if release.hdr != .none, release.hdr != .unknown {
            details.append("HDR: \(release.hdr.rawValue)")
        }
        if release.codec != .unknown {
            details.append("Codec: \(release.codec.rawValue)")
        }
        if !release.audioLanguages.isEmpty {
            details.append("Audio: \(release.audioLanguages.joined(separator: ", "))")
        }
        if !release.subtitleLanguages.isEmpty {
            details.append("Subtitles: \(release.subtitleLanguages.joined(separator: ", "))")
        }
        details.append("Health: \(release.releaseHealth.label)")
        return details
    }

    public var labelTitles: [String] {
        labels.map(\.title)
    }

    fileprivate func withLabels(_ labels: [ReleaseRankingLabel]) -> RankedRelease {
        RankedRelease(release: release, score: score, reasons: reasons, labels: labels)
    }

    private static func isRussian(_ language: String) -> Bool {
        let normalized = language.lowercased()
        return normalized == "ru" || normalized == "rus" || normalized.contains("russian")
    }

    private static func isEnglish(_ language: String) -> Bool {
        let normalized = language.lowercased()
        return normalized == "en" || normalized == "eng" || normalized.contains("english")
    }

    private func appendUnique(_ value: String, to values: inout [String], when condition: Bool = true) {
        guard condition, !values.contains(value) else { return }
        values.append(value)
    }
}

public struct ReleaseRankingEngine: Sendable {
    private let preferences: RankingPreferences

    public init(preferences: RankingPreferences = RankingPreferences()) {
        self.preferences = preferences
    }

    public func rank(_ releases: [TorrentRelease]) -> [RankedRelease] {
        let ranked = releases
            .map(score)
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                return lhs.release.id < rhs.release.id
            }

        return applyLabels(to: ranked)
    }

    public func score(_ release: TorrentRelease) -> RankedRelease {
        var score = 0.0
        var reasons: [ReleaseRankingReason] = []

        score += qualityScore(release.quality)
        reasons.append(.quality(release.quality))

        let preferredQualityScore = scoreForPreferredQuality(release.quality)
        if preferredQualityScore != 0 {
            score += preferredQualityScore
            reasons.append(.preferredQuality(preferences.preferredQuality))
        }

        if release.quality == .unknown {
            score -= 600
            reasons.append(.unknownQualityPenalty)
        }

        if preferences.preferHighSeedersOverHighestQuality {
            reasons.append(.highSeedersPreference)
        }
        score += min(Double(release.seeders), 2_000) * seedersWeight
        reasons.append(.seeders(release.seeders))

        let releaseHealth = release.releaseHealth
        score += releaseHealth.healthScore
        reasons.append(.releaseHealth(releaseHealth))

        let startupRiskPenalty = scoreForStartupRisk(release)
        if startupRiskPenalty != 0 {
            score += startupRiskPenalty
            reasons.append(.startupRiskPenalty)
        }

        let hdrScore = scoreForHDR(release.hdr)
        if hdrScore != 0 {
            score += hdrScore
            if preferences.hdrPreference == .auto {
                reasons.append(.hdr(release.hdr))
            } else {
                reasons.append(.hdrPreference(preferences.hdrPreference))
            }
        }

        let codecScore = scoreForCodec(release.codec)
        if codecScore != 0 {
            score += codecScore
            if preferences.codecPreference == .auto {
                reasons.append(.codec(release.codec))
            } else {
                reasons.append(.codecPreference(preferences.codecPreference))
            }
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

        if let maxFileSizeBytes = preferences.maxFileSizeBytes,
           let sizeBytes = release.sizeBytes {
            if sizeBytes > maxFileSizeBytes {
                score -= 100_000
                reasons.append(.maxFileSizeLimit(maxFileSizeBytes))
            } else {
                reasons.append(.fitsSizePreference(maxFileSizeBytes))
            }
        }

        return RankedRelease(release: release, score: score, reasons: reasons)
    }

    private func applyLabels(to ranked: [RankedRelease]) -> [RankedRelease] {
        guard !ranked.isEmpty else { return [] }

        let fastestID = ranked.max { lhs, rhs in
            if lhs.release.seeders != rhs.release.seeders {
                return lhs.release.seeders < rhs.release.seeders
            }
            return lhs.score < rhs.score
        }?.release.id
        let smallestID = ranked
            .filter { $0.release.sizeBytes != nil }
            .min { lhs, rhs in
                if lhs.release.sizeBytes != rhs.release.sizeBytes {
                    return (lhs.release.sizeBytes ?? .max) < (rhs.release.sizeBytes ?? .max)
                }
                return lhs.score > rhs.score
            }?.release.id
        let bestRussianAudioID = ranked.first { release in
            release.release.audioLanguages.contains { language in
                let normalized = language.lowercased()
                return normalized == "ru" || normalized == "rus" || normalized.contains("russian")
            }
        }?.release.id
        let best4KID = ranked.first { $0.release.quality == .ultraHD }?.release.id

        return ranked.enumerated().map { index, rankedRelease in
            var labels: [ReleaseRankingLabel] = []
            appendLabel(.best, to: &labels, when: index == 0)
            appendLabel(.fastest, to: &labels, when: rankedRelease.release.id == fastestID)
            appendLabel(.smallest, to: &labels, when: rankedRelease.release.id == smallestID)
            appendLabel(.bestRussianAudio, to: &labels, when: rankedRelease.release.id == bestRussianAudioID)
            appendLabel(.best4K, to: &labels, when: rankedRelease.release.id == best4KID)
            return rankedRelease.withLabels(labels)
        }
    }

    private func appendLabel(_ label: ReleaseRankingLabel, to labels: inout [ReleaseRankingLabel], when condition: Bool) {
        guard condition, !labels.contains(label) else { return }
        labels.append(label)
    }

    private func qualityScore(_ quality: ReleaseQuality) -> Double {
        if preferences.preferHighSeedersOverHighestQuality {
            return switch quality {
            case .ultraHD:
                8_000
            case .fullHD:
                6_500
            case .hd:
                4_500
            case .standardDefinition:
                2_000
            case .unknown:
                0
            }
        }

        return switch quality {
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

    private var seedersWeight: Double {
        preferences.preferHighSeedersOverHighestQuality ? 10.0 : 2.0
    }

    private func scoreForStartupRisk(_ release: TorrentRelease) -> Double {
        guard preferences.preferHighSeedersOverHighestQuality else { return 0 }

        var penalty = 0.0
        if release.quality == .ultraHD, release.seeders < 25 {
            penalty -= 2_200
        }

        guard let sizeBytes = release.sizeBytes else { return penalty }
        let sizeGB = Double(sizeBytes) / 1_000_000_000
        if sizeGB >= 20, release.seeders < 50 {
            penalty -= 1_400
        } else if sizeGB >= 8, release.seeders < 10 {
            penalty -= 900
        }
        return penalty
    }

    private func scoreForPreferredQuality(_ quality: ReleaseQuality) -> Double {
        switch preferences.preferredQuality {
        case .auto:
            return 0
        case .highestAvailable:
            return Double(quality.rawValue) * 1_400
        case .p720, .p1080, .p2160:
            guard let target = preferences.preferredQuality.targetQuality else { return 0 }
            if quality == target {
                return 18_000
            }
            if quality > target {
                return Double(quality.rawValue - target.rawValue) * -14_000
            }
            return Double(target.rawValue - quality.rawValue) * -2_500
        }
    }

    private func scoreForHDR(_ hdr: HDRFormat) -> Double {
        switch preferences.hdrPreference {
        case .preferHDR:
            return hdr == .none || hdr == .unknown ? -300 : 1_200
        case .avoidHDR:
            return hdr == .none || hdr == .unknown ? 400 : -3_500
        case .auto:
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
    }

    private func scoreForCodec(_ codec: VideoCodec) -> Double {
        switch preferences.codecPreference {
        case .preferHEVC:
            return switch codec {
            case .hevc, .h265:
                900
            case .h264:
                80
            case .av1:
                40
            case .mpeg4, .unknown:
                0
            }
        case .avoidUnsupportedAV1:
            return codec == .av1 ? -2_800 : 120
        case .auto:
            return switch codec {
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
