import CineFlowCore
import Foundation

public struct MockUpdateService: UpdateServiceProtocol {
    public init() {}

    public var currentStatus: UpdateStatus {
        get async { .idle }
    }

    public var automaticallyChecksForUpdates: Bool {
        get async { true }
    }

    public var lastCheckedAt: Date? {
        get async { nil }
    }

    public func checkForUpdates() async -> UpdateStatus {
        .upToDate
    }

    public func setAutomaticallyChecksForUpdates(_ enabled: Bool) async {}
}
