import AppComponents
import Components
import Foundation
import SwiftUI

/// Registrar that includes all component packages
public struct AllComponentsRegistrar: ComponentRegistrar {
    public init() {}

    public func registerComponents(in registry: ComponentsRegistry) {
        // Register system components from Components package
        ComponentRegistry.registerAll(in: registry)

        // Register components from AppComponents package
        AppComponents.registerComponents(in: registry)
    }

    public func registerDocumentation() {
        // Register documentation from Components package
        ComponentDocumentation.registerAll()

        // Register documentation from AppComponents package
        AppComponents.registerDocumentation()
    }
}
