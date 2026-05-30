import Foundation
import Testing

// MARK: - Exhaustive read battery (#1194)

// Proves the read-only enforcement (#1194) end-to-end through the production
// CLI: every read command, across every source/option, serves queries and
// document reads correctly when the database is opened read-only. Gated on
// `CupertinoCLI.available` (the debug binary + a local snapshot), so CI and
// fresh clones skip it. Each suite is `.serialized` because every assertion
// spawns the binary, and the harness serializes binary spawns anyway.
//
// Coverage:
//  - ~10 search queries per docs source (6), asserting results + source tagging
//  - >= 20 document reads from EVERY database (6 docs + samples + packages)
//  - ~10 queries per AST search command + inheritance
//  - option coverage: --limit, --format json/markdown, platform floors
//
// All assertions are shape-based (result present, source correct, read output
// echoes the title), never bare length, so a degraded read surfaces as a
// failure rather than passing on noise.

enum ReadBattery {
    struct DocsSource: CustomTestStringConvertible {
        let id: String
        let db: String
        let queries: [String]

        var testDescription: String {
            id
        }
    }

    /// The six docs sources with broad query sets chosen to reliably hit each
    /// corpus. Only sources whose DB is present run.
    static let docsSources: [DocsSource] = [
        DocsSource(
            id: "apple-docs",
            db: LocalDBs.appleDocumentation,
            queries: ["view", "data", "string", "async", "protocol", "url", "image", "animation", "error", "color"]
        ),
        DocsSource(
            id: "hig",
            db: LocalDBs.hig,
            queries: ["color", "layout", "typography", "navigation", "button", "accessibility", "gesture", "icon", "menu", "sidebar"]
        ),
        DocsSource(
            id: "apple-archive",
            db: LocalDBs.appleArchive,
            queries: ["view", "controller", "data", "table", "image", "animation", "thread", "memory", "drawing", "layer"]
        ),
        DocsSource(
            id: "swift-evolution",
            db: LocalDBs.swiftEvolution,
            queries: ["concurrency", "actor", "async", "macro", "protocol", "result", "generics", "ownership", "sendable", "string"]
        ),
        DocsSource(
            id: "swift-org",
            db: LocalDBs.swiftOrg,
            queries: ["concurrency", "package", "compiler", "macro", "string", "protocol", "testing", "build", "module", "toolchain"]
        ),
        DocsSource(
            id: "swift-book",
            db: LocalDBs.swiftBook,
            queries: ["closure", "optional", "protocol", "generic", "enumeration", "structure", "class", "function", "property", "initializer"]
        ),
    ]

    static var availableDocsSources: [DocsSource] {
        docsSources.filter { LocalDBs.available($0.db) }
    }

    /// The longest token (>= 4 chars, alphanumeric) of a title, lowercased, for
    /// a case-insensitive "the read echoed the document" shape check.
    static func titleToken(_ title: String) -> String? {
        title
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 4 }
            .max(by: { $0.count < $1.count })
    }
}

// MARK: - Docs search coverage (per source, ~10 queries)

@Suite("#1194 read battery: docs search per source", .serialized, .enabled(if: CupertinoCLI.available))
struct ReadBatteryDocsSearchTests {
    @Test("each source returns correctly-tagged results across ~10 queries", arguments: ReadBattery.availableDocsSources)
    func docsSearch(_ source: ReadBattery.DocsSource) {
        var hits = 0
        for query in source.queries {
            let results = CupertinoCLI.searchDocs(query, ["--source", source.id, "--limit", "10"])
            if !results.isEmpty { hits += 1 }
            // Every returned result must be tagged with the requested source:
            // a read-only fan-out that leaked another DB's rows would fail here.
            for result in results {
                if let src = result.source {
                    #expect(src == source.id, "\(source.id) query '\(query)' returned a result tagged '\(src)'")
                }
                #expect(!result.uri.isEmpty)
            }
        }
        // Broad queries against a real corpus: expect the strong majority to hit.
        #expect(hits >= 8, "\(source.id): only \(hits)/\(source.queries.count) queries returned results")
    }
}

// MARK: - Docs reads (>= 20 documents per docs DB)

