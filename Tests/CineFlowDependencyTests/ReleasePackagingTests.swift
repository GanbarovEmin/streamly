import Foundation
import XCTest

final class ReleasePackagingTests: XCTestCase {
    func testReleaseInfoPlistDeclaresStreamlyIcon() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Configuration/Streamly-Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "Streamly")
    }

    func testReleaseInfoPlistDeclaresStreamlyDisplayAndExecutableName() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Configuration/Streamly-Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Streamly")
        XCTAssertEqual(plist["CFBundleName"] as? String, "Streamly")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "Streamly")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.streamly.app")
        XCTAssertEqual(plist["SUFeedURL"] as? String, "https://ganbarovemin.github.io/streamly/appcast.xml")
        XCTAssertNotEqual(plist["SUPublicEDKey"] as? String, "REPLACE_WITH_SPARKLE_EDDSA_PUBLIC_KEY")
        XCTAssertFalse((plist["SUPublicEDKey"] as? String)?.isEmpty ?? true)
    }

    func testSwiftPackageExposesStreamlyExecutableProduct() throws {
        let packageURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Package.swift")
        let package = try String(contentsOf: packageURL, encoding: .utf8)

        XCTAssertTrue(package.contains(#"name: "Streamly""#))
        XCTAssertTrue(package.contains(#".executable(name: "Streamly""#))
    }

    func testReleaseScriptCopiesStreamlyIconIntoAppBundle() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("script/build_release.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("Streamly.icns"))
        XCTAssertTrue(script.contains(#"PRODUCT_NAME="Streamly""#))
        XCTAssertTrue(script.contains("Contents/Resources"))
    }

    func testReleaseScriptRequiresNativeLibtorrentUnlessDevelopmentOverrideIsExplicit() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("script/build_release.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("Vendor/CineFlowLibtorrentNative.xcframework"))
        XCTAssertTrue(script.contains("CineFlowLibtorrentNative.framework"))
        XCTAssertTrue(script.contains("Refusing to package Streamly without native libtorrent runtime"))
        XCTAssertTrue(script.contains("--allow-missing-native-runtime"))
        XCTAssertTrue(script.contains("Contents/Frameworks/$NATIVE_LIBTORRENT_FRAMEWORK_NAME"))
        XCTAssertTrue(script.contains("NATIVE_LIBTORRENT_COPIED=1"))
    }

    func testReleaseScriptsRejectPlaceholderMPVRuntimeForProductionArtifacts() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let releaseScript = try String(contentsOf: rootURL.appendingPathComponent("script/build_release.sh"), encoding: .utf8)
        let dmgScript = try String(contentsOf: rootURL.appendingPathComponent("script/create_dmg.sh"), encoding: .utf8)

        XCTAssertTrue(releaseScript.contains("Refusing to package Streamly while MPV playback bridge is placeholder"))
        XCTAssertTrue(releaseScript.contains("--allow-placeholder-mpv-runtime"))
        XCTAssertTrue(dmgScript.contains("Refusing to create DMG while MPV playback bridge is placeholder"))
        XCTAssertTrue(dmgScript.contains("--allow-placeholder-mpv-runtime"))
    }

    func testReleaseScriptsRequireBundledFFmpegForInAppTorrentPlayback() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let releaseScript = try String(contentsOf: rootURL.appendingPathComponent("script/build_release.sh"), encoding: .utf8)
        let dmgScript = try String(contentsOf: rootURL.appendingPathComponent("script/create_dmg.sh"), encoding: .utf8)

        XCTAssertTrue(releaseScript.contains("STREAMLY_FFMPEG_EXECUTABLE"))
        XCTAssertTrue(releaseScript.contains("Contents/Resources/ffmpeg"))
        XCTAssertTrue(releaseScript.contains("Refusing to package Streamly without ffmpeg runtime"))
        XCTAssertTrue(dmgScript.contains("Contents/Resources/ffmpeg"))
        XCTAssertTrue(dmgScript.contains("Refusing to create DMG without ffmpeg runtime"))
    }

    func testProductionAppDoesNotSeedDevelopmentDataByDefaultAndUsesRealSubtitles() throws {
        let appURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CineFlowApp/CineFlowApp.swift")
        let source = try String(contentsOf: appURL, encoding: .utf8)

        XCTAssertTrue(source.contains("STREAMLY_SEED_DEVELOPMENT_DATA"))
        XCTAssertTrue(source.contains("shouldSeedDevelopmentData"))
        XCTAssertTrue(source.contains("subtitleService: SubtitleService()"))
        XCTAssertFalse(source.contains("subtitleService: MockSubtitleService()"))
    }

    func testProductionAppWiresSparkleUpdater() throws {
        let appURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CineFlowApp/CineFlowApp.swift")
        let source = try String(contentsOf: appURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private let updateService: SparkleUpdateService"))
        XCTAssertTrue(source.contains("SparkleUpdateService(startingUpdater: true)"))
        XCTAssertFalse(source.contains("let updateService = GitHubReleaseUpdateService()"))
    }

    func testReleaseWorkflowPublishesSparkleAppcast() throws {
        let workflowURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".github/workflows/release.yml")
        let workflow = try String(contentsOf: workflowURL, encoding: .utf8)

        XCTAssertTrue(workflow.contains("generate_appcast"))
        XCTAssertTrue(workflow.contains("appcast.xml"))
        XCTAssertTrue(workflow.contains("actions/deploy-pages"))
        XCTAssertTrue(workflow.contains("SPARKLE_PRIVATE_KEY"))
        XCTAssertTrue(workflow.contains("--ed-key-file"))
        XCTAssertTrue(workflow.contains("--sign -"))
        XCTAssertFalse(workflow.contains("env.SPARKLE_PRIVATE_KEY != ''"))
    }
}
