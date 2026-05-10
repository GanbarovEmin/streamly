import Foundation
import XCTest

final class ReleasePackagingTests: XCTestCase {
    func testReleaseInfoPlistDeclaresStreamlyIcon() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Configuration/CineFlow-Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "Streamly")
    }

    func testReleaseScriptCopiesStreamlyIconIntoAppBundle() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("script/build_release.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("Streamly.icns"))
        XCTAssertTrue(script.contains("Contents/Resources"))
    }

    func testReleaseScriptOptionallyCopiesNativeLibtorrentFramework() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("script/build_release.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("Vendor/CineFlowLibtorrentNative.xcframework"))
        XCTAssertTrue(script.contains("CineFlowLibtorrentNative.framework"))
        XCTAssertTrue(script.contains("Packaging Streamly without torrent playback"))
        XCTAssertTrue(script.contains("Contents/Frameworks/$NATIVE_LIBTORRENT_FRAMEWORK_NAME"))
        XCTAssertTrue(script.contains("NATIVE_LIBTORRENT_COPIED=1"))
    }
}
