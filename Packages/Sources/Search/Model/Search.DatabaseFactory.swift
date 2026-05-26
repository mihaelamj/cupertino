import Foundation

// MARK: - Search.DatabaseFactory

/// Factory abstraction for opening a `Search.Database`-conforming
/// actor from a file URL. GoF Factory Method, Swift-idiomatic
/// expression.
///
/// The composition root (the CLI binary) supplies a concrete factory
/// that opens the production `Search.Index` actor; tests supply a
/// mock that returns a stub or throws on demand. Consumers
/// (`Services.ServiceContainer.with*Service` static methods,
/// `Services.ReadService`) depend on this protocol rather than on a
/// `@Sendable (URL) async throws -> any Search.Database` closure so
/// the contract is named, the injection point is named, and the
/// captured-state surface is explicit (it lives on the conforming
/// type's stored properties, not in a closure's implicit capture
/// list).
///
/// This is the GoF Factory Method pattern in Swift:
/// - "Product" = `any Search.Database`
/// - "Creator" = `Search.DatabaseFactory` protocol (this file)
/// - "ConcreteCreator" = `LiveSearchDatabaseFactory` in the CLI (or a
///   `MockSearchDatabaseFactory` in tests)
extension Search {
    public protocol DatabaseFactory: Sendable {
        /// Open (or create) a `Search.Database` at `url`. The
        /// concrete factory decides which actor to instantiate.
        func openDatabase(at url: URL) async throws -> any Search.Database
    }
}
