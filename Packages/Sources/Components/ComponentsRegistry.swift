import Foundation

// Helper Factory

public struct ComponentFactory: Sendable {
    public let kind: ComponentKind

    // This closure can ONLY be called on the main actor.
    private let _makeRenderable: @MainActor () -> AnyComponent

    // This init can run off-main. We're not *calling* the closure yet,
    // we're just storing it.
    public init<C: Component>(data: C.Data, type: C.Type) {
        kind = C.kind
        _makeRenderable = {
            // This block runs later, on the main actor.
            let instance = C(data: data)
            return AnyComponent(instance)
        }
    }

    // You call this on the main actor, right before rendering.
    @MainActor
    public func makeRenderable() -> AnyComponent {
        _makeRenderable()
    }
}

// MARK: - Component Registry Management

/// Namespace for component registration methods
public enum ComponentRegistry {
    /// Register all system components from Components package
    public static func registerAll(in registry: ComponentsRegistry) {
        // Use auto-generated registration from Sourcery
        registerComponents(in: registry)
    }
}

public final class ComponentsRegistry {
    public typealias ComponentDecoder =
        @Sendable (KeyedDecodingContainer<Container.CodingKeys>) throws -> ComponentFactory

    public var decoders: [ComponentKind: ComponentDecoder] = [:]

    public struct Container: Decodable {
        public enum CodingKeys: CodingKey {
            case kind
            case payload
        }

        public struct ComponentNotFound: Error {
            public var kind: ComponentKind
        }

        public struct DecodersNotFound: Error {}

        // swiftlint:disable:next force_unwrapping
        public static let decodersKey = CodingUserInfoKey(rawValue: "ComponentDecoders")!

        public let factory: ComponentFactory

        public init(from decoder: Decoder) throws {
            // grab the decoder map
            guard let decoders = decoder.userInfo[Self.decodersKey] as? [ComponentKind: ComponentDecoder] else {
                throw DecodersNotFound()
            }

            // decode envelope
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(ComponentKind.self, forKey: .kind)

            // find decoder for that kind
            guard let decodeForKind = decoders[kind] else {
                throw ComponentNotFound(kind: kind)
            }

            // decode data payload into a ComponentFactory
            factory = try decodeForKind(container)
        }
    }

    public init() {}

    // Now decode returns factories, not AnyComponent yet.
    public func decodeFactories(from data: Data) -> [ComponentFactory] {
        do {
            let decoder = JSONDecoder()
            decoder.userInfo[Container.decodersKey] = decoders
            let containers = try decoder.decode([Container].self, from: data)
            return containers.map(\.factory)
        } catch {
            print("Unable to parse \(error)")
            return []
        }
    }
}

public class ComponentsRegistryOld {
    public typealias ComponentDecoder = @Sendable (KeyedDecodingContainer<Container.CodingKeys>) throws -> AnyComponent

    public var decoders: [ComponentKind: ComponentDecoder] = [:]

    public struct Container: Decodable {
        public enum CodingKeys: CodingKey {
            case kind
            case payload
        }

        public struct ComponentNotFound: Error {
            public var kind: ComponentKind
        }

        public struct DecodersNotFound: Error {}

        // swiftlint:disable:next force_unwrapping
        public static let decodersKey = CodingUserInfoKey(rawValue: "ComponentDecoders")!

        public let component: AnyComponent
        public init(from decoder: Decoder) throws {
            guard let decoders = decoder.userInfo[Self.decodersKey] as? [ComponentKind: ComponentDecoder] else {
                throw DecodersNotFound()
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(ComponentKind.self, forKey: .kind)

            guard let factory = decoders[kind] else {
                throw ComponentNotFound(kind: kind)
            }

            component = try factory(container)
        }
    }

    public func decode(from data: Data) -> [AnyComponent] {
        do {
            let decoder = JSONDecoder()
            decoder.userInfo[Container.decodersKey] = decoders
            let containers = try decoder.decode([Container].self, from: data)
            return containers.map(\.component)
        } catch {
            print("Unable to parse \(error)")
            return []
        }
    }
}
