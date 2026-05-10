import CineFlowCore
import Foundation

public actor GitHubReleaseUpdateService: UpdateServiceProtocol {
    private let latestReleaseURL: URL
    private let currentVersion: String
    private let session: URLSession
    private var status: UpdateStatus = .idle
    private var checkedAt: Date?
    private var automaticChecksEnabled: Bool

    public init(
        latestReleaseURL: URL = GitHubReleaseUpdateService.defaultLatestReleaseURL,
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
        session: URLSession = .shared,
        automaticallyChecksForUpdates: Bool = true
    ) {
        self.latestReleaseURL = latestReleaseURL
        self.currentVersion = currentVersion
        self.session = session
        self.automaticChecksEnabled = automaticallyChecksForUpdates
    }

    public var currentStatus: UpdateStatus {
        status
    }

    public var automaticallyChecksForUpdates: Bool {
        automaticChecksEnabled
    }

    public var lastCheckedAt: Date? {
        checkedAt
    }

    public func checkForUpdates() async -> UpdateStatus {
        checkedAt = Date()
        status = .checking

        do {
            var request = URLRequest(url: latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Streamly", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                throw GitHubReleaseUpdateError.invalidResponse
            }

            let release = try JSONDecoder().decode(GitHubLatestRelease.self, from: data)
            guard let latestVersion = Self.normalizedVersion(release.tagName) else {
                throw GitHubReleaseUpdateError.missingVersion
            }

            let installedVersion = Self.normalizedVersion(currentVersion) ?? currentVersion
            status = Self.compareVersions(latestVersion, installedVersion) == .orderedDescending
                ? .updateAvailable(latestVersion)
                : .upToDate
            return status
        } catch {
            status = .failed("Could not check GitHub Releases for updates.")
            return status
        }
    }

    public func setAutomaticallyChecksForUpdates(_ enabled: Bool) async {
        automaticChecksEnabled = enabled
    }

    public static var defaultLatestReleaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/GanbarovEmin/streamly/releases/latest"
        return components.url ?? URL(fileURLWithPath: "/")
    }

    private static func normalizedVersion(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        return withoutPrefix.isEmpty ? nil : withoutPrefix
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue > rightValue { return .orderedDescending }
            if leftValue < rightValue { return .orderedAscending }
        }
        return .orderedSame
    }
}

private struct GitHubLatestRelease: Decodable {
    let tagName: String

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}

private enum GitHubReleaseUpdateError: Error {
    case invalidResponse
    case missingVersion
}
