import Foundation

public enum ReleaseQuality: Int, Codable, Comparable, Hashable, Sendable {
    case unknown = 0
    case standardDefinition = 1
    case hd = 2
    case fullHD = 3
    case ultraHD = 4

    public static func < (lhs: ReleaseQuality, rhs: ReleaseQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var qualityLabel: String {
        switch self {
        case .unknown:
            "Unknown"
        case .standardDefinition:
            "SD"
        case .hd:
            "720p"
        case .fullHD:
            "1080p"
        case .ultraHD:
            "2160p"
        }
    }
}

public enum VideoCodec: String, Codable, Equatable, Hashable, Sendable {
    case h264 = "H264"
    case h265 = "H265"
    case hevc = "HEVC"
    case av1 = "AV1"
    case mpeg4 = "MPEG4"
    case unknown
}

public enum HDRFormat: String, Codable, Equatable, Hashable, Sendable {
    case none
    case hdr10 = "HDR10"
    case dolbyVision = "DolbyVision"
    case unknown
}

public enum ReleaseHealth: String, Codable, Equatable, Hashable, Sendable {
    case excellent
    case good
    case weak
    case noSeeders
    case unknown

    public var healthScore: Double {
        switch self {
        case .excellent:
            900
        case .good:
            420
        case .weak:
            -450
        case .noSeeders:
            -2_400
        case .unknown:
            -150
        }
    }

    public var label: String {
        switch self {
        case .excellent:
            "Excellent"
        case .good:
            "Good"
        case .weak:
            "Weak"
        case .noSeeders:
            "No Seeders"
        case .unknown:
            "Unknown"
        }
    }
}

public struct TorrentRelease: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let sourceId: String
    public let sourceName: String
    public let title: String
    public let magnetURI: String?
    public let torrentFileURL: URL?
    public let quality: ReleaseQuality
    public let codec: VideoCodec
    public let hdr: HDRFormat
    public let audioLanguages: [String]
    public let subtitleLanguages: [String]
    public let seeders: Int
    public let leechers: Int
    public let sizeBytes: Int64?
    public let uploadDate: Date?
    public let trustedUploader: Bool?
    public let rankScore: Double
    public let preferredFileIndex: Int?
    public let availability: Double?

    public init(
        id: String,
        sourceId: String = "mock",
        sourceName: String = "Mock Source",
        title: String,
        magnetURI: String? = nil,
        torrentFileURL: URL? = nil,
        quality: ReleaseQuality,
        codec: VideoCodec = .unknown,
        hdr: HDRFormat = .unknown,
        audioLanguages: [String] = [],
        subtitleLanguages: [String] = [],
        seeders: Int,
        leechers: Int = 0,
        sizeBytes: Int64? = nil,
        uploadDate: Date? = nil,
        trustedUploader: Bool? = nil,
        preferredFileIndex: Int? = nil,
        availability: Double? = nil,
        rankScore: Double? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.sourceName = sourceName
        self.title = title
        self.magnetURI = magnetURI
        self.torrentFileURL = torrentFileURL
        self.quality = quality
        self.codec = codec
        self.hdr = hdr
        self.audioLanguages = audioLanguages
        self.subtitleLanguages = subtitleLanguages
        self.seeders = seeders
        self.leechers = leechers
        self.sizeBytes = sizeBytes
        self.uploadDate = uploadDate
        self.trustedUploader = trustedUploader
        self.preferredFileIndex = preferredFileIndex
        self.availability = availability
        self.rankScore = rankScore ?? Self.defaultRankScore(quality: quality, seeders: seeders, trustedUploader: trustedUploader)
    }

    public var qualityLabel: String {
        quality.qualityLabel
    }

    public var humanReadableSize: String {
        guard let sizeBytes else { return "Unknown size" }
        let units: [(label: String, value: Double)] = [
            ("TB", 1_000_000_000_000),
            ("GB", 1_000_000_000),
            ("MB", 1_000_000)
        ]
        let bytes = Double(sizeBytes)
        guard let unit = units.first(where: { bytes >= $0.value }) else {
            return "\(sizeBytes) B"
        }

        let value = bytes / unit.value
        return "\(String(format: "%.2f", value)) \(unit.label)"
    }

    public var releaseHealth: ReleaseHealth {
        guard seeders >= 0 else { return .unknown }
        if seeders == 0 { return .noSeeders }

        let availabilityValue = availability ?? (seeders > 0 ? 1 : 0)
        if seeders >= 80 && availabilityValue >= 1 {
            return .excellent
        }
        if seeders >= 25 || availabilityValue >= 0.6 {
            return .good
        }
        return .weak
    }

    private static func defaultRankScore(quality: ReleaseQuality, seeders: Int, trustedUploader: Bool?) -> Double {
        let trustBoost = trustedUploader == true ? 25.0 : 0.0
        return Double(quality.rawValue * 1_000) + Double(seeders) + trustBoost
    }
}

public extension Sequence where Element == TorrentRelease {
    func sortedByCineFlowRank() -> [TorrentRelease] {
        ReleaseRankingEngine()
            .rank(Array(self))
            .map(\.release)
    }
}
