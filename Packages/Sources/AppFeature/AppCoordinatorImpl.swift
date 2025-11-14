import AppFont
import AuthFeature
import SharedModels
import SharedViews
import SwiftUI

@MainActor
class AppCoordinatorImpl: ObservableObject, AppCoordinator {
    enum AppState: Equatable {
        case loading
        case auth
        case mainApp
    }

    // State
    @Published var currentState: AppState = .loading

    init() {
        // Register custom fonts on startup
        FontRegistration.registerFonts()
    }

    // MARK: - AppCoordinator Protocol

    func start() {
        currentState = .loading

        // Simulate checking authentication
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            // TODO: Check KeyChain for token
            let hasToken = false // Placeholder
            if hasToken {
                self?.showMainApp()
            } else {
                self?.showAuth()
            }
        }
    }

    func showAuth() {
        currentState = .auth
    }

    func showMainApp() {
        currentState = .mainApp
    }

    func logout() {
        // TODO: Clear token from KeyChain
        showAuth()
    }

    // MARK: - View Builder

    @ViewBuilder
    func getCurrentView() -> some View {
        switch currentState {
        case .loading:
            SharedViews.LoadingView(message: "Loading...")
                .transition(.opacity)

        case .auth:
            AuthFlowView(appCoordinator: self)
                .transition(.opacity)

        case .mainApp:
            // Placeholder for MainTabView
            PlaceholderView(title: "Main App", message: "TabBar with Benefits/Banks/Profile")
                .transition(.opacity)
        }
    }
}

// MARK: - Placeholder View

private struct PlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.title)
                .fontWeight(.bold)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}
