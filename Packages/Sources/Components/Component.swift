import Foundation
import SwiftUI

public protocol ComponentData: Hashable, Decodable, Sendable {}
public typealias ComponentKind = String

public protocol Component: Sendable {
    associatedtype Data: ComponentData
    associatedtype ViewBody: View

    var data: Data { get }

    /// Build the SwiftUI view for this component.
    /// This must run on the main actor because SwiftUI view
    /// construction and state are main-actor isolated.
    @MainActor
    func make() -> ViewBody

    static var kind: ComponentKind { get }
    init(data: Data)
}

private struct _SendableComponentType<C: Component>: @unchecked Sendable {
    let type: C.Type
}

public extension Component {
    @inline(__always)
    static var kind: ComponentKind {
        String(describing: Self.self)
            .replacingOccurrences(of: "Component", with: "")
            .lowercased()
    }

    static func register(in registry: ComponentsRegistry) {
        let componentType = Self.self // capture metatype *outside* the @Sendable closure
        let dataType = Self.Data.self

        // Wrap the metatype so Swift knows it's Sendable.
        let boxed = _SendableComponentType(type: componentType)

        registry.decoders[kind] = { decoder in
            // decode the component's Data off-main:
            let data = try decoder.decode(dataType, forKey: .payload)

            // build a ComponentFactory that *knows how* to turn into AnyComponent
            // later on the main actor
            return ComponentFactory(data: data, type: boxed.type)
        }
    }
}
