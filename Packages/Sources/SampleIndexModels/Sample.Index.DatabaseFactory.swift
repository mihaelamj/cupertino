import Foundation
import SharedConstants

// MARK: - Sample.Index.DatabaseFactory

/// Factory abstraction for opening a `Sample.Index.Reader`-conforming
/// database actor from a file URL. GoF Factory Method, Swift-idiomatic
/// expression — parallel to `Search.DatabaseFactory` on the docs side
/// (#494).
///
/// The composition root (the CLI / TUI binary) supplies a concrete
/// factory that opens the production `Sample.Index.Database` actor;
/// tests supply a mock that returns a stub or throws on demand.
/// Consumers (`Services.ServiceContainer.withSampleService`,
/// `withTeaserService`, `withUnifiedSearchService`) depend on this
/// protocol rather than on `import SampleIndex`, so the Services
/// target stays free of any concrete-producer dependency.
///
/// "Product" = `any Sample.Index.Reader`
/// "Creator" = `Sample.Index.DatabaseFactory` (this protocol)
/// "ConcreteCreator" = `LiveSampleIndexDatabaseFactory` in the CLI
/// (or a mock conforming type in tests).
extension Sample.Index {
    public protocol DatabaseFactory: Sendable {
        /// Open (or create) a `Sample.Index.Reader`-conforming database
        /// at `url`. The concrete factory decides which actor to
        /// instantiate.
        func openDatabase(at url: URL) async throws -> any Sample.Index.Reader
    }
}
