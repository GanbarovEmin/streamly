import CineFlowCore
import Foundation

public struct DetailHeroBadge: Equatable, Sendable {
    public let title: String

    public init(title: String) {
        self.title = title
    }
}

public struct DetailReleaseHighlight: Equatable, Sendable {
    public let releaseID: String
    public let title: String
    public let badge: String
    public let primaryMetadata: String
    public let secondaryMetadata: String
    public let scopeLabel: String?

    public init(
        releaseID: String,
        title: String,
        badge: String,
        primaryMetadata: String,
        secondaryMetadata: String,
        scopeLabel: String? = nil
    ) {
        self.releaseID = releaseID
        self.title = title
        self.badge = badge
        self.primaryMetadata = primaryMetadata
        self.secondaryMetadata = secondaryMetadata
        self.scopeLabel = scopeLabel
    }
}

public struct SeriesEpisodePresentation: Equatable, Sendable {
    public let label: String
    public let title: String
    public let progressFraction: Double?

    public init(label: String, title: String, progressFraction: Double?) {
        self.label = label
        self.title = title
        self.progressFraction = progressFraction
    }
}

extension HDRFormat {
    var displayLabel: String {
        switch self {
        case .dolbyVision:
            "Dolby Vision"
        case .hdr10:
            "HDR10"
        case .none:
            "SDR"
        case .unknown:
            "HDR n/a"
        }
    }
}

extension TorrentRelease {
    var compactSizeLabel: String {
        guard let sizeBytes else { return "size n/a" }
        let bytes = Double(sizeBytes)
        if bytes >= 1_000_000_000_000 {
            return Self.compactSize(bytes / 1_000_000_000_000, unit: "TB")
        }
        if bytes >= 1_000_000_000 {
            return Self.compactSize(bytes / 1_000_000_000, unit: "GB")
        }
        if bytes >= 1_000_000 {
            return Self.compactSize(bytes / 1_000_000, unit: "MB")
        }
        return "\(sizeBytes) B"
    }

    private static func compactSize(_ value: Double, unit: String) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded)) \(unit)"
        }
        return String(format: "%.1f %@", rounded, unit)
    }
}
