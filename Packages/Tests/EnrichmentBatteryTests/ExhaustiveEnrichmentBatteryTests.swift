import Foundation
import Testing

// MARK: - Exhaustive enrichment battery (#1196)

// Proves every enrichment from docs/enrichment-inventory.md, plus the
// inheritance / conformance / min-version command surfaces, through the real
// `cupertino` CLI -- >= 20 queries per applicable database and per option,
// each with an assertion that the specific enrichment / command surfaces, and
// each recorded into the shared `BatteryReport` HTML (#1194) as its own
// collapsible section showing the actual returned text.
//
// Gated on `CupertinoCLI.available` (debug binary + local snapshot), serialized
// (every assertion spawns the binary). Full run is long; it is local-only and
// skipped on CI, like the rest of EnrichmentBatteryTests.
//
// Report ordering: the read battery uses orders 0-8; this battery uses 100+ so
// its sections render after the read sections in the same HTML file.

enum EnrichmentBattery {
    // >= 20 broad queries per source, chosen to reliably hit each corpus.
    static let appleDocs = [
        "view", "data", "string", "async", "protocol", "url", "image", "animation", "error", "color",
        "array", "dictionary", "task", "actor", "codable", "result", "sequence", "stream", "publisher", "gesture",
        "navigation", "layout", "font", "shape", "transaction",
    ]
    static let hig = [
        "color", "layout", "typography", "navigation", "button", "accessibility", "gesture", "icon", "menu", "sidebar",
        "toolbar", "alert", "sheet", "picker", "tab", "search", "notification", "widget", "window", "feedback",
        "onboarding", "gauge", "rating", "scroll", "label",
    ]
    static let appleArchive = [
        "view", "controller", "data", "table", "image", "animation", "thread", "memory", "drawing", "layer",
        "quartz", "core", "key", "value", "observe", "graphics", "context", "path", "transform", "gradient",
        "shadow", "text", "font", "event", "responder",
    ]
    static let swiftEvolution = [
        "concurrency", "actor", "async", "macro", "protocol", "result", "generics", "ownership", "sendable", "string",
        "regex", "result builder", "property wrapper", "existential", "package", "typed throws", "isolation", "copyable", "span", "embedded",
        "distributed", "variadic", "opaque", "move", "borrow",
    ]
    static let swiftOrg = [
        "concurrency", "package", "compiler", "macro", "string", "protocol", "testing", "build", "module", "toolchain",
        "actor", "async", "generics", "interop", "c++", "foundation", "swiftpm", "runtime", "abi", "linux",
        "windows", "documentation", "migration", "performance", "library",
    ]
    static let swiftBook = [
        "closure", "optional", "protocol", "generic", "enumeration", "structure", "class", "function", "property", "initializer",
        "subscript", "extension", "inheritance", "error handling", "concurrency", "actor", "macro", "opaque type", "result builder", "string",
        "collection", "control flow", "deinitialization", "memory safety", "access control",
    ]
    static let samples = [
        "view", "swiftui", "animation", "data", "network", "audio", "camera", "widget", "metal", "map",
        "game", "machine learning", "vision", "augmented reality", "watch", "notification", "core data", "photo", "video", "scene",
        "gesture", "list", "navigation", "chart", "document",
    ]
    static let packages = [
        "logger", "actor", "async", "client", "server", "json", "http", "test", "macro", "collection",
        "crypto", "url", "date", "algorithm", "concurrency", "stream", "decode", "encode", "websocket", "metrics",
        "tracing", "atomic", "regex", "numerics", "argument",
    ]

    /// (sourceId, dbFile, queries) for the 6 docs sources.
    static let docs: [(id: String, db: String, queries: [String])] = [
        ("apple-docs", LocalDBs.appleDocumentation, appleDocs),
        ("hig", LocalDBs.hig, hig),
        ("apple-archive", LocalDBs.appleArchive, appleArchive),
        ("swift-evolution", LocalDBs.swiftEvolution, swiftEvolution),
        ("swift-org", LocalDBs.swiftOrg, swiftOrg),
        ("swift-book", LocalDBs.swiftBook, swiftBook),
    ]

    static var availableDocs: [(id: String, db: String, queries: [String])] {
        docs.filter { LocalDBs.available($0.db) }
    }

