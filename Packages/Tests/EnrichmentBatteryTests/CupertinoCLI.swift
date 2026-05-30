import Foundation

// Drives the real `cupertino search` path for the second layer of every
// enrichment battery. DB-probe tests prove the data is present; these
// prove the enrichment actually surfaces through the production query
// pipeline (FTS + BM25F weights + RRF + intent routing + kind-aware
// rerank), which raw SQL cannot exercise.
//
// Safety: the binary is the debug build under Packages/.build/debug/. Its
// provenance is `.other`, so it can never default to the brew path
// (~/.cupertino). On first use we also (idempotently) drop a
// cupertino.config.json next to it pinning baseDirectory to the local
// snapshot (LocalDBs.dir), so every query reads the private DBs only.
enum CupertinoCLI {
    static let binary: String = {
        if let env = ProcessInfo.processInfo.environment["CUPERTINO_BIN"], !env.isEmpty { return env }
        let here = URL(fileURLWithPath: #filePath) // .../Tests/EnrichmentBatteryTests/CupertinoCLI.swift
        let packages = here.deletingLastPathComponent() // EnrichmentBatteryTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Packages
        return packages.appendingPathComponent(".build/debug/cupertino").path
    }()

    static var available: Bool {
        FileManager.default.isExecutableFile(atPath: binary) && LocalDBs.anyAvailable
    }

    /// Pin the binary to the local snapshot once. Runs lazily on first search.
    private static let configured: Bool = {
        let dir = URL(fileURLWithPath: binary).deletingLastPathComponent()
        let cfg = dir.appendingPathComponent("cupertino.config.json")
        let json = "{\"baseDirectory\":\"\(LocalDBs.dir)\"}\n"
        try? json.write(to: cfg, atomically: true, encoding: .utf8)
        return true
    }()

    /// `cupertino search --source <docs source>` emits a top-level array.
    struct DocResult: Decodable {
        let uri: String
        let title: String
        let framework: String?
        let source: String?
        let summary: String?
        let rank: Double?
        let wordCount: Int?
        let matchedSymbols: [Symbol]?

        struct Symbol: Decodable {
            let name: String
            let kind: String
            let isAsync: Bool?
        }
    }

    /// `--source samples` emits a list view: matched files + their projects.
    struct SamplesResponse: Decodable {
        let files: [SampleFile]
        let projects: [SampleProject]

        struct SampleFile: Decodable {
            let filename: String
            let path: String
            let projectId: String
            let rank: Double?
            let snippet: String?
        }

        struct SampleProject: Decodable {
            let id: String
            let title: String
            let description: String?
            let fileCount: Int?
            let frameworks: [String]?
        }
    }

    /// `--source packages` emits chunk candidates.
    struct PackagesResponse: Decodable {
        let candidates: [PackageCandidate]

        struct PackageCandidate: Decodable {
            let identifier: String
            let title: String?
            let kind: String?
            let rank: Double?
            let score: Double?
            let source: String?
            let metadata: Meta?

            struct Meta: Decodable {
                let module: String?
                let owner: String?
                let repo: String?
                let relpath: String?
            }
        }
    }

    /// AST symbol-query commands (search-generics / search-symbols / ...)
    /// emit { filters, results: [...] } with snake_case keys; the shared
    /// decoder maps them to camelCase.
    struct ASTQueryResponse: Decodable {
        let results: [ASTSymbol]
        struct ASTSymbol: Decodable {
            let symbolName: String
            let symbolKind: String?
            let genericParams: String?
            let docUri: String?
            let docTitle: String?
            let framework: String?
        }
    }

    /// Default fan-out search (no --source): RRF-fused chunk candidates plus
    /// the list of sources that contributed.
    struct FanoutResponse: Decodable {
        let candidates: [Candidate]
        let contributingSources: [String]
        struct Candidate: Decodable {
            let source: String?
            let title: String?
            let identifier: String?
            let rank: Double?
            let score: Double?
        }
    }

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return dec
    }()

