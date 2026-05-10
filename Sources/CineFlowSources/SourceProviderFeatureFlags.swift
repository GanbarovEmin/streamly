import Foundation

public struct SourceProviderFeatureFlags: Equatable, Sendable {
    public var mockProvider: Bool
    public var rutorProvider: Bool
    public var ruTrackerProvider: Bool
    public var torrentioProvider: Bool

    public init(
        mockProvider: Bool = true,
        rutorProvider: Bool = false,
        ruTrackerProvider: Bool = false,
        torrentioProvider: Bool = false
    ) {
        self.mockProvider = mockProvider
        self.rutorProvider = rutorProvider
        self.ruTrackerProvider = ruTrackerProvider
        self.torrentioProvider = torrentioProvider
    }

    public static let development = SourceProviderFeatureFlags()
}
