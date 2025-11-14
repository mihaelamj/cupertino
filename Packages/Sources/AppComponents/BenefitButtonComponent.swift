import AppFont
import AppTheme
import Components
import SwiftUI

public struct BenefitButtonComponent: Component {
    public struct Data: ComponentData {
        /// Button text
        public var text: String

        /// Button style: "black" or "white"
        public var style: String = "black"

        /// Corner radius
        public var cornerRadius: CGFloat = 12

        /// Full width
        public var fullWidth: Bool = true

        public init(
            text: String,
            style: String = "black",
            cornerRadius: CGFloat = 12,
            fullWidth: Bool = true
        ) {
            self.text = text
            self.style = style
            self.cornerRadius = cornerRadius
            self.fullWidth = fullWidth
        }
    }

    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public func make() -> some View {
        BenefitButtonContent(data: data)
    }
}

struct BenefitButtonContent: View {
    var data: BenefitButtonComponent.Data
    @State private var isPressed = false
    @Environment(\.appTheme) private var theme

    private var isBlackStyle: Bool {
        data.style.lowercased() == "black"
    }

    var body: some View {
        Text(data.text)
            .bdrFont(.body, weight: .semibold)
            .foregroundColor(isBlackStyle ? theme.colors.onPrimary : theme.colors.primary)
            .frame(maxWidth: data.fullWidth ? .infinity : nil)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(isBlackStyle ? theme.colors.primary : theme.colors.background)
            .cornerRadius(data.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: data.cornerRadius)
                    .stroke(isBlackStyle ? Color.clear : theme.colors.primary, lineWidth: isBlackStyle ? 0 : 1.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .onTapGesture {
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                }
            }
    }
}
