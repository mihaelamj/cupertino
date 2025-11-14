import SharedModels
import SwiftUI

public struct AppView: View {
    @StateObject private var appCoordinator: AppCoordinatorImpl

    public init() {
        _appCoordinator = StateObject(wrappedValue: AppCoordinatorImpl())
    }

    public var body: some View {
        ZStack {
            appCoordinator.getCurrentView()
        }
        .animation(.easeInOut, value: appCoordinator.currentState)
        .onAppear {
            appCoordinator.start()
        }
    }
}

#if DEBUG
#Preview("App View") {
    AppView()
}
#endif