    /// >= 20 symbol-ish args for the AST commands.
    static let symbols = [
        "View", "Data", "String", "Color", "Image", "URLSession", "Task", "Array", "Codable", "Error",
        "Button", "Text", "Stack", "Path", "Gesture", "Publisher", "Sequence", "Result", "Date", "Notification",
        "Shape", "Font", "Layout", "Transaction", "Binding",
    ]
    static let constraints = [
        "Equatable", "Hashable", "Comparable", "Codable", "Sendable", "Collection", "Sequence", "Identifiable", "Error", "View",
        "Encodable", "Decodable", "RawRepresentable", "CaseIterable", "CustomStringConvertible",
        "Numeric", "Strideable", "AdditiveArithmetic", "ExpressibleByStringLiteral",
        "RandomAccessCollection", "BidirectionalCollection", "IteratorProtocol", "AsyncSequence", "Observable",
    ]

    /// HTML helpers reuse the read battery's BatteryReport escaping.
    static func recordTable(order: Int, title: String, header: [String], rows: [[String]]) {
        var html = "<h2>\(BatteryReport.esc(title))</h2><table><tr>"
        html += header.map { "<th>\(BatteryReport.esc($0))</th>" }.joined()
        html += "</tr>"
        for row in rows {
            html += "<tr>" + row.map { "<td>\(BatteryReport.esc($0))</td>" }.joined() + "</tr>"
        }
        html += "</table>"
        BatteryReport.shared.record(order: order, html: html)
    }
}

// MARK: - #1 Lexical Index (FTS5) -- all 8 databases, >= 20 queries each

@Suite("Enrichment #1 Lexical Index (exhaustive, all DBs)", .serialized, .enabled(if: CupertinoCLI.available))
struct ExhaustiveLexicalIndexTests {
    @Test("each docs source returns FTS results for >= 20 queries", arguments: EnrichmentBattery.availableDocs.map(\.id))
    func docsLexical(_ sourceId: String) {
        guard let source = EnrichmentBattery.docs.first(where: { $0.id == sourceId }) else { return }
        var rows: [[String]] = []
        var hits = 0
        for query in source.queries {
            let results = CupertinoCLI.searchDocs(query, ["--source", source.id, "--limit", "5"])
            if !results.isEmpty { hits += 1 }
            for result in results where result.source != nil {
                #expect(result.source == source.id, "\(source.id) '\(query)' leaked source \(result.source ?? "?")")
            }
            rows.append([query, "\(results.count)", results.first?.title ?? "(none)"])
        }
        #expect(hits >= 18, "\(source.id): only \(hits)/\(source.queries.count) FTS queries hit")
        EnrichmentBattery.recordTable(
            order: 100 + EnrichmentBattery.docs.firstIndex { $0.id == sourceId }!,
            title: "#1 Lexical Index -- search --source \(source.id) (\(source.queries.count) queries)",
            header: ["query", "#results", "top result"],
            rows: rows
        )
    }

    @Test(
        "samples + packages FTS return results for >= 20 queries",
        .enabled(if: LocalDBs.samplesAvailable || LocalDBs.packagesAvailable)
    )
    func samplesPackagesLexical() {
        var rows: [[String]] = []
        if LocalDBs.samplesAvailable {
            var hits = 0
            for query in EnrichmentBattery.samples {
                let count = CupertinoCLI.searchSamples(query, ["--limit", "5"])?.files.count ?? 0
                if count >= 1 { hits += 1 }
                rows.append(["samples", query, "\(count)"])
            }
            #expect(hits >= 16, "samples: only \(hits)/\(EnrichmentBattery.samples.count) FTS queries hit")
        }
        if LocalDBs.packagesAvailable {
            var hits = 0
            for query in EnrichmentBattery.packages {
                let count = CupertinoCLI.searchPackages(query, ["--limit", "5"])?.candidates.count ?? 0
                if count >= 1 { hits += 1 }
                rows.append(["packages", query, "\(count)"])
            }
            #expect(hits >= 16, "packages: only \(hits)/\(EnrichmentBattery.packages.count) FTS queries hit")
        }
        EnrichmentBattery.recordTable(
            order: 106,
            title: "#1 Lexical Index -- samples + packages FTS",
            header: ["source", "query", "#results"],
            rows: rows
        )
    }
}