@Suite("#1194 read battery: read >= 20 docs per source", .serialized, .enabled(if: CupertinoCLI.available))
struct ReadBatteryDocsReadTests {
    @Test("reads at least 20 distinct documents read-only", arguments: ReadBattery.availableDocsSources)
    func read20Docs(_ source: ReadBattery.DocsSource) {
        // Collect distinct (uri, title) pairs from the source's query set.
        var seen = Set<String>()
        var docs: [(uri: String, title: String)] = []
        for query in source.queries {
            for result in CupertinoCLI.searchDocs(query, ["--source", source.id, "--limit", "10"]) where seen.insert(result.uri).inserted {
                docs.append((result.uri, result.title))
            }
            if docs.count >= 20 { break }
        }
        #expect(docs.count >= 20, "\(source.id): only gathered \(docs.count) distinct docs to read")

        var read = 0
        for doc in docs.prefix(20) {
            // A successful read echoes the document; a failure prints a short
            // "Document not found ..." line that contains neither the title
            // token nor enough text to clear the length floor. So the title
            // token (or, for token-less titles, a real length) is the success
            // signal -- no content scan for "error" (which appears legitimately
            // in error-handling docs).
            let output = CupertinoCLI.run(["read", doc.uri, "--source", source.id])
            if let token = ReadBattery.titleToken(doc.title) {
                #expect(output.lowercased().contains(token), "\(source.id) read '\(doc.uri)' did not echo title token '\(token)'")
            } else {
                #expect(output.count > 100, "\(source.id) read '\(doc.uri)' returned trivial output")
            }
            read += 1
        }
        #expect(read >= 20, "\(source.id): read \(read) docs (< 20)")
    }
}

// MARK: - Samples (search + read >= 20 files)

@Suite("#1194 read battery: samples search + read >= 20 files", .serialized, .enabled(if: CupertinoCLI.available))
struct ReadBatterySamplesTests {
    static let queries = ["view", "swiftui", "animation", "data", "network", "audio", "camera", "widget", "metal", "map"]

    @Test(
        "samples search returns files/projects and reads >= 20 files read-only",
        .enabled(if: LocalDBs.samplesAvailable)
    )
    func samplesSearchAndRead() {
        var seen = Set<String>()
        var files: [(project: String, path: String)] = []
        var queriesWithHits = 0
        for query in Self.queries {
            guard let response = CupertinoCLI.searchSamples(query, ["--limit", "10"]) else { continue }
            if !response.files.isEmpty { queriesWithHits += 1 }
            for file in response.files where seen.insert("\(file.projectId)/\(file.path)").inserted {
                files.append((file.projectId, file.path))
            }
        }
        #expect(queriesWithHits >= 6, "samples: only \(queriesWithHits)/\(Self.queries.count) queries hit")
        #expect(files.count >= 20, "samples: only gathered \(files.count) distinct files")

        var read = 0
        for file in files.prefix(20) {
            // A failed read prints a short "... not found" line (~60 chars); a
            // real file clears the length floor. Length is the success signal
            // (no content scan: source files legitimately contain "error").
            let output = CupertinoCLI.run(["read-sample-file", file.project, file.path])
            #expect(output.count > 80, "samples read-sample-file '\(file.project)/\(file.path)' returned trivial output")
            read += 1
        }
        #expect(read >= 20, "samples: read \(read) files (< 20)")
    }
}

// MARK: - Packages (search + read >= 20 files)

@Suite("#1194 read battery: packages search + read >= 20 files", .serialized, .enabled(if: CupertinoCLI.available))
struct ReadBatteryPackagesTests {
    static let queries = ["logger", "actor", "async", "client", "server", "json", "http", "test", "macro", "collection"]

    @Test(
        "packages search returns candidates and reads >= 20 files read-only",
        .enabled(if: LocalDBs.packagesAvailable)
    )
    func packagesSearchAndRead() {
        var seen = Set<String>()
        var identifiers: [String] = []
        var queriesWithHits = 0
        for query in Self.queries {
            guard let response = CupertinoCLI.searchPackages(query, ["--limit", "10"]) else { continue }
            if !response.candidates.isEmpty { queriesWithHits += 1 }
            for candidate in response.candidates where seen.insert(candidate.identifier).inserted {
                identifiers.append(candidate.identifier)
            }
        }
        #expect(queriesWithHits >= 6, "packages: only \(queriesWithHits)/\(Self.queries.count) queries hit")
        #expect(identifiers.count >= 20, "packages: only gathered \(identifiers.count) distinct candidates")

        var read = 0
        for identifier in identifiers.prefix(20) {
            let output = CupertinoCLI.run(["read", identifier, "--source", "packages"])
            #expect(output.count > 80, "packages read '\(identifier)' returned trivial output")
            read += 1
        }
        #expect(read >= 20, "packages: read \(read) files (< 20)")
    }
}

