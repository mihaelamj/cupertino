import Foundation
import SearchModels

// MARK: - CupertinoDataEngine.PackageReaderFactory

extension CupertinoDataEngine {
    /// Read-only package-search reader owned by the data engine.
    ///
    /// `Search.PackagesSearcher` intentionally exposes only query behavior.
    /// The engine also owns connection lifecycle, so internal reader factories
    /// return this refinement and public callers still receive the narrower
    /// `Search.PackagesSearcher` interface from ``packages()``.
    @_spi(CupertinoInternal)
    public protocol PackageReader: Search.PackagesSearcher {
        func disconnect() async
    }

    /// Factory abstraction for opening the packages corpus reader behind the
    /// Cupertino backend boundary.
    ///
    /// Concrete implementations live in composition roots that import
    /// Cupertino-owned storage producers. UI packages pass around `CupertinoDataEngine`
    /// and never construct storage readers directly.
    @_spi(CupertinoInternal)
    public protocol PackageReaderFactory: Sendable {
        func openPackageReader(at url: URL) async throws -> any PackageReader
    }
}