// MARK: - #2 / #5 / #7 Symbol surfacing (AST symbols, boosting, identifier splitting)

@Suite(
    "Enrichment #2/#5/#7 Symbol surfacing (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveSymbolTests {
    @Test("search-symbols returns AST symbol rows for >= 20 queries (#5)")
    func astSymbols() {
        var rows: [[String]] = []
        var hits = 0
        for symbol in EnrichmentBattery.symbols {
            let results = CupertinoCLI.searchSymbols(query: symbol, ["--limit", "5"])?.results ?? []
            if !results.isEmpty { hits += 1 }
            rows.append([symbol, "\(results.count)", results.first?.symbolName ?? "(none)", results.first?.symbolKind ?? ""])
        }
        #expect(hits >= 18, "search-symbols: only \(hits)/\(EnrichmentBattery.symbols.count) hit")
        EnrichmentBattery.recordTable(
            order: 110, title: "#5 AST Symbol Extraction -- search-symbols (\(EnrichmentBattery.symbols.count) queries)",
            header: ["query", "#results", "top symbol", "kind"], rows: rows
        )
    }

    // Exact API symbol names that each have a canonical apple-docs page. Symbol
    // field boosting (#2) + identifier splitting (#7) should surface that page
    // in the top results when you search the symbol name.
    static let canonicalSymbols = [
        "LazyVGrid", "LazyHGrid", "NavigationStack", "NavigationSplitView", "ScrollView",
        "AsyncStream", "AsyncThrowingStream", "URLSession", "URLRequest", "GeometryReader",
        "RoundedRectangle", "LinearGradient", "ForEach", "TabView", "ProgressView",
        "DatePicker", "ColorPicker", "AttributedString", "TaskGroup", "RoundedBorderTextFieldStyle",
        "UIViewController", "CALayer", "NSAttributedString", "DispatchQueue", "PropertyListDecoder",
    ]

    @Test("exact symbol queries surface the canonical page (#2 boosting + #7 splitting)")
    func symbolBoosting() {
        var rows: [[String]] = []
        var surfaced = 0
        for symbol in Self.canonicalSymbols {
            let results = CupertinoCLI.searchDocs(symbol, ["--source", "apple-docs", "--limit", "3"])
            let needle = symbol.lowercased()
            // The canonical page is surfaced when a top-3 result's uri/title
            // contains the symbol, or it is exposed in matchedSymbols.
            let hit = results.prefix(3).contains { result in
                result.uri.lowercased().contains(needle)
                    || result.title.lowercased().replacingOccurrences(of: " ", with: "").contains(needle)
                    || (result.matchedSymbols?.contains { $0.name.lowercased() == needle } ?? false)
            }
            if hit { surfaced += 1 }
            rows.append([symbol, "\(results.count)", results.first?.title ?? "(none)", hit ? "canonical surfaced" : "-"])
        }
        #expect(surfaced >= 20, "symbol boosting: only \(surfaced)/\(Self.canonicalSymbols.count) surfaced the canonical page")
        EnrichmentBattery.recordTable(
            order: 111, title: "#2 Symbol Field Boosting + #7 Identifier Splitting (\(Self.canonicalSymbols.count) exact symbols)",
            header: ["query", "#results", "top result", "canonical surfaced?"], rows: rows
        )
    }
}

// MARK: - #9 / #10 Generic constraints + #24 boilerplate demotion

@Suite(
    "Enrichment #9/#10 Constraints (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveConstraintTests {
    @Test("search-generics returns constrained symbols for >= 20 constraints")
    func generics() {
        var rows: [[String]] = []
        var hits = 0
        for constraint in EnrichmentBattery.constraints {
            let results = CupertinoCLI.searchGenerics(constraint: constraint, ["--limit", "5"])?.results ?? []
            if !results.isEmpty { hits += 1 }
            rows.append([constraint, "\(results.count)", results.first?.symbolName ?? "(none)", results.first?.genericParams ?? ""])
        }
        #expect(hits >= 12, "search-generics: only \(hits)/\(EnrichmentBattery.constraints.count) constraints hit")
        EnrichmentBattery.recordTable(
            order: 112, title: "#9/#10 Constraint Resolution + Propagation -- search-generics (\(EnrichmentBattery.constraints.count) constraints)",
            header: ["constraint", "#results", "top symbol", "generic params"], rows: rows
        )
    }
}

