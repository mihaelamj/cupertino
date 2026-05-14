import Foundation
import SampleIndexModels
import SharedConstants

// MARK: - Sample.Search.Service conformance witness

/// `Sample.Search.Service` (concrete actor in this target) satisfies
/// the `Sample.Search.Searcher` protocol declared in `SampleIndexModels`.
/// The actor's existing `search(_:) async throws -> Sample.Search.Result`
/// already matches the protocol method-for-method, so this is a
/// one-line conformance with no body.
///
/// Mirrors the `Sample.Index.Database: Sample.Index.Reader` witness
/// pattern in #475 and the `Services.DocsSearchService: Services.DocsSearcher`
/// witness alongside it.
extension Sample.Search.Service: Sample.Search.Searcher {}
