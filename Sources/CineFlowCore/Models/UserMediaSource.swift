import Foundation

public enum UserMediaSourceKind: String, Codable, CaseIterable, Equatable, Sendable {
    case localFile
    case magnet
    case torrentFile
}

public struct UserMediaSource: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let mediaID: String
    public var displayName: String
    public var kind: UserMediaSourceKind
    public var url: URL?
    public var magnetURI: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        mediaID: String,
        displayName: String,
        kind: UserMediaSourceKind,
        url: URL? = nil,
        magnetURI: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.mediaID = mediaID
        self.displayName = displayName
        self.kind = kind
        self.url = url
        self.magnetURI = magnetURI
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isPlayableLocalFile: Bool {
        kind == .localFile && url?.isFileURL == true
    }

    public var playbackMediaSource: PlaybackMediaSource? {
        guard isPlayableLocalFile, let url else { return nil }
        return PlaybackMediaSource(
            id: id,
            title: displayName,
            url: url,
            qualityLabel: nil,
            sourceName: "Local file"
        )
    }
}

public protocol UserMediaSourceRepositoryProtocol {
    func sources(for mediaID: String) async throws -> [UserMediaSource]
    func source(id: String) async throws -> UserMediaSource?
    func save(_ source: UserMediaSource) async throws
    func delete(id: String) async throws
}
