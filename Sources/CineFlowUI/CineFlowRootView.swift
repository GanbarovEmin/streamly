import CineFlowCore
import SwiftUI

public struct CineFlowRootView: View {
    private let environment: AppEnvironment
    private let navigationCoordinator: NavigationCoordinator
    private let macOSIntegrationViewModel: MacOSIntegrationViewModel

    public init(
        environment: AppEnvironment,
        navigationCoordinator: NavigationCoordinator,
        macOSIntegrationViewModel: MacOSIntegrationViewModel
    ) {
        self.environment = environment
        self.navigationCoordinator = navigationCoordinator
        self.macOSIntegrationViewModel = macOSIntegrationViewModel
    }

    public var body: some View {
        AppWindowRootView(
            environment: environment,
            navigationCoordinator: navigationCoordinator,
            macOSIntegrationViewModel: macOSIntegrationViewModel
        )
    }
}
