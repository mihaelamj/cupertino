import AppFont
import AppTheme
import SwiftUI

public struct ErrorView: View {
    let title: String
    let message: String
    let retryAction: (() -> Void)?
    @Environment(\.appTheme) private var theme

    public init(
        title: String = "Something went wrong",
        message: String,
        retryAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.retryAction = retryAction
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(theme.colors.destructive)

            Text(title)
                .bdrFont(.headline)
                .foregroundColor(theme.colors.label)

            Text(message)
                .bdrFont(.body)
                .foregroundColor(theme.colors.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let retryAction {
                Button(action: {
                    retryAction()
                }) {
                    Text("Try Again")
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
        }
        .padding()
    }
}

#if DEBUG
#Preview("Error") {
    ErrorView(
        title: "Connection Failed",
        message: "Unable to connect to the server. Please check your internet connection.",
        retryAction: { print("Retry tapped") }
    )
}
#endif
