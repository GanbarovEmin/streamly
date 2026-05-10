import Foundation
import XCTest
@testable import CineFlowCore

final class CineFlowErrorTests: XCTestCase {
    func testNetworkErrorUsesUserSafeMessageAndKeepsTechnicalDetailsForDiagnostics() {
        let error = CineFlowError.from(URLError(.notConnectedToInternet), fallbackCategory: .network)

        XCTAssertEqual(error.category, .network)
        XCTAssertEqual(error.logLevel, .warning)
        XCTAssertEqual(error.userMessage, "Streamly cannot reach the network right now.")
        XCTAssertEqual(error.recoverySuggestion, "Check your internet connection and try again.")
        XCTAssertTrue(error.technicalDescription.contains("notConnectedToInternet"))
        XCTAssertFalse(error.userMessage.contains("URLError"))
    }

    func testKnownPlaybackErrorMapsToPlaybackCategory() {
        let error = CineFlowError.from(PlaybackServiceError.mpvUnavailable)

        XCTAssertEqual(error.category, .playback)
        XCTAssertEqual(error.logLevel, .error)
        XCTAssertEqual(error.userMessage, "Playback is not available right now.")
        XCTAssertTrue(error.technicalDescription.contains("mpv"))
    }
}
