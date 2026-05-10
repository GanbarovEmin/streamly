import Foundation

public enum PlaybackState: Equatable, Sendable {
    case idle
    case preparing
    case playing(TorrentRelease)
    case paused(TorrentRelease)
    case failed(String)
}
