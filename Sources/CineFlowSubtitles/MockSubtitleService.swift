import CineFlowCore
import Foundation

public struct MockSubtitleService: SubtitleServiceProtocol {
    public init() {}

    public func preferredSubtitles(for item: MediaItem) async throws -> [SubtitleTrack] {
        [
            SubtitleTrack(id: "\(item.id):ru", languageCode: "ru", displayName: "Russian", source: .embedded),
            SubtitleTrack(id: "\(item.id):en", languageCode: "en", displayName: "English", source: .openSubtitles)
        ]
    }
}