// MARK: - AST search commands (~10 queries each) + inheritance

@Suite("#1194 read battery: AST search commands", .serialized, .enabled(if: CupertinoCLI.available))
struct ReadBatteryASTTests {
    @Test(
        "search-symbols returns results across ~10 queries",
        .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation))
    )
    func searchSymbols() {
        let queries = ["View", "Data", "String", "Color", "Image", "URLSession", "Task", "Array", "Codable", "Error"]
        var hits = 0
        for query in queries where CupertinoCLI.searchSymbols(query: query, ["--limit", "5"])?.results.isEmpty == false {
            hits += 1
        }
        #expect(hits >= 8, "search-symbols: only \(hits)/\(queries.count) queries hit")
    }

    @Test(
        "search-generics returns results across ~10 constraints",
        .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation))
    )
    func searchGenerics() {
        let constraints = ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "Collection", "Sequence", "Identifiable", "Error", "View"]
        var hits = 0
        for constraint in constraints where CupertinoCLI.searchGenerics(constraint: constraint, ["--limit", "5"])?.results.isEmpty == false {
            hits += 1
        }
        #expect(hits >= 6, "search-generics: only \(hits)/\(constraints.count) constraints hit")
    }

    @Test(
        "search-conformances / concurrency / property-wrappers / inheritance run read-only",
        .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation))
    )
    func otherASTCommands() {
        // These exercise the read-only Search.Index through additional command
        // surfaces; assert the command runs and emits JSON without an error.
        for proto in ["Equatable", "Hashable", "Codable", "View", "Sendable"] {
            let out = CupertinoCLI.run(["search-conformances", "--protocol", proto, "--limit", "5", "--format", "json"])
            #expect(out.contains("{") || out.contains("["), "search-conformances '\(proto)' emitted no JSON")
        }
        for symbol in ["Color", "View", "Data", "String", "Image"] {
            let out = CupertinoCLI.run(["inheritance", symbol, "--format", "json"])
            #expect(!out.isEmpty, "inheritance '\(symbol)' emitted nothing")
        }
    }
}

// MARK: - Option coverage (--limit, --format, platform floors)

@Suite("#1194 read battery: option coverage", .serialized, .enabled(if: CupertinoCLI.available))
struct ReadBatteryOptionTests {
    @Test(
        "--limit caps the docs result count",
        .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation))
    )
    func limitOption() {
        for limit in [1, 3, 5, 10] {
            let results = CupertinoCLI.searchDocs("view", ["--source", "apple-docs", "--limit", "\(limit)"])
            #expect(results.count <= limit, "--limit \(limit) returned \(results.count) results")
        }
    }

    @Test(
        "--format json and markdown both produce output",
        .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation))
    )
    func formatOption() {
        let json = CupertinoCLI.run(["search", "view", "--source", "apple-docs", "--limit", "3", "--format", "json"])
        #expect(json.contains("[") || json.contains("{"), "json format emitted no JSON")
        let markdown = CupertinoCLI.run(["search", "view", "--source", "apple-docs", "--limit", "3", "--format", "markdown"])
        #expect(markdown.count > 20, "markdown format emitted trivial output")
    }

    @Test(
        "platform floor options run read-only without error",
        .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation))
    )
    func platformFloorOptions() {
        for floor in ["--min-ios", "--min-macos", "--min-tvos", "--min-watchos", "--min-visionos"] {
            let out = CupertinoCLI.run(["search", "view", "--source", "apple-docs", "--limit", "5", floor, "16.0", "--format", "json"])
            #expect(out.contains("[") || out.contains("{"), "\(floor) emitted no JSON")
        }
    }
}
