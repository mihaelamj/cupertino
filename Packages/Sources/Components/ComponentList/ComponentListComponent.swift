import SwiftUI

// Not a Component - used internally to avoid recursion
struct ComponentListComponent {
    struct Data {
        let title: String

        init(title: String = "Components") {
            self.title = title
        }
    }

    var data: Data

    func make() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(data.title)
                .font(.headline)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: 12) {
                    Text("Component Registry")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
}

#Preview {
    ComponentListComponent(data: .init()).make()
}
