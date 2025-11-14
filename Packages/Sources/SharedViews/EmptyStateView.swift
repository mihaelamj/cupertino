import AppFont
import AppTheme
import SwiftUI

public struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    @Environment(\.appTheme) private var theme

    public init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(theme.colors.secondaryLabel)

            Text(title)
                .bdrFont(.headline)
                .foregroundColor(theme.colors.label)

            Text(message)
                .bdrFont(.body)
                .foregroundColor(theme.colors.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let actionTitle, let action {
                Button(action: {
                    action()
                }) {
                    Text(actionTitle)
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
#Preview("Empty State") {
    EmptyStateView(
        icon: "tray",
        title: "No Benefits Yet",
        message: "You don't have any benefits available at the moment. Check back later.",
        actionTitle: "Refresh",
        action: { print("Refresh tapped") }
    )
}
#endif
