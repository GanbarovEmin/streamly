import CineFlowCore
import XCTest
@testable import CineFlowUI

@MainActor
final class SearchErrorHandlingTests: XCTestCase {
    func testSearchFailureShowsUserSafeMessageAndLogsTechnicalDetails() async {
        let diagnostics = CapturingDiagnosticsService()
        let provider = FailingSearchProvider(error: URLError(.notConnectedToInternet))
        let viewModel = SearchViewModel(provider: provider, diagnosticsService: diagnostics, debounceNanoseconds: 0)

        await viewModel.searchNow(query: "matrix")

        XCTAssertEqual(viewModel.state, .failed("Streamly cannot reach the network right now."))
        XCTAssertEqual(viewModel.lastError?.category, .network)
        let events = await diagnostics.events()
        XCTAssertEqual(events.first?.level, .warning)
        XCTAssertEqual(events.first?.subsystem, .app)
        XCTAssertEqual(events.first?.message, "Streamly cannot reach the network right now.")
        XCTAssertTrue(events.first?.metadata["technicalDescription"]?.contains("notConnectedToInternet") == true)
    }

    func testRetryLastSearchReusesQueryAndClearsFailure() async {
        let provider = FailsOnceSearchProvider()
        let viewModel = SearchViewModel(provider: provider, debounceNanoseconds: 0)

        await viewModel.searchNow(query: "matrix")
        XCTAssertEqual(viewModel.state, .failed("Search is temporarily unavailable."))

        await viewModel.retryLastSearch()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertFalse(viewModel.results.torrentReleases.isEmpty)
    }
}

private struct FailingSearchProvider: SearchProviderProtocol {
    let error: Error

    func search(query: String) async throws -> SearchProviderResponse {
        throw error
    }
}

private actor FailsOnceSearchProvider: SearchProviderProtocol {
    private var didFail = false

    func search(query: String) async throws -> SearchProviderResponse {
        if !didFail {
            didFail = true
            throw SearchProviderError.mockFailure
        }
        return try await MockSearchProvider().search(query: query)
    }
}

private actor CapturingDiagnosticsService: DiagnosticsServiceProtocol {
    private var storedEvents: [DiagnosticsEvent] = []

    func log(level: DiagnosticsLogLevel, subsystem: DiagnosticsSubsystem, message: String, metadata: [String: String]) async {
        storedEvents.append(DiagnosticsEvent(level: level, subsystem: subsystem, message: message, metadata: metadata))
    }

    func exportDiagnostics() async -> String {
        ""
    }

    func exportDiagnosticsPackage() async throws -> URL {
        URL(fileURLWithPath: "/tmp/diagnostics.zip")
    }

    func recentEvents(limit: Int) async -> [DiagnosticsEvent] {
        Array(storedEvents.prefix(limit))
    }

    func events() -> [DiagnosticsEvent] {
        storedEvents
    }
}
