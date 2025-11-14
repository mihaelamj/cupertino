import Components
import SwiftUI

public struct BenefitCardComponent: Component {
    public struct Data: ComponentData {
        /// Background image name from Assets
        public var backgroundImage: String = "benefit_climate"

        /// Main title text
        public var title: String

        /// Description text
        public var description: String

        /// Badge text (e.g., "One-time payment", "Recurring benefit in kind")
        public var badgeText: String

        /// Status badge text
        public var statusText: String = "Aktiv"

        /// Whether status is active
        public var isActive: Bool = true

        /// Corner radius
        public var cornerRadius: CGFloat = 16

        public init(
            backgroundImage: String = "benefit_climate",
            title: String,
            description: String,
            badgeText: String,
            statusText: String = "Aktiv",
            isActive: Bool = true,
            cornerRadius: CGFloat = 16
        ) {
            self.backgroundImage = backgroundImage
            self.title = title
            self.description = description
            self.badgeText = badgeText
            self.statusText = statusText
            self.isActive = isActive
            self.cornerRadius = cornerRadius
        }
    }

    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public func make() -> some View {
        BenefitCardContent(data: data)
    }
}

struct BenefitCardContent: View {
    var data: BenefitCardComponent.Data
    @State private var isPressed = false

    var body: some View {
        ZStack {
            // Background image
            GeometryReader { geometry in
                Image(data.backgroundImage, bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }

            // Gradient overlay — strong at bottom for text readability
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.6),
                    Color.black.opacity(0.25),
                    Color.black.opacity(0.0),
                ]),
                startPoint: .bottom,
                endPoint: .top
            )

            VStack(alignment: .leading, spacing: 10) {
                // Top row with badges
                HStack {
                    // Left badge
                    Text(data.badgeText)
                        .font(.caption)
                        .fontWeight(.regular) // was .medium
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Color.white.opacity(0.85) // was 0.9, now a touch more transparent
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                        ) // was Capsule()
                        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)

                    Spacer()

                    // Right badge (status)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(data.isActive ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)

                        Text(data.statusText)
                            .font(.caption)
                            .fontWeight(.regular) // was .medium
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Color.white.opacity(0.85)
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
                }

                Spacer(minLength: 0)

                // Title + description
                VStack(alignment: .leading, spacing: 4) {
                    Text(data.title)
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(data.description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
            }
            .padding(12)
        }
        .frame(height: 160) // was 190; feel free to drop to 150 if you want it even tighter
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3) // bottom-oriented shadow
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .onTapGesture {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isPressed = false
            }
        }
    }
}

struct BenefitCardContentOld: View {
    var data: BenefitCardComponent.Data
    @State private var isPressed = false

    var body: some View {
        ZStack {
            // Background image
            GeometryReader { geometry in
                Image(data.backgroundImage, bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }

            // Gradient overlay — keep this strong enough for text readability
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.6),
                    Color.black.opacity(0.25),
                    Color.black.opacity(0.0),
                ]),
                startPoint: .bottom,
                endPoint: .top
            )

            VStack(alignment: .leading, spacing: 10) {
                // Top row with badges
                HStack {
                    Text(data.badgeText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)

                    Spacer()

                    HStack(spacing: 5) {
                        Circle()
                            .fill(data.isActive ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)

                        Text(data.statusText)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
                }

                Spacer(minLength: 0)

                // Title + description
                VStack(alignment: .leading, spacing: 4) {
                    Text(data.title)
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(data.description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
            }
            .padding(12)
        }
        .frame(height: 190) // ⬅️ smaller, more elegant proportion
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .onTapGesture {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isPressed = false
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        BenefitCardComponent(data: .init(
            title: "Health Insurance",
            description: "Comprehensive coverage for you and your family",
            badgeText: "Badge 1"
        )).make()

        BenefitCardComponent(data: .init(
            title: "Retirement Plan",
            description: "Secure your future with our 401(k) plan",
            badgeText: "Badge 1"
        )).make()

        BenefitCardComponent(data: .init(
            title: "Flexible Holidays",
            description: "Enjoy up to 30 days of paid time off",
            badgeText: "Hello"
        )).make()
    }
    .padding()
}
