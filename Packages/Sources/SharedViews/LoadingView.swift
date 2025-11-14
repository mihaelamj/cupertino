import AppFont
import AppTheme
import SwiftUI

public struct LoadingView: View {
    let message: String
    @Environment(\.appTheme) private var theme

    public init(message: String = "Loading...") {
        self.message = message
    }

    public var body: some View {
        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)

                Text(message)
                    .bdrFont(.subheadline)
                    .foregroundColor(theme.colors.secondaryLabel)
            }
        }
    }
}

#if DEBUG
#Preview("Loading") {
    LoadingView(message: "Loading your benefits...")
}
#endif
