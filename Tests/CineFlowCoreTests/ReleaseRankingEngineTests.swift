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

    func testReleaseHealthLabelsUseSeedersAndAvailability() {
        XCTAssertEqual(
            release(id: "excellent", quality: .fullHD, seeders: 500, sizeGB: 8, availability: 1.2).releaseHealth,
            .excellent
        )
        XCTAssertEqual(
            release(id: "good", quality: .fullHD, seeders: 80, sizeGB: 8, availability: 0.8).releaseHealth,
            .good
        )
        XCTAssertEqual(
            release(id: "weak", quality: .fullHD, seeders: 3, sizeGB: 8, availability: 0.3).releaseHealth,
            .weak
        )
        XCTAssertEqual(
            release(id: "dead", quality: .fullHD, seeders: 0, sizeGB: 8, availability: 0).releaseHealth,
            .noSeeders
        )
        XCTAssertEqual(
            release(id: "unknown", quality: .fullHD, seeders: -1, sizeGB: 8, availability: nil).releaseHealth,
            .unknown
        )
    }

    func testReleaseHealthAffectsRankingInsideComparableQuality() {
        let noSeeders = release(id: "dead", quality: .ultraHD, seeders: 0, sizeGB: 24, availability: 0)
        let weak = release(id: "weak", quality: .ultraHD, seeders: 8, sizeGB: 24, availability: 0.2)
        let excellent = release(id: "excellent", quality: .ultraHD, seeders: 100, sizeGB: 24, availability: 1.0)

        let ranked = ReleaseRankingEngine().rank([weak, noSeeders, excellent])

        XCTAssertEqual(ranked.map(\.release.id), ["excellent", "weak", "dead"])
        XCTAssertTrue(ranked[0].reasons.contains(.releaseHealth(.excellent)))
        XCTAssertTrue(ranked[2].reasons.contains(.releaseHealth(.noSeeders)))
    }

    func testFallbackPlannerOffersNextBestReleaseWithoutSelectedRelease() {
        let selected = release(id: "selected", quality: .fullHD, seeders: 0, sizeGB: 8)
        let weak = release(id: "weak", quality: .fullHD, seeders: 3, sizeGB: 8)
        let best = release(id: "best", quality: .fullHD, seeders: 120, sizeGB: 8, audioLanguages: ["ru"])
        let lowerQuality = release(id: "lower-quality", quality: .hd, seeders: 400, sizeGB: 4)

        let suggestion = ReleaseFallbackPlanner.suggestion(
            for: selected,
            in: [selected, weak, best, lowerQuality],
            reason: .noSeeders,
            preferences: RankingPreferences(preferredAudioLanguages: ["ru"])
        )

        XCTAssertEqual(suggestion?.reason, .noSeeders)
        XCTAssertEqual(suggestion?.nextBestRelease?.release.id, "best")
        XCTAssertEqual(suggestion?.candidates.map(\.release.id), ["best", "weak", "lower-quality"])
        XCTAssertFalse(suggestion?.candidates.contains(where: { $0.release.id == selected.id }) == true)
    }

    func testFallbackPlannerSkipsDuplicateMagnetHashCandidates() {
        let selected = TorrentRelease(
            id: "selected-0",
            title: "Selected",
            magnetURI: "magnet:?xt=urn:btih:duplicatehash",
            quality: .ultraHD,
            seeders: 700
        )
        let duplicate = TorrentRelease(
            id: "selected-auto",
            title: "Selected duplicate",
            magnetURI: "magnet:?xt=urn:btih:duplicatehash",
            quality: .ultraHD,
            seeders: 700
        )
        let nextUnique = TorrentRelease(
            id: "next-1080p",
            title: "Next 1080p",
            magnetURI: "magnet:?xt=urn:btih:nextuniquehash",
            quality: .fullHD,
            seeders: 120
        )

        let suggestion = ReleaseFallbackPlanner.suggestion(
            for: selected,
            in: [selected, duplicate, nextUnique],
            reason: .failedToStart
        )

        XCTAssertEqual(suggestion?.nextBestRelease?.release.id, nextUnique.id)
        XCTAssertEqual(suggestion?.candidates.map(\.release.id), [nextUnique.id])
    }

    func testMediaFileSelectorPrefersExplicitIndexThenLargestRealVideo() {
        let releaseWithPreferredFile = release(
            id: "preferred",
            quality: .fullHD,
            seeders: 40,
            sizeGB: 8,
            preferredFileIndex: 2
        )
        let files = [
            TorrentFile(id: "0", path: "Extras/sample.mkv", name: "sample.mkv", lengthBytes: 80_000_000, isMediaFile: true),
            TorrentFile(id: "1", path: "Movie/CD1.mkv", name: "CD1.mkv", lengthBytes: 2_000_000_000, isMediaFile: true),
            TorrentFile(id: "2", path: "Movie/CD2.mkv", name: "CD2.mkv", lengthBytes: 2_100_000_000, isMediaFile: true)
        ]

        XCTAssertEqual(TorrentMediaFileSelector.selection(for: releaseWithPreferredFile, files: files)?.selectedFile.id, "2")

        let releaseWithoutPreference = release(id: "largest", quality: .fullHD, seeders: 40, sizeGB: 8)
        let selection = TorrentMediaFileSelector.selection(for: releaseWithoutPreference, files: files)

        XCTAssertEqual(selection?.selectedFile.id, "2")
        XCTAssertEqual(selection?.manualOptions.map(\.file.id), ["2", "1"])
        XCTAssertFalse(selection?.manualOptions.contains(where: { $0.file.id == "0" }) == true)
    }

    func testPreferredQualityAndMaxFileSizeAffectRanking() {
        let releases = [
            release(id: "2160p-large", quality: .ultraHD, seeders: 220, sizeGB: 28),
            release(id: "1080p-fit", quality: .fullHD, seeders: 150, sizeGB: 8),
            release(id: "720p-small", quality: .hd, seeders: 300, sizeGB: 3)
        ]
        let preferences = RankingPreferences(
            preferredQuality: .p1080,
            maxFileSizeBytes: 10_000_000_000
        )

        let ranked = ReleaseRankingEngine(preferences: preferences).rank(releases)

        XCTAssertEqual(ranked.map(\.release.id), ["1080p-fit", "720p-small", "2160p-large"])
        XCTAssertTrue(ranked[0].reasons.contains(.preferredQuality(.p1080)))
        XCTAssertTrue(ranked[2].reasons.contains(.maxFileSizeLimit(10_000_000_000)))
    }

    func testHighSeedersPreferenceCanOutrankHigherQuality() {
        let releases = [
            release(id: "2160p-low-seeders", quality: .ultraHD, seeders: 8, sizeGB: 24),
            release(id: "1080p-many-seeders", quality: .fullHD, seeders: 1_200, sizeGB: 8)
        ]
        let preferences = RankingPreferences(preferHighSeedersOverHighestQuality: true)

        let ranked = ReleaseRankingEngine(preferences: preferences).rank(releases)

        XCTAssertEqual(ranked.first?.release.id, "1080p-many-seeders")
        XCTAssertTrue(ranked.first?.reasons.contains(.highSeedersPreference) == true)
    }

    func testHighSeedersPreferenceDemotesLargeLowSeeded4KForFasterStartup() {
        let releases = [
            release(
                id: "got-2160p-one-seeder",
                quality: .ultraHD,
                codec: .hevc,
                hdr: .dolbyVision,
                seeders: 1,
                sizeGB: 9.52,
                audioLanguages: ["ru", "en"],
                subtitleLanguages: ["ru"]
            ),
            release(
                id: "got-1080p-more-seeders",
                quality: .fullHD,
                codec: .hevc,
                hdr: .none,
                seeders: 22,
                sizeGB: 4.66,
                audioLanguages: ["ru", "en"],
                subtitleLanguages: ["ru"]
            )
        ]
        let preferences = RankingPreferences(
            preferredAudioLanguages: ["ru"],
            preferredSubtitleLanguages: ["ru"],
            supportsHDR: true,
            preferHighSeedersOverHighestQuality: true
        )

        let ranked = ReleaseRankingEngine(preferences: preferences).rank(releases)

        XCTAssertEqual(ranked.first?.release.id, "got-1080p-more-seeders")
        XCTAssertTrue(ranked.last?.reasons.contains(.startupRiskPenalty) == true)
    }

    func testAutoPlaybackDemotesWeakLowSeeder4KBelowHealthy1080p() {
        let releases = [
            release(
                id: "matrix-2160p-three-seeders",
                quality: .ultraHD,
                codec: .hevc,
                hdr: .dolbyVision,
                seeders: 3,
                sizeGB: 13,
                audioLanguages: ["ru", "en"],
                subtitleLanguages: ["ru"]
            ),
            release(
                id: "matrix-1080p-healthy",
                quality: .fullHD,
                codec: .h264,
                hdr: .none,
                seeders: 180,
                sizeGB: 6.5,
                audioLanguages: ["ru", "en"],
                subtitleLanguages: ["ru"]
            )
        ]
        let preferences = RankingPreferences(
            preferredAudioLanguages: ["ru"],
            preferredSubtitleLanguages: ["ru"],
            supportsHDR: true,
            preferredQuality: .auto,
            preferHighSeedersOverHighestQuality: true
        )

        let ranked = ReleaseRankingEngine(preferences: preferences).rank(releases)

        XCTAssertEqual(ranked.map(\.release.id), ["matrix-1080p-healthy", "matrix-2160p-three-seeders"])
        XCTAssertTrue(ranked.last?.reasons.contains(.startupRiskPenalty) == true)
    }

    func testAutoPlaybackDemotesHuge4KBelowHealthy1080pEvenWithManyReportedSeeders() {
        let releases = [
            release(
                id: "project-hail-mary-2160p-33gb",
                quality: .ultraHD,
                codec: .hevc,
                hdr: .dolbyVision,
                seeders: 734,
                sizeGB: 33.6,
                audioLanguages: ["ru", "en"],
                subtitleLanguages: ["ru"]
            ),
            release(
                id: "project-hail-mary-1080p-healthy",
                quality: .fullHD,
                codec: .h264,
                hdr: .none,
                seeders: 423,
                sizeGB: 5.2,
                audioLanguages: ["ru", "en"],
                subtitleLanguages: ["ru"]
            )
        ]
        let preferences = RankingPreferences(
            preferredAudioLanguages: ["ru"],
            preferredSubtitleLanguages: ["ru"],
            supportsHDR: true,
            preferredQuality: .auto,
            preferHighSeedersOverHighestQuality: true
        )

        let ranked = ReleaseRankingEngine(preferences: preferences).rank(releases)

        XCTAssertEqual(ranked.map(\.release.id), ["project-hail-mary-1080p-healthy", "project-hail-mary-2160p-33gb"])
        XCTAssertTrue(ranked.last?.reasons.contains(.startupRiskPenalty) == true)
    }

    func testAutoPlaybackPrefersSmallHealthyProjectHailMary1080pForFastStartup() {
        let releases = [
            release(
                id: "torrentio:tt12042730:1f5081fb83839dce4c025cb828d7c7558f03df47:0",
                quality: .fullHD,
                codec: .h264,
                hdr: .none,
                seeders: 1_906,
                sizeGB: 9.1,
                audioLanguages: ["en"],
                subtitleLanguages: ["en"]
            ),
            release(
                id: "torrentio:tt12042730:1e2879d1917ed68b00b4b2842c5de11f5b0a17fe:4",
                quality: .ultraHD,
                codec: .h265,
                hdr: .none,
                seeders: 1_680,
                sizeGB: 10.69,
                audioLanguages: ["en"],
                subtitleLanguages: ["en"]
            ),
            release(
                id: "torrentio:tt12042730:d6ecf1ac0937e505330aed486f4980be1df9bbb8:0",
                quality: .fullHD,
                codec: .hevc,
                hdr: .none,
                seeders: 1_621,
                sizeGB: 2.72,
                audioLanguages: ["en"],
                subtitleLanguages: ["en"]
            )
        ]
        let preferences = RankingPreferences(
            preferredQuality: .auto,
            preferHighSeedersOverHighestQuality: true
        )

        let ranked = ReleaseRankingEngine(preferences: preferences).rank(releases)

        XCTAssertEqual(ranked.first?.release.id, "torrentio:tt12042730:d6ecf1ac0937e505330aed486f4980be1df9bbb8:0")
        XCTAssertTrue(ranked.first?.reasons.contains(.startupRiskPenalty) == true)
        XCTAssertGreaterThan(ranked[0].score, ranked[1].score)
    }

    func testAutoPlaybackKeepsVeryLarge4KBelowSmall1080pFallbacksEvenWithMoreReportedSeeders() {
        let releases = [
            release(
                id: "torrentio:tt12042730:792b3577fed6dd95dbb03f5f0972e821230b834f:0",
                quality: .ultraHD,
                codec: .h265,
                hdr: .none,
                seeders: 2_484,
                sizeGB: 23.33,
                audioLanguages: ["en"],
                subtitleLanguages: ["en"]
            ),
            release(
                id: "torrentio:tt12042730:f72a9cf2b79020a2fa1c8fb6f646fd384905efe9:0",
                quality: .fullHD,
                codec: .h264,
                hdr: .none,
                seeders: 954,
                sizeGB: 2.35,
                audioLanguages: ["en"],
                subtitleLanguages: ["en"]
            ),
            release(
                id: "torrentio:tt12042730:e9b05de28f91baa6bac63278f9e42ed1828da3af:0",
                quality: .fullHD,
                codec: .hevc,
                hdr: .none,
                seeders: 850,
                sizeGB: 2.98,
                audioLanguages: ["en"],
                subtitleLanguages: ["en"]
            )
        ]
        let preferences = RankingPreferences(
            preferredQuality: .auto,
            preferHighSeedersOverHighestQuality: true
        )

        let ranked = ReleaseRankingEngine(preferences: preferences).rank(releases)

        XCTAssertEqual(ranked.map(\.release.quality), [.fullHD, .fullHD, .ultraHD])
        XCTAssertEqual(ranked.last?.release.id, "torrentio:tt12042730:792b3577fed6dd95dbb03f5f0972e821230b834f:0")
        XCTAssertTrue(ranked.last?.reasons.contains(.startupRiskPenalty) == true)
    }

    func testHDRAndCodecPreferencesAffectRanking() {
        let releases = [
            release(id: "hdr-av1", quality: .fullHD, codec: .av1, hdr: .hdr10, seeders: 300, sizeGB: 8),
            release(id: "sdr-hevc", quality: .fullHD, codec: .hevc, hdr: .none, seeders: 260, sizeGB: 8)
        ]

        let avoidRanked = ReleaseRankingEngine(preferences: RankingPreferences(
            hdrPreference: .avoidHDR,
            codecPreference: .avoidUnsupportedAV1
        )).rank(releases)
        XCTAssertEqual(avoidRanked.first?.release.id, "sdr-hevc")
        XCTAssertTrue(avoidRanked.first?.reasons.contains(.codecPreference(.avoidUnsupportedAV1)) == true)

        let preferRanked = ReleaseRankingEngine(preferences: RankingPreferences(
            hdrPreference: .preferHDR,
            codecPreference: .preferHEVC
        )).rank([
            release(id: "hdr-hevc", quality: .fullHD, codec: .hevc, hdr: .hdr10, seeders: 240, sizeGB: 8),
            release(id: "sdr-h264", quality: .fullHD, codec: .h264, hdr: .none, seeders: 300, sizeGB: 8)
        ])
        XCTAssertEqual(preferRanked.first?.release.id, "hdr-hevc")
        XCTAssertTrue(preferRanked.first?.reasons.contains(.hdrPreference(.preferHDR)) == true)
        XCTAssertTrue(preferRanked.first?.reasons.contains(.codecPreference(.preferHEVC)) == true)
    }

    func testRankedReleaseExposesUserFacingLabelsReasonsAndAdvancedDetails() {
        let best = release(
            id: "best-4k-ru",
            quality: .ultraHD,
            codec: .hevc,
            hdr: .hdr10,
            seeders: 800,
            sizeGB: 18,
            audioLanguages: ["ru", "en"],
            subtitleLanguages: ["en"],
            trustedUploader: true,
            availability: 1.0
        )
        let fastest = release(id: "fastest-1080p", quality: .fullHD, seeders: 1_400, sizeGB: 9)
        let smallest = release(id: "smallest-720p", quality: .hd, seeders: 120, sizeGB: 3)

        let ranked = ReleaseRankingEngine(preferences: RankingPreferences(
            preferredAudioLanguages: ["ru"],
            preferredSubtitleLanguages: ["en"],
            supportsHDR: true,
            maxFileSizeBytes: 20_000_000_000
        )).rank([smallest, fastest, best])

        XCTAssertEqual(ranked.first?.release.id, "best-4k-ru")
        XCTAssertTrue(ranked[0].labels.contains(.best))
        XCTAssertTrue(ranked[0].labels.contains(.best4K))
        XCTAssertTrue(ranked[0].labels.contains(.bestRussianAudio))
        XCTAssertTrue(ranked.first?.conciseReasons.contains("4K quality") == true)
        XCTAssertTrue(ranked.first?.conciseReasons.contains("Russian audio") == true)
        XCTAssertTrue(ranked.first?.conciseReasons.contains("English subtitles") == true)
        XCTAssertTrue(ranked.first?.conciseReasons.contains("HDR") == true)
        XCTAssertTrue(ranked.first?.conciseReasons.contains("trusted source") == true)
        XCTAssertTrue(ranked.first?.conciseReasons.contains("fits size preference") == true)
        XCTAssertTrue(ranked.first?.conciseReasons.contains("HEVC codec") == true)
        XCTAssertTrue(ranked.first?.tooltipExplanation.contains("Why this release") == true)
        XCTAssertTrue(ranked.first?.advancedDetails.contains(where: { $0.contains("Score") }) == true)
        XCTAssertTrue(ranked.first?.advancedDetails.contains(where: { $0.contains("Source") }) == true)
        XCTAssertTrue(ranked.first?.advancedDetails.contains(where: { $0.contains("Size") }) == true)
        XCTAssertTrue(ranked.first(where: { $0.release.id == "fastest-1080p" })?.labels.contains(.fastest) == true)
        XCTAssertTrue(ranked.first(where: { $0.release.id == "smallest-720p" })?.labels.contains(.smallest) == true)
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
        trustedUploader: Bool? = nil,
        preferredFileIndex: Int? = nil,
        availability: Double? = nil
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
            trustedUploader: trustedUploader,
            preferredFileIndex: preferredFileIndex,
            availability: availability
        )
    }
}
