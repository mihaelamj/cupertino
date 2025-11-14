import AppFont
import AppTheme
import SharedModels
import SwiftUI

struct WelcomeScreen: View {
    let coordinator: AuthCoordinatorImpl
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                VStack(spacing: 12) {
                    // Logo and title on same line
                    HStack(spacing: 16) {
                        IDPayLogo()

                        Text("ID Pay")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(theme.colors.label)
                    }

                    Text("Identity-based benefit payments")
                        .bdrFont(.subheadline)
                        .foregroundColor(theme.colors.label.opacity(0.7))
                }

                Spacer()

                // Login button
                Button(action: {
                    coordinator.showLogin()
                }) {
                    Text("Log In")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(theme.colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 32)
                        .contentShape(Rectangle())
                }
                .background(theme.colors.primary)
                .cornerRadius(12)
                .buttonStyle(.plain)

                // Support text
                Text("Do you have questions or need help? Contact our support team.")
                    .bdrFont(.caption)
                    .foregroundColor(theme.colors.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
            .padding()

            // Close button (top-left)
            Button(action: {
                // TODO: Handle close action
            }) {
                Text("Close")
                    .bdrFont(.body)
                    .foregroundColor(theme.colors.secondaryLabel)
            }
            .buttonStyle(.plain)
            .padding()
        }
    }
}

// MARK: - Logo

private struct IDPayLogo: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            // Background color circle
            Circle()
                .fill(theme.colors.background)
                .frame(width: 80, height: 80)

            // German flag horizontal stripes (clipped to circle)
            // Top third: Black, Middle third: Red, Bottom third: Yellow
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 80 / 3)

                Rectangle()
                    .fill(Color.red)
                    .frame(height: 80 / 3)

                Rectangle()
                    .fill(Color(red: 1.0, green: 0.807, blue: 0.0)) // German flag gold
                    .frame(height: 80 / 3)
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())
            .shadow(
                color: colorScheme == .dark ? Color.white.opacity(0.3) : Color.clear,
                radius: 8,
                x: 0,
                y: 0
            )

            // Bigger hole in the center that matches background
            Circle()
                .fill(theme.colors.background)
                .frame(width: 56, height: 56)
        }
    }
}

#if DEBUG
// Preview helper
private class PreviewAppCoordinator: AppCoordinator {
    func start() {}
    func showAuth() {}
    func showMainApp() {}
    func logout() {}
}

#Preview("Welcome Screen") {
    let appCoordinator = PreviewAppCoordinator()
    let authCoordinator = AuthCoordinatorImpl(appCoordinator: appCoordinator)
    return WelcomeScreen(coordinator: authCoordinator)
}
#endif
