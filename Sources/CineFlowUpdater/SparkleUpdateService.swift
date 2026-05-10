import CineFlowCore
import Foundation
import Sparkle

@MainActor
public final class SparkleUpdateService: UpdateServiceProtocol {
    private let updaterController: SPUStandardUpdaterController
    private var status: UpdateStatus = .idle
    private var hasStartedUpdater: Bool

    public init(startingUpdater: Bool = false) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        hasStartedUpdater = startingUpdater
    }

    public var currentStatus: UpdateStatus {
        get async { status }
    }

    public var automaticallyChecksForUpdates: Bool {
        get async { updaterController.updater.automaticallyChecksForUpdates }
    }

    public var lastCheckedAt: Date? {
        get async { updaterController.updater.lastUpdateCheckDate }
    }

    public func startUpdaterIfNeeded() {
        guard !hasStartedUpdater else { return }
        updaterController.startUpdater()
        hasStartedUpdater = true
    }

    public func checkForUpdates() async -> UpdateStatus {
        startUpdaterIfNeeded()

        guard updaterController.updater.canCheckForUpdates else {
            status = .checking
            return status
        }

        status = .checking
        updaterController.checkForUpdates(nil)
        return status
    }

    public func setAutomaticallyChecksForUpdates(_ enabled: Bool) async {
        updaterController.updater.automaticallyChecksForUpdates = enabled
    }
}
