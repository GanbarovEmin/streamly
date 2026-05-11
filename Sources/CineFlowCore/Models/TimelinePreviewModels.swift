import Foundation

public enum TimelinePreviewSource: String, Codable, Equatable, Sendable {
    case cache
    case generated
}

public struct TimelinePreviewRequest: Codable, Equatable, Sendable {
    public let mediaID: String
    public let mediaURL: URL
    public let timeSeconds: Double
    public let durationSeconds: Double?
    public let bufferedUntilSeconds: Double?
    public let isPlaybackActive: Bool
    public let width: Int
    public let height: Int

    public init(
        mediaID: String,
        mediaURL: URL,
        timeSeconds: Double,
        durationSeconds: Double? = nil,
        bufferedUntilSeconds: Double? = nil,
        isPlaybackActive: Bool,
        width: Int = 240,
        height: Int = 135
    ) {
        self.mediaID = mediaID
        self.mediaURL = mediaURL
        self.timeSeconds = max(0, timeSeconds)
        self.durationSeconds = durationSeconds.map { max(0, $0) }
        self.bufferedUntilSeconds = bufferedUntilSeconds.map { max(0, $0) }
        self.isPlaybackActive = isPlaybackActive
        self.width = max(80, width)
        self.height = max(45, height)
    }

    public var roundedTimeSeconds: Double {
        floor(timeSeconds / 10) * 10
    }

    public var isTimeAvailable: Bool {
        mediaURL.isFileURL || bufferedUntilSeconds.map { timeSeconds <= $0 } == true
    }
}

public struct TimelinePreview: Codable, Equatable, Sendable {
    public let mediaID: String
    public let timeSeconds: Double
    public let imageData: Data
    public let contentType: String
    public let source: TimelinePreviewSource
    public let cacheURL: URL?

    public init(
        mediaID: String,
        timeSeconds: Double,
        imageData: Data,
        contentType: String = "image/jpeg",
        source: TimelinePreviewSource,
        cacheURL: URL? = nil
    ) {
        self.mediaID = mediaID
        self.timeSeconds = max(0, timeSeconds)
        self.imageData = imageData
        self.contentType = contentType
        self.source = source
        self.cacheURL = cacheURL
    }
}
