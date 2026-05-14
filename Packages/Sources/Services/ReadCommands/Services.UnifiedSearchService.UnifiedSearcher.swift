import Foundation
import ServicesModels

// MARK: - Services.UnifiedSearchService conformance witness

/// `Services.UnifiedSearchService` (concrete actor) satisfies the
/// `Services.UnifiedSearcher` protocol declared in `ServicesModels`.
/// The actor's existing `searchAll(query:framework:limit:)` method
/// matches the protocol signature, so this is a one-line conformance
/// witness.
extension Services.UnifiedSearchService: Services.UnifiedSearcher {}
