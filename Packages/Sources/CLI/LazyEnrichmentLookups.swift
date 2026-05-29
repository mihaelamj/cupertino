import AppleConstraintsKit
import Foundation
import SearchModels

// MARK: - Deferred, file-backed enrichment lookups

/// `Search.StaticConstraintsLookup` that defers reading
/// `apple-constraints.json` until the enrichment pass first queries it (the
/// END of a save), not save start.
///
/// The enrichment passes run after all indexing finishes, so the input is not
/// needed until then. Loading lazily lets an operator produce the file with
/// `cupertino-constraints-gen` *while* a long index runs; the freshly written
/// table is read at the enrichment phase and applied. A missing or unparseable
/// file yields an empty table (best-effort: the save proceeds un-enriched, it
/// does not throw). The table is read once and cached.
actor LazyConstraintsLookup: Search.StaticConstraintsLookup {
    private let path: URL
    private var cached: [Search.StaticConstraintEntry]?

    init(path: URL) {
        self.path = path
    }

    func allEntries() async throws -> [Search.StaticConstraintEntry] {
        if let cached {
            return cached
        }
        var loaded: [Search.StaticConstraintEntry] = []
        if FileManager.default.fileExists(atPath: path.path),
           let table = try? AppleConstraintsKit.Table.from(fileURL: path) {
            loaded = await (try? table.allEntries()) ?? []
        }
        cached = loaded
        return loaded
    }
}

/// Conformance sibling of ``LazyConstraintsLookup``: defers reading
/// `apple-conformances.json` to the enrichment phase. Same rationale
/// (produce-during-save) and same best-effort, read-once semantics.
actor LazyConformancesLookup: Search.StaticConformancesLookup {
    private let path: URL
    private var cached: [Search.StaticConformanceEntry]?

    init(path: URL) {
        self.path = path
    }

    func allConformanceEntries() async throws -> [Search.StaticConformanceEntry] {
        if let cached {
            return cached
        }
        var loaded: [Search.StaticConformanceEntry] = []
        if FileManager.default.fileExists(atPath: path.path),
           let table = try? AppleConstraintsKit.ConformanceTable.from(fileURL: path) {
            loaded = await (try? table.allConformanceEntries()) ?? []
        }
        cached = loaded
        return loaded
    }
}
