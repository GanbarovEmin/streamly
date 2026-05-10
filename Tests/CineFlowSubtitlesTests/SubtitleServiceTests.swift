import CineFlowCore
import XCTest
@testable import CineFlowSubtitles

final class SubtitleServiceTests: XCTestCase {
    func testPreferredSubtitlesCombineEmbeddedLocalAndOpenSubtitlesByLanguagePriority() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let localSubtitleURL = directory.appendingPathComponent("The Matrix.1999.ru.srt")
        try "1\n00:00:00,000 --> 00:00:01,000\nPrivet\n".write(to: localSubtitleURL, atomically: true, encoding: .utf8)

        let service = SubtitleService(
            openSubtitlesClient: MockOpenSubtitlesClient(results: [
                SubtitleSearchResult(
                    id: "os-en",
                    title: "The Matrix English",
                    languageCode: "en",
                    source: .openSubtitles,
                    score: 0,
                    downloadURL: URL(string: "https://example.test/matrix-en.srt")
                )
            ]),
            cache: SubtitleCache(storageURL: directory.appendingPathComponent("cache", isDirectory: true)),
            settings: SubtitleSettings(languagePreference: SubtitleLanguagePreference(["ru", "en"]))
        )
        let query = SubtitleSearchQuery(
            title: "The Matrix",
            year: 1999,
            localVideoURL: directory.appendingPathComponent("The Matrix.1999.mkv")
        )
        let embedded = [
            SubtitleTrack(id: "embedded-en", languageCode: "en", displayName: "English Embedded", source: .embedded),
            SubtitleTrack(id: "embedded-ru", languageCode: "ru", displayName: "Russian Embedded", source: .embedded)
        ]

        let subtitles = try await service.preferredSubtitles(for: query, embeddedTracks: embedded, localSearchDirectory: directory)

        XCTAssertEqual(subtitles.map(\.languageCode), ["ru", "ru", "en", "en"])
        XCTAssertEqual(subtitles.map(\.source), [.embedded, .localFile, .embedded, .openSubtitles])
    }

    func testOpenSubtitlesSearchIsSkippedWhenAutoSearchDisabled() async throws {
        let client = RecordingOpenSubtitlesClient(results: [])
        let service = SubtitleService(
            openSubtitlesClient: client,
            settings: SubtitleSettings(autoSearchSubtitles: false)
        )

        let results = try await service.searchOnlineSubtitles(
            query: SubtitleSearchQuery(title: "Arrival", year: 2016),
            languages: ["ru", "en"]
        )

        XCTAssertTrue(results.isEmpty)
        let searchCount = await client.searchCountValue()
        XCTAssertEqual(searchCount, 0)
    }

    func testDownloadSubtitleCachesFileInApplicationSupportSubtitlesPath() async throws {
        let cache = SubtitleCache(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        let service = SubtitleService(
            openSubtitlesClient: MockOpenSubtitlesClient(downloadData: Data("subtitle-body".utf8)),
            cache: cache
        )
        let result = SubtitleSearchResult(
            id: "os-ru",
            title: "Arrival Russian",
            languageCode: "ru",
            source: .openSubtitles,
            score: 0.9,
            downloadURL: URL(string: "https://example.test/arrival-ru.srt")
        )

        let track = try await service.downloadSubtitle(result)
        let cachedData = try Data(contentsOf: try XCTUnwrap(track.localURL))

        XCTAssertEqual(track.source, .openSubtitles)
        XCTAssertEqual(String(data: cachedData, encoding: .utf8), "subtitle-body")
        XCTAssertTrue(SubtitleCache.defaultStorageURL().path.contains("Application Support"))
        XCTAssertTrue(SubtitleCache.defaultStorageURL().path.contains("Streamly/Subtitles"))
    }

    func testMatchingLogicUsesTitleYearEpisodeHashAndLanguage() {
        let query = SubtitleSearchQuery(
            title: "Game of Thrones",
            year: 2012,
            season: 2,
            episode: 3,
            fileHash: "abc123"
        )
        let strong = SubtitleSearchResult(
            id: "strong",
            title: "Game of Thrones S02E03",
            languageCode: "ru",
            source: .openSubtitles,
            score: 0,
            year: 2012,
            season: 2,
            episode: 3,
            fileHash: "abc123"
        )
        let weak = SubtitleSearchResult(
            id: "weak",
            title: "Different Show",
            languageCode: "en",
            source: .openSubtitles,
            score: 0,
            year: 2011
        )
        let matcher = SubtitleMatcher(languagePreference: SubtitleLanguagePreference(["ru", "en"]))

        XCTAssertGreaterThan(matcher.score(strong, for: query), matcher.score(weak, for: query))
    }
}

private actor RecordingOpenSubtitlesClient: OpenSubtitlesClientProtocol {
    private var searchCount = 0
    private let results: [SubtitleSearchResult]

    init(results: [SubtitleSearchResult]) {
        self.results = results
    }

    func searchCountValue() -> Int {
        searchCount
    }

    func search(query: SubtitleSearchQuery, languages: [String]) async throws -> [SubtitleSearchResult] {
        searchCount += 1
        return results
    }

    func download(result: SubtitleSearchResult) async throws -> Data {
        Data()
    }
}
