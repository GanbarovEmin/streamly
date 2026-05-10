import XCTest
@testable import CineFlowDesignSystem

final class DesignTokenTests: XCTestCase {
    func testColorTokensExposeStreamlyPalette() {
        XCTAssertEqual(CFColorToken.backgroundPrimary.hex, "#0A0B0F")
        XCTAssertEqual(CFColorToken.accentPrimary.hex, "#2563FF")
        XCTAssertEqual(CFColorToken.accentSecondary.hex, "#7B3DFF")
        XCTAssertEqual(CFColorToken.accentTertiary.hex, "#FF2DB2")
        XCTAssertEqual(CFColorToken.textPrimary.hex, "#F2F4F8")
    }

    func testSpacingRadiusAndMotionTokensMatchMacShellScale() {
        XCTAssertEqual(CFSpacingToken.lg.value, 24)
        XCTAssertEqual(CFSpacingToken.xl.value, 32)
        XCTAssertEqual(CFRadiusToken.component.value, 12)
        XCTAssertEqual(CFRadiusToken.poster.value, 14)
        XCTAssertEqual(CFMotionToken.standard.duration, 0.22, accuracy: 0.001)
        XCTAssertEqual(CFMotionToken.spring.response, 0.34, accuracy: 0.001)
    }
}