    /// Run any subcommand with --format json and return the JSON payload with
    /// the leading timestamp log line stripped (the binary prints one log
    /// line on stdout before the JSON value; nothing trails the close).
    static func jsonData(_ fullArgs: [String]) -> Data? {
        _ = configured
        // A cold DB open occasionally returns before the query completes,
        // yielding output with no JSON value — spawn-timing flake, not a
        // real empty result (a real empty result is still valid JSON with
        // delimiters). Retry on a delimiter-less body; fan-out across all
        // eight DBs is the slowest to warm, so allow several attempts.
        for _ in 0..<4 {
            let out = run(fullArgs + ["--format", "json"])
            if let start = out.firstIndex(where: { $0 == "{" || $0 == "[" }) {
                return Data(out[start...].utf8)
            }
        }
        return nil
    }

    /// Every CLI invocation spawns the binary, which cold-opens one or more
    /// large DBs. Many concurrent spawns (parallel suites) contend hard
    /// enough that a query degrades or returns before its DB finishes
    /// opening. Serialize all binary spawns process-wide; the DB-probe tests
    /// (no binary) still run in parallel.
    private static let cliLock = NSLock()

    /// `{count,query,results:[...]}` list-view shape (hig emits this; the
    /// other docs sources emit a bare array).
    private struct DocsListView: Decodable {
        let results: [DocResult]
    }

    /// Docs sources (apple-docs, hig, apple-archive, swift-evolution,
    /// swift-org, swift-book). Always pass `--source` so only one DB opens.
    static func searchDocs(_ query: String, _ args: [String] = []) -> [DocResult] {
        guard let data = jsonData(["search", query] + args) else { return [] }
        // Most docs sources emit a bare `[DocResult]`; hig emits a
        // `{results:[...]}` list-view object. Accept either.
        if let arr = try? decoder.decode([DocResult].self, from: data) {
            return arr
        }
        return (try? decoder.decode(DocsListView.self, from: data))?.results ?? []
    }

    static func searchSamples(_ query: String, _ args: [String] = []) -> SamplesResponse? {
        guard let data = jsonData(["search", query] + args + ["--source", "samples"]) else { return nil }
        return try? decoder.decode(SamplesResponse.self, from: data)
    }

    static func searchPackages(_ query: String, _ args: [String] = []) -> PackagesResponse? {
        guard let data = jsonData(["search", query] + args + ["--source", "packages"]) else { return nil }
        return try? decoder.decode(PackagesResponse.self, from: data)
    }

    /// AST symbol-query commands (search-generics / search-conformances /
    /// search-symbols / search-concurrency / search-property-wrappers).
    static func searchGenerics(constraint: String, _ args: [String] = []) -> ASTQueryResponse? {
        guard let data = jsonData(["search-generics", "--constraint", constraint] + args) else { return nil }
        return try? decoder.decode(ASTQueryResponse.self, from: data)
    }

    static func searchSymbols(query: String, _ args: [String] = []) -> ASTQueryResponse? {
        guard let data = jsonData(["search-symbols", "--query", query] + args) else { return nil }
        return try? decoder.decode(ASTQueryResponse.self, from: data)
    }

    /// Default fan-out search (no --source): RRF fusion across all sources.
    static func searchFanout(_ query: String, _ args: [String] = []) -> FanoutResponse? {
        guard let data = jsonData(["search", query] + args) else { return nil }
        return try? decoder.decode(FanoutResponse.self, from: data)
    }

    /// Raw combined stdout+stderr, for non-JSON assertions and diagnostics.
    static func run(_ args: [String]) -> String {
        _ = configured
        cliLock.lock()
        defer { cliLock.unlock() }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch { return "" }
        // Read to EOF before waiting: the child closes the pipe on exit, so
        // this drains fully and avoids the pipe-buffer deadlock (#1106).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
