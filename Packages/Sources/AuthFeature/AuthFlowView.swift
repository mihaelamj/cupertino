import SharedModels
import SwiftUI

public struct AuthFlowView: View {
    @StateObject private var coordinator: AuthCoordinatorImpl

    public init(appCoordinator: AppCoordinator) {
        _coordinator = StateObject(wrappedValue: AuthCoordinatorImpl(
            appCoordinator: appCoordinator
        ))
    }

    public var body: some View {
        ZStack {
            coordinator.getCurrentView()
        }
        .animation(.easeInOut, value: coordinator.currentStep)
    }
}

#if DEBUG
// Preview helper
private class PreviewAppCoordinator: AppCoordinator {
    func start() {}
    func showAuth() {}
    func showMainApp() { print("Navigate to main app") }
    func logout() {}
}

#Preview("Auth Flow") {
    AuthFlowView(appCoordinator: PreviewAppCoordinator())
}
#endif