// MARK: - Conformances command (>= 20)

@Suite(
    "search-conformances (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveConformanceTests {
    @Test("search-conformances emits JSON results for >= 20 protocols")
    func conformances() {
        var rows: [[String]] = []
        var hits = 0
        for proto in EnrichmentBattery.constraints {
            let out = BatteryReport.stripLog(CupertinoCLI.run(["search-conformances", "--protocol", proto, "--limit", "5", "--format", "json"]))
            let hasJSON = out.contains("{") || out.contains("[")
            #expect(hasJSON, "search-conformances '\(proto)' emitted no JSON")
            // crude result count from the JSON body
            let count = out.components(separatedBy: "\"symbol_name\"").count - 1
            if count >= 1 { hits += 1 }
            rows.append([proto, "\(count)"])
        }
        #expect(hits >= 10, "search-conformances: only \(hits)/\(EnrichmentBattery.constraints.count) protocols had conformers")
        EnrichmentBattery.recordTable(
            order: 113, title: "search-conformances (\(EnrichmentBattery.constraints.count) protocols)",
            header: ["protocol", "#conformers"], rows: rows
        )
    }
}

// MARK: - #15 Inheritance graph (>= 20)

@Suite(
    "Enrichment #15 Inheritance Graph (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveInheritanceTests {
    static let symbols = [
        "UIView", "UIViewController", "UIControl", "UIButton", "UILabel", "UIScrollView", "UITableView", "NSObject", "UIResponder", "CALayer",
        "UICollectionView", "UIImageView", "UITextField", "UISlider", "UISwitch", "UIStackView", "UINavigationController", "UITabBarController", "NSView", "NSViewController",
        "SKNode", "SCNNode", "CAAnimation", "UIGestureRecognizer", "UIWindow",
    ]

    @Test("inheritance emits a graph for >= 20 symbols")
    func inheritance() {
        var rows: [[String]] = []
        var hits = 0
        for symbol in Self.symbols {
            let out = BatteryReport.stripLog(CupertinoCLI.run(["inheritance", symbol, "--format", "json"]))
            #expect(!out.isEmpty, "inheritance '\(symbol)' emitted nothing")
            let hasEdges = out.contains("parent") || out.contains("child") || out.contains("\(symbol)")
            if hasEdges { hits += 1 }
            rows.append([symbol, "\(out.count) chars"])
        }
        #expect(hits >= 15, "inheritance: only \(hits)/\(Self.symbols.count) symbols produced a graph")
        EnrichmentBattery.recordTable(
            order: 114, title: "#15 Inheritance Graph -- inheritance (\(Self.symbols.count) symbols)",
            header: ["symbol", "output"], rows: rows
        )
    }
}

// MARK: - #3 / #17 Deployment floors -- min-version options (>= 20 per floor)

@Suite(
    "Enrichment #3/#17 Deployment Floors (exhaustive, per option)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveFloorTests {
    @Test("each --min-<platform> floor runs over >= 20 queries and returns results", arguments: [
        "--min-ios", "--min-macos", "--min-tvos", "--min-watchos", "--min-visionos",
    ])
    func floor(_ option: String) {
        var rows: [[String]] = []
        var hits = 0
        for query in EnrichmentBattery.appleDocs {
            let results = CupertinoCLI.searchDocs(query, ["--source", "apple-docs", "--limit", "5", option, "16.0"])
            if !results.isEmpty { hits += 1 }
            rows.append([query, "\(results.count)", results.first?.title ?? "(none)"])
        }
        #expect(hits >= 10, "\(option): only \(hits)/\(EnrichmentBattery.appleDocs.count) queries returned results")
        let floorOrder = ["--min-ios": 0, "--min-macos": 1, "--min-tvos": 2, "--min-watchos": 3, "--min-visionos": 4][option] ?? 0
        EnrichmentBattery.recordTable(
            order: 120 + floorOrder, title: "#3/#17 Deployment Floors -- apple-docs \(option) 16.0 (\(EnrichmentBattery.appleDocs.count) queries)",
            header: ["query", "#results", "top result"], rows: rows
        )
    }
}

// MARK: - #21 / #22 / #23 Query-time ranking (RRF, intent routing, reranking)

