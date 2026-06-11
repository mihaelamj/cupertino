import Foundation
import SampleIndexModels
import SharedConstants

// MARK: - Sample.Index.Database <-> Sample.Index.Writer witness

/// `Sample.Index.Database` (the concrete actor in this SampleIndexSQLite
/// target) already implements every method on `Sample.Index.Writer`
/// (defined in `SampleIndexModels`): the protocol is the exact write
/// surface that `Sample.Index.Builder` (in the sibling SampleIndex
/// orchestration target) calls. This one-line witness lets that consumer
/// receive `any Sample.Index.Writer` while the concrete actor stays
/// unchanged.
///
/// Mirrors the read-side witness in `Sample.Index.Database.Reader.swift`
/// (`extension Sample.Index.Database: Sample.Index.Reader {}`). Added by
/// #902 alongside the SampleIndexSQLite extraction (mirror of #898 sub-PR E).
extension Sample.Index.Database: Sample.Index.Writer {}
