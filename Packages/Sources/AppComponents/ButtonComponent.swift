import AppFont
import AppTheme
import Components
import SwiftUI

public struct ButtonComponent: Component {
    public struct Data: ComponentData {
        public let title: String
        public let style: ButtonStyle
        public let isEnabled: Bool
        public let isLoading: Bool

        public enum ButtonStyle: String, Codable, Sendable {
            case primary
            case secondary
            case danger
            case custom
        }

        public init(
            title: String,
            style: ButtonStyle = .primary,
            isEnabled: Bool = true,
            isLoading: Bool = false
        ) {
            self.title = title
            self.style = style
            self.isEnabled = isEnabled
            self.isLoading = isLoading
        }
    }

    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public func make() -> some View {
        ButtonContent(data: data)
    }
}

struct ButtonContent: View {
    let data: ButtonComponent.Data
    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: {}, label: {
            HStack(spacing: 8) {
                if data.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(foregroundColor)
                }

                Text(data.title)
                    .bdrFont(.body)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(12)
            .opacity(data.isEnabled ? 1 : 0.6)
        })
        .buttonStyle(.plain)
        .disabled(!data.isEnabled || data.isLoading)
    }

    private var backgroundColor: Color {
        guard data.isEnabled else {
            return theme.colors.secondary.opacity(0.5)
        }

        switch data.style {
        case .primary:
            return theme.colors.primary
        case .secondary:
            return theme.colors.secondaryBackground
        case .danger:
            return theme.colors.destructive
        case .custom:
            return theme.colors.primary
        }
    }

    private var foregroundColor: Color {
        switch data.style {
        case .primary:
            return theme.colors.onPrimary
        case .secondary:
            return theme.colors.label
        case .danger:
            return theme.colors.onPrimary
        case .custom:
            return theme.colors.onPrimary
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ButtonComponent(data: .init(title: "Primary", style: .primary)).make()
        ButtonComponent(data: .init(title: "Secondary", style: .secondary)).make()
        ButtonComponent(data: .init(title: "Danger", style: .danger)).make()
        ButtonComponent(data: .init(title: "Disabled", isEnabled: false)).make()
        ButtonComponent(data: .init(title: "Loading", isLoading: true)).make()
    }
    .padding()
}