@Suite(
    "Enrichment #21/#22/#23 Ranking (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveRankingTests {
    @Test("fan-out search fuses multiple sources via RRF for >= 20 queries (#21)")
    func rankFusion() {
        var rows: [[String]] = []
        var fused = 0
        for query in EnrichmentBattery.appleDocs {
            let response = CupertinoCLI.searchFanout(query, ["--limit", "10"])
            let sources = response?.contributingSources ?? []
            let candidates = response?.candidates.count ?? 0
            if sources.count >= 2, candidates >= 1 { fused += 1 }
            rows.append([query, "\(sources.count)", "\(candidates)", sources.prefix(4).joined(separator: ",")])
        }
        #expect(fused >= 15, "RRF: only \(fused)/\(EnrichmentBattery.appleDocs.count) queries fused >= 2 sources")
        EnrichmentBattery.recordTable(
            order: 130, title: "#21 Rank Fusion -- fan-out search (\(EnrichmentBattery.appleDocs.count) queries)",
            header: ["query", "#sources", "#candidates", "contributing sources"], rows: rows
        )
    }

    @Test("exact-title queries rank that page first (#23 kind-aware reranking)")
    func reranking() {
        let exact = ExhaustiveSymbolTests.canonicalSymbols
        var rows: [[String]] = []
        var topHit = 0
        for symbol in exact {
            let results = CupertinoCLI.searchDocs(symbol, ["--source", "apple-docs", "--limit", "3"])
            let needle = symbol.lowercased()
            let topIsExact = results.first.map {
                $0.title.lowercased().replacingOccurrences(of: " ", with: "").contains(needle)
                    || $0.uri.lowercased().contains(needle)
            } ?? false
            if topIsExact { topHit += 1 }
            rows.append([symbol, results.first?.title ?? "(none)", topIsExact ? "top" : "-"])
        }
        #expect(topHit >= 18, "reranking: only \(topHit)/\(exact.count) ranked the exact page first")
        EnrichmentBattery.recordTable(
            order: 131, title: "#23 Kind-Aware Reranking -- exact-title-first (\(exact.count) symbols)",
            header: ["query", "top result", "exact first?"], rows: rows
        )
    }

    @Test("intent-routed fan-out keeps apple-docs a top contributor for API queries (#22)")
    func intentRouting() {
        var rows: [[String]] = []
        var appleTop = 0
        for query in EnrichmentBattery.symbols {
            let response = CupertinoCLI.searchFanout(query, ["--limit", "10"])
            let candidates = response?.candidates ?? []
            // Authority weighting (#254) gives apple-docs the highest authority;
            // for API-symbol queries it should contribute the top candidate.
            let appleContributes = candidates.prefix(3).contains { ($0.source ?? "").contains("apple") }
            if appleContributes { appleTop += 1 }
            rows.append([query, "\(candidates.count)", candidates.first?.source ?? "(none)"])
        }
        #expect(appleTop >= 15, "intent routing: apple-docs in top-3 for only \(appleTop)/\(EnrichmentBattery.symbols.count)")
        EnrichmentBattery.recordTable(
            order: 132, title: "#22 Intent Routing -- apple-docs authority (\(EnrichmentBattery.symbols.count) queries)",
            header: ["query", "#candidates", "top source"], rows: rows
        )
    }
}

// MARK: - #11 Framework aliasing

@Suite(
    "Enrichment #11 Framework Aliasing (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveAliasingTests {
    // (alias query, expected framework substring)
    static let aliases: [(query: String, framework: String)] = [
        ("bluetooth", "bluetooth"), ("location", "location"), ("machine learning", "ml"), ("augmented reality", "arkit"),
        ("nfc", "nfc"), ("health", "health"), ("home automation", "home"), ("payments", "passkit"),
        ("notifications", "notification"), ("contacts", "contact"), ("calendar", "eventkit"), ("photos", "photo"),
        ("speech", "speech"), ("maps", "mapkit"), ("camera", "avfoundation"), ("audio", "av"),
        ("animation", "core"), ("graphics", "core"), ("networking", "network"), ("storage", "core"),
        ("widgets", "widgetkit"), ("watch", "watch"), ("game", "game"), ("ar", "arkit"),
    ]

    @Test("alias queries route to the aliased framework for >= 20 terms")
    func aliasing() {
        var rows: [[String]] = []
        var routed = 0
        for entry in Self.aliases {
            let results = CupertinoCLI.searchDocs(entry.query, ["--source", "apple-docs", "--limit", "5"])
            let hit = results.contains { result in
                (result.framework?.lowercased().contains(entry.framework) ?? false)
                    || result.uri.lowercased().contains(entry.framework)
            }
            if hit { routed += 1 }
            rows.append([entry.query, "-> \(entry.framework)", "\(results.count)", hit ? "routed" : "-"])
        }
        #expect(routed >= 12, "aliasing: only \(routed)/\(Self.aliases.count) terms routed to the framework")
        EnrichmentBattery.recordTable(
            order: 133, title: "#11 Framework Aliasing (\(Self.aliases.count) alias terms)",
            header: ["query", "expected framework", "#results", "routed?"], rows: rows
        )
    }
}

