import Foundation
import SwiftUI

@MainActor
public struct AnyComponent: Identifiable {
    private let component: any Component
    public var id: UUID = .init()
    public let kind: ComponentKind

    private let _make: () -> AnyView

    public init<ComponentType>(_ component: ComponentType) where ComponentType: Component {
        self.component = component
        kind = ComponentType.kind
        _make = {
            AnyView(component.make())
        }
    }

    public var contentView: AnyView {
        _make()
    }
}
