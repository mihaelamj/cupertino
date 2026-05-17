import Foundation
import SearchModels

extension AppleConstraintsKit {
    /// Stateless extractor that consumes one symbol-graph JSON file
    /// and emits the filtered `Search.StaticConstraintEntry` values.
    ///
    /// **Pipeline.**
    /// 1. JSON-decode the file into `SymbolGraph.Document`.
    /// 2. For each symbol that has `swiftGenerics.constraints`:
    ///    a. Filter the constraint array to entries where
    ///       `contributesToSearchAxis` is true (drops `sameType` /
    ///       layout requirements).
    ///    b. Skip the symbol if no constraints survive the filter.
    ///    c. Map `module.name` + `pathComponents` → cupertino URI
    ///       via `URIMapper.uri(forModule:pathComponents:)`.
    ///    d. Emit a `StaticConstraintEntry(docURI:, constraints:)`
    ///       carrying the constraint `rhs` halves.
    ///
    /// **Sequencing.** Caller loops over multiple symbol-graph files
    /// (one Apple module per `Document`, plus cross-module-extension
    /// files like `SwiftUI@Foundation.symbols.json`) and concatenates
    /// the entry arrays. Last-write-wins is acceptable because the
    /// same URI rarely appears in two symbol-graphs from one SDK.
    ///
    /// **Memory.** The 456 MB SwiftUI symbol-graph decodes to roughly
    /// 1-2 GB of in-memory `SymbolGraph.Document` (Swift's
    /// `JSONDecoder` is not streaming). Acceptable for one-shot
    /// generator runs on a workstation. The output entry list is
    /// orders of magnitude smaller (~15-30k entries across all
    /// frameworks, ~3-6 MB of JSON-on-disk after re-encode).
    ///
    /// **Pure / stateless.** No collaborators; takes the JSON `Data`
    /// in and returns entries. Lifts standalone, testable in isolation.
    public enum Extractor {
        public enum Error: Swift.Error, Sendable, Equatable {
            case decodeFailed(message: String)
        }

        /// Decode one symbol-graph file's `Data` and emit the
        /// constraint entries. Throws `Error.decodeFailed` on
        /// malformed JSON; returns `[]` if the file is well-formed
        /// but carries no constraint-bearing symbols (a real case for
        /// trivial extension files).
        public static func extractEntries(from data: Data) throws -> [Search.StaticConstraintEntry] {
            let document: SymbolGraph.Document
            do {
                document = try JSONDecoder().decode(SymbolGraph.Document.self, from: data)
            } catch {
                throw Error.decodeFailed(message: String(describing: error))
            }
            return extractEntries(from: document)
        }

        /// Same as `extractEntries(from data:)` but takes an
        /// already-decoded document. Exposed so the test suite can
        /// feed in-memory fixtures without serialising to JSON first.
        public static func extractEntries(
            from document: SymbolGraph.Document
        ) -> [Search.StaticConstraintEntry] {
            var entries: [Search.StaticConstraintEntry] = []
            entries.reserveCapacity(document.symbols.count / 4)

            for symbol in document.symbols {
                guard let raw = symbol.swiftGenerics?.constraints, !raw.isEmpty else {
                    continue
                }
                let constraintRHS = raw
                    .filter(\.contributesToSearchAxis)
                    .map(\.rhs)
                guard !constraintRHS.isEmpty else {
                    continue
                }
                guard let uri = URIMapper.uri(
                    forModule: document.module.name,
                    pathComponents: symbol.pathComponents
                ) else {
                    continue
                }
                entries.append(Search.StaticConstraintEntry(
                    docURI: uri,
                    constraints: constraintRHS
                ))
            }

            return entries
        }
    }
}
