import CineFlowCore
import Foundation

public struct MockMetadataService: MetadataServiceProtocol {
    public init() {}

    public func search(query: String) async throws -> [MediaItem] {
        [
            MediaItem(
                id: "tmdb:movie:603",
                title: "The Matrix",
                kind: .movie,
                overview: "A computer hacker learns about the true nature of his reality.",
                releaseYear: 1999,
                posterPath: nil
            )
        ]
    }
}
