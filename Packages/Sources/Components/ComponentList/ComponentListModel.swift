import Foundation
import KZFileWatchers
import SharedComponents

/// Protocol for registering components and documentation
public protocol ComponentRegistrar {
    func registerComponents(in registry: ComponentsRegistry)
    func registerDocumentation()
}

/// Default registrar that only registers Components package
public struct SystemComponentRegistrar: ComponentRegistrar {
    public init() {}

    public func registerComponents(in registry: ComponentsRegistry) {
        ComponentRegistry.registerAll(in: registry)
    }

    public func registerDocumentation() {
        ComponentDocumentation.registerAll()
    }
}

@MainActor
@Observable
public class ComponentListModel {
    // MARK: - Public observable state (UI-facing)

    var components = [AnyComponent]()

    // MARK: - Private state

    private var registry: ComponentsRegistry = .init()

    @ObservationIgnored
    private var registrar: ComponentRegistrar

    @ObservationIgnored
    var fileWatcher: FileWatcher.Local?

    // MARK: - Private helpers

    #if os(iOS)
    private static func calculateJSONPath(jsonPath: String?, filePath: String) -> String {
        if let jsonPath {
            return jsonPath
        } else {
            var codePath = filePath.components(separatedBy: "/")
            codePath.removeLast(2) // Remove "ComponentList/ComponentListModel.swift"
            return codePath.joined(separator: "/") + "/components.json"
        }
    }

    #elseif os(macOS)
    private static func calculateJSONPath(jsonPath: String?, filePath: String) -> String {
        if let jsonPath {
            return jsonPath
        } else {
            var codePath = filePath.components(separatedBy: "/")
            codePath.removeLast(2) // Remove "ComponentList/ComponentListModel.swift"
            return codePath.joined(separator: "/") + "/components.json"
        }
    }
    #endif

    // MARK: - Init

    public init(registrar: ComponentRegistrar = SystemComponentRegistrar(), jsonPath: String? = nil) {
        print("🔵 ComponentListModel.init() starting")
        print("🔵 #file = \(#file)")
        print("🔵 #filePath = \(#filePath)")
        self.registrar = registrar

        // Calculate path from #filePath (full absolute path) instead of #file
        let calculatedPath = Self.calculateJSONPath(jsonPath: jsonPath, filePath: #filePath)
        print("🔵 Calculated jsonPath: \(calculatedPath)")

        // Register components and documentation using the provided registrar
        registrar.registerComponents(in: registry)
        registrar.registerDocumentation()

        // Capture registry in a local constant so we can use it from the watcher
        // without re-touching self (which is @MainActor) from background code.
        let registryForWatcher = registry

        // Create and start file watcher
        let watcher = FileWatcher.Local(path: calculatedPath)
        do {
            try watcher.start { [weak self] status in
                print("🔥 FileWatcher detected change: \(status)")

                switch status {
                case .noChanges:
                    break

                case let .updated(data: data):
                    // 1. Decode factories off-main (this is pure data work,
                    //    does not touch @MainActor types)
                    let factories = registryForWatcher.decodeFactories(from: data)

                    // 2. Hop back to main actor to build UI components
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }

                        // 2a. Turn each factory into a renderable AnyComponent.
                        //     makeRenderable() is @MainActor, and this block is on main.
                        let rendered = factories.map { factory in
                            factory.makeRenderable()
                        }

                        // 2b. Update observable state on the main actor (legal)
                        self.components = rendered
                        print("🔥 Reloaded \(rendered.count) components")
                    }
                }
            }

            fileWatcher = watcher
            print("✅ FileWatcher started successfully!")
        } catch {
            print("⚠️ FileWatcher failed to start: \(error)")
            print("ℹ️ Continuing without file watching. Components loaded from registrar.")
        }
    }
}
