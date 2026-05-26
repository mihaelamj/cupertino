import Foundation
import SampleIndexModels
import SharedConstants

// MARK: - Sample.Index.Database conformance witness

/// `Sample.Index.Database` (concrete actor) satisfies the
/// `Sample.Index.Reader` protocol declared in `SampleIndexModels`. The
/// method signatures already match — every read method named in the
/// protocol exists on the actor with the exact same shape — so this is
/// a one-line conformance witness with no body.
///
/// Lives in the `SampleIndex` target so that target imports
/// `SampleIndexModels` and exposes the conformance; consumers
/// (`Services`, `SearchToolProvider`) only need to import
/// `SampleIndexModels` to see `any Sample.Index.Reader` and the
/// compiler picks the concrete witness up at the composition root.
extension Sample.Index.Database: Sample.Index.Reader {}
