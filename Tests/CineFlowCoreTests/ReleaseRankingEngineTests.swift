import XCTest
@testable import CineFlowCore

final class ReleaseRankingEngineTests: XCTestCase {
    func testRanksHigherQualityAboveLowerQualityEvenWithFewerSeeders() {
        let releases = [
            release(id: "1080p-many", quality: .fullHD, seeders: 2_000, sizeGB: 12),
            release(id: "2160p-fewer", quality: .ultraHD, seeders: 250, sizeGB: 28)
        ]

        let ranked = ReleaseRankingEngine().rank(releases)

        XCTAssertEqual(ranked.map(\.release.id), ["2160p-fewer", "1080p-many"])
        XCTAssertTrue(ranked[0].reasons.contains(.quality(.ultraHD)))
        XCTAssertGreaterThan(ranked[0].score, ranked[1].score)
    }

    func testRanksMoreSeedersHigherInsideSameQuality() {
        let releases = [
            release(id: "2160p-low", quality: .ultraHD, seeders: 20, sizeGB: 26),
            release(id: "2160p-high", quality: .ultraHD, seeders: 420, sizeGB: 26)
        ]

        let ranked = ReleaseRankingEngine().rank(releases)

        XCTAssertEqual(ranked.map(\.release.id), ["2160p-high", "2160p-low"])
        XCTAssertTrue(ranked[0].reasons.contains(.seeders(420)))
    }

    func testLanguagePreferencesAffectRankingAndReasons() {
        let releases = [
            release(
                id: "english-only",
                quality: .ultraHD,
                seeders: 300,
                sizeGB: 25,
                audioLanguages: ["en"],
                subtitleLanguages: ["en"]
            ),
            release(
                id: "preferred-languages",
                quality: .ultraHD,
                seeders: 260,
                sizeGB: 25,
                audioLanguages: ["ru", "en"],
                subtitleLanguages: ["az", "ru"]
            )
        ]
        let preferences = RankingPreferences(
            preferredAudioLanguages: ["ru"],
            preferredSubtitleLanguages: ["az"],
            supportsHDR: true
        )

        let ranked = ReleaseRankingEngine(preferences: preferences).rank(releases)

        XCTAssertEqual(ranked.first?.release.id, "preferred-languages")
        XCTAssertTrue(ranked[0].reasons.contains(.preferredAudioLanguage("ru")))
        XCTAssertTrue(ranked[0].reasons.contains(.preferredSubtitleLanguage("az")))
    }

    func testHdrTrustedUploaderCodecAndSuspiciousSizeChangeScore() {
        let strong = release(
            id: "strong",
            quality: .ultraHD,
            codec: .hevc,
            hdr: .dolbyVision,
            seeders: 240,
            sizeGB: 32,
            trustedUploader: true
        )
        let suspicious = release(
            id: "suspicious",
            quality: .ultraHD,
            codec: .unknown,
            hdr: .none,
            seeders: 240,
            sizeGB: 1,
            trustedUploader: false
        )

        let ranked = ReleaseRankingEngine(preferences: RankingPreferences(supportsHDR: true)).rank([suspicious, strong])

        XCTAssertEqual(ranked.first?.release.id, "strong")
        XCTAssertTrue(ranked[0].reasons.contains(.hdr(.dolbyVision)))
        XCTAssertTrue(ranked[0].reasons.contains(.trustedUploader))
        XCTAssertTrue(ranked[0].reasons.contains(.codec(.hevc)))
        XCTAssertTrue(ranked[1].reasons.contains(.suspiciousSmallSize))
    }

    func testUnknownQualityIsPenalizedAndRankingIsDeterministic() {
        let releases = [
            release(id: "z", quality: .unknown, seeders: 10, sizeGB: 1),
            release(id: "a", quality: .unknown, seeders: 10, sizeGB: 1)
        ]

        let ranked = ReleaseRankingEngine().rank(releases)

        XCTAssertEqual(ranked.map(\.release.id), ["a", "z"])
        XCTAssertTrue(ranked[0].reasons.contains(.unknownQualityPenalty))
        XCTAssertEqual(ReleaseRankingEngine().rank(releases).map(\.release.id), ranked.map(\.release.id))
    }

    func testSequenceSortedByCineFlowRankUsesRankingEngine() {
        let releases = [
            release(id: "1080p", quality: .fullHD, seeders: 2_000, sizeGB: 12),
            release(id: "2160p", quality: .ultraHD, seeders: 250, sizeGB: 28)
        ]

        XCTAssertEqual(releases.sortedByCineFlowRank().map(\.id), ["2160p", "1080p"])
    }

    private func release(
        id: String,
        quality: ReleaseQuality,
        codec: VideoCodec = .h264,
        hdr: HDRFormat = .none,
        seeders: Int,
        sizeGB: Double,
        audioLanguages: [String] = ["en"],
        subtitleLanguages: [String] = ["en"],
        trustedUploader: Bool? = nil
    ) -> TorrentRelease {
        TorrentRelease(
            id: id,
            title: id,
            quality: quality,
            codec: codec,
            hdr: hdr,
            audioLanguages: audioLanguages,
            subtitleLanguages: subtitleLanguages,
            seeders: seeders,
            sizeBytes: Int64(sizeGB * 1_000_000_000),
            trustedUploader: trustedUploader
        )
    }
}
