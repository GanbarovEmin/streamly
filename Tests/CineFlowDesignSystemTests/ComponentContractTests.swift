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

    func testMediaCardMenuAvailabilityCoversPowerUserActions() {
        let availability = CFMediaCardMenuAvailability(
            canWatch: true,
            canOpenDetails: true,
            canAddToLibrary: false,
            canAddToWatchlist: true,
            canAddToList: true,
            canRate: true,
            canHide: false,
            canFixMetadata: true,
            canFindBestRelease: true,
            canClearProgress: false,
            canTuneRecommendations: true
        )

        XCTAssertTrue(availability.canWatch)
        XCTAssertTrue(availability.canAddToWatchlist)
        XCTAssertTrue(availability.canFindBestRelease)
        XCTAssertFalse(availability.canAddToLibrary)
        XCTAssertFalse(availability.canHide)
        XCTAssertFalse(availability.canClearProgress)
    }

    func testBrandMarkResolvesLogoFromReleaseResourceBundle() throws {
        let resourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("streamly-brandmark-\(UUID().uuidString)", isDirectory: true)
        let bundleURL = resourceURL.appendingPathComponent("Streamly_CineFlowDesignSystem.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.streamly.tests.CineFlowDesignSystem</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
        </dict>
        </plist>
        """.write(to: bundleURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        let logoURL = bundleURL.appendingPathComponent("streamly-mark.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: logoURL)
        defer { try? FileManager.default.removeItem(at: resourceURL) }

        XCTAssertEqual(
            CFBrandMark.logoResourceURL(
                resourceURL: resourceURL,
                appBundleURL: resourceURL.appendingPathComponent("Streamly.app"),
                includeSwiftPackageFallback: false
            ),
            logoURL
        )
    }

    func testBrandMarkDoesNotEvaluateSwiftPackageBundleInsidePackagedApp() {
        let appURL = URL(fileURLWithPath: "/Applications/Streamly.app", isDirectory: true)

        XCTAssertNil(
            CFBrandMark.logoResourceURL(
                resourceURL: nil,
                appBundleURL: appURL,
                includeSwiftPackageFallback: true
            )
        )
    }
}
