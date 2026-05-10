import Foundation
import XCTest
@testable import CineFlowCore
@testable import CineFlowUpdater

final class GitHubReleaseUpdateServiceTests: XCTestCase {
    override func tearDown() {
        URLProtocolMock.reset()
        super.tearDown()
    }

    func testLatestMatchingGitHubReleaseReportsUpToDate() async {
        let service = GitHubReleaseUpdateService(
            currentVersion: "1.0.0",
            session: Self.mockSession(responseBody: #"{"tag_name":"v1.0.0"}"#)
        )

        let status = await service.checkForUpdates()
        let lastCheckedAt = await service.lastCheckedAt

        XCTAssertEqual(status, .upToDate)
        XCTAssertNotNil(lastCheckedAt)
    }

    func testNewerGitHubReleaseReportsAvailableVersion() async {
        let service = GitHubReleaseUpdateService(
            currentVersion: "1.0.0",
            session: Self.mockSession(responseBody: #"{"tag_name":"v1.0.1"}"#)
        )

        let status = await service.checkForUpdates()

        XCTAssertEqual(status, .updateAvailable("1.0.1"))
    }

    func testInvalidGitHubReleasePayloadReportsFailure() async {
        let service = GitHubReleaseUpdateService(
            currentVersion: "1.0.0",
            session: Self.mockSession(responseBody: #"{"name":"missing tag"}"#)
        )

        let status = await service.checkForUpdates()

        guard case .failed(let message) = status else {
            return XCTFail("Expected failed status, got \(status)")
        }
        XCTAssertTrue(message.contains("GitHub Releases"))
    }

    private static func mockSession(responseBody: String, statusCode: Int = 200) -> URLSession {
        URLProtocolMock.responseData = Data(responseBody.utf8)
        URLProtocolMock.statusCode = statusCode
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolMock.self]
        return URLSession(configuration: configuration)
    }
}

private final class URLProtocolMock: URLProtocol {
    static var responseData = Data()
    static var statusCode = 200

    static func reset() {
        responseData = Data()
        statusCode = 200
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
