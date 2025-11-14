import AppFont
import AppTheme
import SharedModels
import SwiftUI

@MainActor
class AuthCoordinatorImpl: ObservableObject, AuthCoordinator {
    enum AuthStep: Equatable {
        case welcome
        case login
        case register
    }

    // Published properties
    @Published var currentStep: AuthStep = .welcome

    // Dependencies
    private weak var appCoordinator: AppCoordinator?

    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }

    // MARK: - AuthCoordinator Protocol

    func showWelcome() {
        currentStep = .welcome
    }

    func showLogin() {
        currentStep = .login
    }

    func showRegister() {
        currentStep = .register
    }

    func authenticationCompleted() {
        appCoordinator?.showMainApp()
    }

    // MARK: - View Builder

    @ViewBuilder
    func getCurrentView() -> some View {
        switch currentStep {
        case .welcome:
            WelcomeScreen(coordinator: self)
                .transition(.opacity)
        case .login:
            PlaceholderScreen(title: "Login Screen", coordinator: self)
                .transition(.opacity)
        case .register:
            PlaceholderScreen(title: "Register Screen", coordinator: self)
                .transition(.opacity)
        }
    }
}

// MARK: - Placeholder Screen

private struct PlaceholderScreen: View {
    let title: String
    let coordinator: AuthCoordinatorImpl
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                Text(title)
                    .bdrFont(.largeTitle, weight: .bold)
                    .foregroundColor(theme.colors.label)

                Spacer()

                Button(action: {
                    coordinator.showWelcome()
                }) {
                    Text("Back to Welcome")
                        .bdrFont(.body, weight: .semibold)
                        .foregroundColor(theme.colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 24)
                        .contentShape(Rectangle())
                }
                .background(theme.colors.primary)
                .cornerRadius(12)
                .buttonStyle(.plain)
            }
            .padding()
        }
    }
}
