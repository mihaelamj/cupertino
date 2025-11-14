import SwiftUI

public struct ComponentDocumentation: Identifiable {
    public struct Variable: Identifiable {
        public var name: String
        public var id: String { name }
        public var type: String
        public let documentation: [String]
        public let defaultValue: String

        public init(name: String, type: String, documentation: [String], defaultValue: String) {
            self.name = name
            self.type = type
            self.documentation = documentation
            self.defaultValue = defaultValue
        }
    }

    public let name: String
    public let kind: String
    public var id: String { kind }
    public let variables: [Variable]

    public init(name: String, kind: String, variables: [Variable]) {
        self.name = name
        self.kind = kind
        self.variables = variables
    }

    public nonisolated(unsafe) static var all = [Self]()
}

// MARK: - Documentation Registration

public extension ComponentDocumentation {
    /// Register system documentation from Components package
    static func registerAll() {
        // Clear existing documentation to avoid duplicates
        all.removeAll()
        registerDocumentation()
    }
}

// sourcery: inComponentsModule
public struct HelpComponent: Component {
    public struct Data: ComponentData {
        public var kind: String?

        public init(kind: String? = nil) {
            self.kind = kind
        }
    }

    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    struct Content: View {
        @State var documentations: [ComponentDocumentation]
        @State var expanded = Set<String>()

        private func isExpanded(for info: ComponentDocumentation) -> Bool {
            expanded.contains(info.name)
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading) {
                    if documentations.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 32))
                                .foregroundColor(.blue)
                            Text("No Components Available")
                                .font(.headline)
                            Text("Register components to see their documentation here")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .padding()
                    } else {
                        ForEach(documentations) { info in
                            let isExpandedBinding: Binding<Bool> = .init(get: {
                                isExpanded(for: info)
                            }, set: { expanded in
                                if expanded {
                                    self.expanded.insert(info.name)
                                } else {
                                    self.expanded.remove(info.name)
                                }
                            })
                            DisclosureGroup(isExpanded: isExpandedBinding, content: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("kind")
                                            .bold()
                                        Text(info.kind)
                                            .italic()
                                            .foregroundColor(.blue)
                                    }
                                    .font(.headline)

                                    if !info.variables.isEmpty {
                                        Text("Properties")
                                            .font(.headline)
                                            .bold()
                                        ForEach(info.variables) { field in
                                            VStack(alignment: .leading, spacing: 4) {
                                                if !field.documentation.isEmpty {
                                                    ForEach(field.documentation, id: \.self) { doc in
                                                        Text("/// " + doc)
                                                            .font(.callout)
                                                            .foregroundColor(.primary.opacity(0.6))
                                                    }
                                                }
                                                if field.defaultValue.isEmpty {
                                                    Text("\(field.name): \(field.type)")
                                                        .font(.callout)
                                                        .fontWeight(.semibold)
                                                } else {
                                                    Text("\(field.name): \(field.type) = \(field.defaultValue)")
                                                        .font(.callout)
                                                        .fontWeight(.semibold)
                                                }
                                            }
                                            .padding(.leading, 10)
                                        }
                                    }
                                }
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }, label: {
                                Text(info.name)
                                    .font(.title3)
                                    .fontWeight(.bold)
                            })
                            .padding(.vertical, 8)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: documentations.count)
                .animation(.spring, value: expanded)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.blue, lineWidth: 2)
            )
        }
    }

    public func make() -> some View {
        let allDocs = ComponentDocumentation.all
        let filteredDocs: [ComponentDocumentation]

        if let kind = data.kind {
            filteredDocs = allDocs.filter { $0.kind == kind }
        } else {
            filteredDocs = allDocs
        }

        return Content(documentations: filteredDocs)
    }
}

#Preview {
    // Preview with sample documentation
    VStack {
        HelpComponent(data: .init()).make()
    }
}
