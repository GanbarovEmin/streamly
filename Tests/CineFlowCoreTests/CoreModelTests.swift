import XCTest
@testable import CineFlowCore

final class CoreModelTests: XCTestCase {
    func testMediaItemKeepsCanonicalIdentityAndDisplayFields() {
        let posterURL = URL(string: "https://image.tmdb.org/t/p/w780/poster.jpg")!
        let backdropURL = URL(string: "https://image.tmdb.org/t/p/original/backdrop.jpg")!
        let metadata = MediaMetadata(
            tmdbId: 550,
            imdbId: "tt0137523",
            traktId: 727,
            title: "Fight Club",
            originalTitle: "Fight Club",
            overview: "A placeholder overview",
            year: 1999,
            genres: ["Drama"],
            runtime: 139,
            rating: 8.4,
            posterURL: posterURL,
            backdropURL: backdropURL
        )
        let item = MediaItem(
            id: "tmdb:movie:550",
            title: "Fight Club",
            kind: .movie,
            overview: "A placeholder overview",
            releaseYear: 1999,
            posterPath: "/poster.jpg",
            metadata: metadata
        )

        XCTAssertEqual(item.id, "tmdb:movie:550")
        XCTAssertEqual(item.title, "Fight Club")
        XCTAssertEqual(item.kind, .movie)
        XCTAssertEqual(item.releaseYear, 1999)
        XCTAssertEqual(item.posterPath, "/poster.jpg")
        XCTAssertEqual(item.displayTitle, "Fight Club")
        XCTAssertEqual(item.displayYear, "1999")
        XCTAssertEqual(item.bestPosterURL, posterURL)
        XCTAssertEqual(item.bestBackdropURL, backdropURL)
    }

    func testTorrentReleaseSortsByQualityThenSeeders() {
        let releases = [
            TorrentRelease(id: "a", title: "1080p low seeds", quality: .fullHD, seeders: 12),
            TorrentRelease(id: "b", title: "2160p fewer seeds", quality: .ultraHD, seeders: 3),
            TorrentRelease(id: "c", title: "2160p more seeds", quality: .ultraHD, seeders: 40)
        ]

        let ranked = releases.sortedByCineFlowRank()

        XCTAssertEqual(ranked.map(\.id), ["c", "b", "a"])
    }

    func testTorrentReleaseComputedProperties() {
        let release = TorrentRelease(
            id: "release-1",
            sourceId: "source-a",
            sourceName: "Source A",
            title: "Movie 2160p HEVC",
            magnetURI: "magnet:?xt=urn:btih:fixture",
            torrentFileURL: URL(string: "https://example.com/movie.torrent"),
            quality: .ultraHD,
            codec: .hevc,
            hdr: .hdr10,
            audioLanguages: ["ru", "en"],
            subtitleLanguages: ["ru", "en"],
            seeders: 120,
            leechers: 8,
            sizeBytes: 8_589_934_592,
            uploadDate: Date(timeIntervalSince1970: 1_700_000_000),
            trustedUploader: true
        )

        XCTAssertEqual(release.sourceId, "source-a")
        XCTAssertEqual(release.sourceName, "Source A")
        XCTAssertEqual(release.qualityLabel, "2160p")
        XCTAssertEqual(release.humanReadableSize, "8.59 GB")
        XCTAssertGreaterThan(release.rankScore, 4_000)
        XCTAssertEqual(release.audioLanguages, ["ru", "en"])
        XCTAssertEqual(release.subtitleLanguages, ["ru", "en"])
    }

    func testMediaItemSupportsMultipleReleases() {
        let item = MediaItem(
            id: "tmdb:movie:603",
            title: "The Matrix",
            kind: .movie,
            overview: "Fixture",
            releaseYear: 1999,
            posterPath: nil,
            torrentReleases: [
                TorrentRelease(id: "release-1080p", title: "The Matrix 1080p", quality: .fullHD, seeders: 200),
                TorrentRelease(id: "release-2160p", title: "The Matrix 2160p", quality: .ultraHD, seeders: 120)
            ]
        )

        XCTAssertEqual(item.torrentReleases.count, 2)
        XCTAssertEqual(item.rankedReleases.map(\.id), ["release-2160p", "release-1080p"])
    }

    func testMediaMetadataComputedFallbacks() {
        let metadata = MediaMetadata(
            tmdbId: 42,
            title: "",
            originalTitle: "Original Title",
            overview: "Fixture",
            year: nil
        )

        XCTAssertEqual(metadata.displayTitle, "Original Title")
        XCTAssertEqual(metadata.displayYear, "Unknown")
        XCTAssertNil(metadata.bestPosterURL)
        XCTAssertNil(metadata.bestBackdropURL)
    }

    func testUserFacingDomainModelsAreCodable() throws {
        let progress = PlaybackProgress(mediaID: "tmdb:movie:603", positionSeconds: 90, durationSeconds: 120)
        let encoded = try JSONEncoder().encode(progress)
        let decoded = try JSONDecoder().decode(PlaybackProgress.self, from: encoded)

        XCTAssertEqual(decoded.mediaID, progress.mediaID)
        XCTAssertEqual(decoded.positionSeconds, 90)
    }

    func testAppSettingsExposeDefaultTorrentCacheLocation() {
        let settings = AppSettings()

        XCTAssertTrue(settings.storage.torrentCacheFolderPath.contains("Application Support"))
        XCTAssertTrue(settings.storage.torrentCacheFolderPath.contains("CineFlow/TorrentCache"))
        XCTAssertNil(settings.storage.downloadsFolderPath)
    }
}
