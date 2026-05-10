import XCTest
import CineFlowLocalization
@testable import CineFlowDesignSystem

final class ComponentContractTests: XCTestCase {
    func testBadgeToneLabelsCoverMediaMetadataNeeds() {
        XCTAssertEqual(CFBadgeTone.quality.accessibilityPrefixKey, .accessibilityBadgeQuality)
        XCTAssertEqual(CFBadgeTone.source.accessibilityPrefixKey, .accessibilityBadgeSource)
        XCTAssertEqual(CFBadgeTone.seeders.accessibilityPrefixKey, .accessibilityBadgeSeeders)
        XCTAssertEqual(CFBadgeTone.rating.accessibilityPrefixKey, .accessibilityBadgeRating)
    }

    func testPosterCardModelKeepsReusableMediaCardData() {
        let artworkURL = URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg")!
        let model = CFMediaCardModel(
            id: "tmdb:movie:603",
            title: "The Matrix",
            metadata: "2160p · 88 seeders",
            badge: "2160p",
            artworkURL: artworkURL
        )

        XCTAssertEqual(model.id, "tmdb:movie:603")
        XCTAssertEqual(model.title, "The Matrix")
        XCTAssertEqual(model.badge, "2160p")
        XCTAssertEqual(model.artworkURL, artworkURL)
    }
}
