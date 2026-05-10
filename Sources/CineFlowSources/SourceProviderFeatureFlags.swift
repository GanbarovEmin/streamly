import Foundation

public struct SourceProviderFeatureFlags: Equatable, Sendable {
    public var mockProvider: Bool
    public var rutorProvider: Bool
    public var ruTrackerProvider: Bool

    public init(
        mockProvider: Bool = true,
        rutorProvider: Bool = false,
        ruTrackerProvider: Bool = false
    ) {
        self.mockProvider = mockProvider
        self.rutorProvider = rutorProvider
        self.ruTrackerProvider = ruTrackerProvider
    }

    public static let development = SourceProviderFeatureFlags()
}
