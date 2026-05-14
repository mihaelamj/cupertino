import Foundation
import ServicesModels

// MARK: - Services.DocsSearchService conformance witness

/// `Services.DocsSearchService` (concrete actor) satisfies the
/// `Services.DocsSearcher` protocol declared in `ServicesModels`. The
/// method signature already matches — `search(_ query:)
/// async throws -> [Search.Result]` is the actor's existing public
/// method — so this is a one-line conformance with no body.
///
/// Lives in the `Services` target so consumers (`SearchToolProvider`)
/// can hold `any Services.DocsSearcher` after importing only
/// `ServicesModels`. The CLI composition root constructs the actor and
/// passes it across the seam as a `Services.DocsSearcher` existential.
extension Services.DocsSearchService: Services.DocsSearcher {}
