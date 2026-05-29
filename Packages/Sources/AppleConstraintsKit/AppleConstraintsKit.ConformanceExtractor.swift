import Foundation
import SearchModels

extension AppleConstraintsKit {
    /// Stateless extractor that consumes one symbol-graph JSON file and emits
    /// `Search.StaticConformanceEntry` values: the full SDK conformance graph
    /// the rendered DocC markdown omits. Conformance analogue of `Extractor`
    /// (which does generic constraints from the same files).
    ///
    /// **Pipeline.**
    /// 1. Decode the file into `SymbolGraph.Document`.
    /// 2. Build a `USR -> pathComponents` map from `document.symbols`.
    /// 3. For each `conformsTo` / `inheritsFrom` relationship:
    ///    a. Resolve `source` USR to a path (this module's symbols) and map
    ///       `module + path -> apple-docs://` URI via `URIMapper`.
    ///    b. Take the protocol / superclass name from `targetFallback`
    ///       (reduced to its last dot-component), or the local target's last
    ///       path component.
    ///    c. Group by conforming-type URI, de-duplicating names in first-seen
    ///       order.
    ///
    /// **Pure / stateless.** No collaborators; lifts and tests in isolation.
    public enum ConformanceExtractor {
        public enum Error: Swift.Error, Sendable, Equatable {
            case decodeFailed(message: String)
        }

        public static func extractEntries(from data: Data) throws -> [Search.StaticConformanceEntry] {
            let document: SymbolGraph.Document
            do {
                document = try JSONDecoder().decode(SymbolGraph.Document.self, from: data)
            } catch {
                throw Error.decodeFailed(message: String(describing: error))
            }
            return extractEntries(from: document)
        }

        public static func extractEntries(
            from document: SymbolGraph.Document
        ) -> [Search.StaticConformanceEntry] {
            guard let relationships = document.relationships, !relationships.isEmpty else {
                return []
            }

            var pathByUSR: [String: [String]] = [:]
            pathByUSR.reserveCapacity(document.symbols.count)
            for symbol in document.symbols {
                if let usr = symbol.identifier?.precise {
                    pathByUSR[usr] = symbol.pathComponents
                }
            }

            var conformsByURI: [String: [String]] = [:]
            var uriOrder: [String] = []

            for relationship in relationships where relationship.contributesToConformanceGraph {
                guard let sourcePath = pathByUSR[relationship.source],
                      let uri = URIMapper.uri(forModule: document.module.name, pathComponents: sourcePath)
                else {
                    continue
                }
                guard let name = conformanceName(for: relationship, pathByUSR: pathByUSR) else {
                    continue
                }
                if conformsByURI[uri] == nil {
                    uriOrder.append(uri)
                }
                if !(conformsByURI[uri]?.contains(name) ?? false) {
                    conformsByURI[uri, default: []].append(name)
                }
            }

            return uriOrder.map {
                Search.StaticConformanceEntry(docURI: $0, conformsTo: conformsByURI[$0] ?? [])
            }
        }

        /// Protocol / superclass display name. Prefer `targetFallback` (present
        /// even for cross-module targets, e.g. `"SwiftUICore.View"`), reduced to
        /// its last dot-component (`"View"`); else the local target's last path
        /// component; else nil (skip the edge).
        private static func conformanceName(
            for relationship: SymbolGraph.Relationship,
            pathByUSR: [String: [String]]
        ) -> String? {
            if let fallback = relationship.targetFallback, !fallback.isEmpty {
                return fallback.split(separator: ".").last.map(String.init) ?? fallback
            }
            if let targetPath = pathByUSR[relationship.target], let last = targetPath.last {
                return last
            }
            return nil
        }
    }
}