// MARK: - #14 / #16 read-surfaced enrichments (structured projection, code examples)

@Suite(
    "Enrichment #14/#16 read-surfaced (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveReadFieldTests {
    @Test("reading >= 20 docs exposes structured projection + code examples")
    func readFields() {
        // Gather >= 20 distinct apple-docs URIs.
        var seen = Set<String>()
        var uris: [String] = []
        for query in EnrichmentBattery.appleDocs {
            for result in CupertinoCLI.searchDocs(query, ["--source", "apple-docs", "--limit", "5"]) where seen.insert(result.uri).inserted {
                uris.append(result.uri)
            }
            if uris.count >= 25 { break }
        }
        #expect(uris.count >= 20, "only gathered \(uris.count) docs to read")

        var rows: [[String]] = []
        var structured = 0
        var withExamples = 0
        for uri in uris.prefix(25) {
            let body = BatteryReport.stripLog(CupertinoCLI.run(["read", uri, "--source", "apple-docs", "--format", "json"]))
            // #14 Structured Projection: declaration / overview / sections lifted out.
            let hasStructure = body.contains("\"declaration\"") || body.contains("\"sections\"") || body.contains("\"overview\"")
            if hasStructure { structured += 1 }
            // #16 Code Example Extraction: codeExamples array present (non-empty for many API pages).
            if body.contains("\"codeExamples\""), !body.contains("\"codeExamples\" : [ ]"), !body.contains("\"codeExamples\":[]") {
                withExamples += 1
            }
            rows.append([uri, hasStructure ? "structured" : "-", body.count > 200 ? "ok" : "thin"])
        }
        #expect(structured >= 20, "#14 structured projection: only \(structured)/\(uris.prefix(25).count) docs had structure")
        #expect(withExamples >= 1, "#16 code examples: none of the read docs carried codeExamples")
        EnrichmentBattery.recordTable(
            order: 134, title: "#14 Structured Projection + #16 Code Examples (\(uris.prefix(25).count) docs read)",
            header: ["uri", "structured?", "body"], rows: rows
        )
    }
}

// MARK: - Internal stored columns proven by DB probe (>= 20 populated rows)

// #4 toolchain, #6 imports, #8 availability, #12 HIG NULLing, #13 apple-imports,
// #18 dependency closure, #19 provenance, #20 row bookkeeping.

@Suite(
    "Enrichment #4/#6/#8/#12/#13/#18/#19/#20 stored columns (exhaustive probe)",
    .serialized,
    .enabled(if: LocalDBs.anyAvailable)
)
struct ExhaustiveStoredColumnTests {
    private func nonNull(_ db: String, table: String, column: String) -> Int64 {
        guard let probe = DBProbe(db), probe.hasTable(table), probe.tableColumns(table).contains(column) else { return -1 }
        return probe.count("SELECT COUNT(*) FROM \(table) WHERE \(column) IS NOT NULL AND \(column) != ''")
    }

