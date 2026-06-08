import Foundation
import SearchModels

// MARK: - CupertinoDataEngine.PackageDatabaseFactory

extension CupertinoDataEngine {
    /// Read-only package-search connection owned by the data engine.
    ///
    /// `Search.PackagesSearcher` intentionally exposes only query behavior.
    /// The engine also owns connection lifecycle, so package database factories
    /// return this refinement and public callers still receive the narrower
    /// `Search.PackagesSearcher` interface from ``packages()``.
    public protocol PackageConnection: Search.PackagesSearcher {
        func disconnect() async
    }

    /// Factory abstraction for opening the packages database behind the
    /// engine boundary.
    ///
    /// Concrete implementations live in composition roots that import
    /// SQLite-backed producers. UI packages pass around `CupertinoDataEngine`
    /// and never construct a database reader directly.
    public protocol PackageDatabaseFactory: Sendable {
        func openDatabase(at url: URL) async throws -> any PackageConnection
    }
}
