import Foundation

public struct DummyModel: Identifiable {
    public var id: UUID = .init()
    public var title: String
    public init(
        id: UUID = .init(),
        title: String
    ) {
        self.id = id
        self.title = title
    }
}