    @Test("every internal enrichment column is populated in >= 20 rows of its DB")
    func storedColumns() {
        var rows: [[String]] = []
        func check(_ label: String, _ db: String, _ table: String, _ column: String, min: Int64 = 20) {
            guard LocalDBs.available(db) else { return }
            let count = nonNull(db, table: table, column: column)
            rows.append([label, "\(db) . \(table) . \(column)", "\(count)"])
            #expect(count >= min, "\(label): \(db).\(table).\(column) populated in \(count) rows (< \(min))")
        }
        // #19 provenance + #20 bookkeeping: every docs DB.
        for source in EnrichmentBattery.docs where LocalDBs.available(source.db) {
            check("#19 provenance", source.db, "docs_metadata", "source_type")
            check("#20 content_hash", source.db, "docs_metadata", "content_hash")
            check("#20 word_count", source.db, "docs_metadata", "word_count")
        }
        // #4 toolchain stamping.
        check("#4 toolchain", LocalDBs.swiftEvolution, "docs_metadata", "implementation_swift_version", min: 5)
        check("#4 toolchain", LocalDBs.swiftBook, "docs_metadata", "implementation_swift_version", min: 1)
        check("#4 toolchain", LocalDBs.packages, "package_metadata", "swift_tools_version", min: 5)
        // #6 imports (row presence in the imports tables).
        check("#6 imports", LocalDBs.appleDocumentation, "doc_imports", "module_name")
        check("#6 imports", LocalDBs.appleSampleCode, "file_imports", "module_name")
        check("#6 imports", LocalDBs.packages, "package_imports", "module_name")
        // #8 availability capture.
        check("#8 availability", LocalDBs.packages, "package_files", "available_attrs_json", min: 5)
        // #13 apple-framework usage + #18 dependency closure (packages).
        check("#13 apple-imports", LocalDBs.packages, "package_metadata", "apple_imports_json", min: 5)
        check("#18 dep closure", LocalDBs.packages, "package_metadata", "parents_json", min: 5)
        EnrichmentBattery.recordTable(
            order: 140, title: "Internal enrichment columns -- populated-row probe (>= 20 unless noted)",
            header: ["enrichment", "db.table.column", "non-null rows"], rows: rows
        )
    }

    @Test(
        "#12 HIG platform applicability NULLs some min_<platform> rows",
        .enabled(if: LocalDBs.available(LocalDBs.hig))
    )
    func higPlatformApplicability() {
        guard let probe = DBProbe(LocalDBs.hig), probe.hasTable("docs_metadata") else { return }
        let total = probe.count("SELECT COUNT(*) FROM docs_metadata")
        let nulled = probe.count("SELECT COUNT(*) FROM docs_metadata WHERE min_ios IS NULL OR min_macos IS NULL")
        #expect(total >= 1)
        #expect(nulled >= 1, "#12: HIG has no NULLed platform rows (subtractive applicability not applied)")
        EnrichmentBattery.recordTable(
            order: 141, title: "#12 Platform Applicability -- HIG subtractive NULLing",
            header: ["metric", "value"], rows: [["total HIG rows", "\(total)"], ["rows with a NULLed platform floor", "\(nulled)"]]
        )
    }
}

// MARK: - #24 AST Boilerplate Demotion (signal-rank ORDER BY on AST commands)

@Suite(
    "Enrichment #24 AST Boilerplate Demotion (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveDemotionTests {
    @Test("search-symbols ranks a named declaration first, demoting synthesized/operator boilerplate (#177)")
    func boilerplateDemotion() {
        var rows: [[String]] = []
        var namedFirst = 0
        for symbol in EnrichmentBattery.symbols {
            let results = CupertinoCLI.searchSymbols(query: symbol, ["--limit", "5"])?.results ?? []
            // Boilerplate demotion: the top hit should be a real named symbol
            // (starts with a letter), not a synthesized operator (`==`, `<`, ...)
            // or other punctuation-led boilerplate pushed down by signal-rank.
            let top = results.first?.symbolName ?? ""
            let namedTop = top.first.map { $0.isLetter || $0 == "_" } ?? false
            if namedTop { namedFirst += 1 }
            rows.append([symbol, "\(results.count)", top.isEmpty ? "(none)" : top, namedTop ? "named" : "boilerplate"])
        }
        #expect(namedFirst >= 18, "boilerplate demotion: only \(namedFirst)/\(EnrichmentBattery.symbols.count) ranked a named symbol first")
        EnrichmentBattery.recordTable(
            order: 135, title: "#24 AST Boilerplate Demotion -- search-symbols top-hit is a named symbol (\(EnrichmentBattery.symbols.count) queries)",
            header: ["query", "#results", "top symbol", "named/boilerplate"], rows: rows
        )
    }
}
