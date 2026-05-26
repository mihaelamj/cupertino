import Foundation
import ServicesModels

// MARK: - Services.TeaserService conformance witness

/// `Services.TeaserService` (concrete actor) satisfies the
/// `Services.Teaser` protocol declared in `ServicesModels`. The
/// actor's existing `fetchAllTeasers(query:framework:currentSource:includeArchive:)`
/// method matches the protocol signature, so this is a one-line
/// conformance witness.
extension Services.TeaserService: Services.Teaser {}
