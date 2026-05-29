import ArgumentParser
@testable import CLI
import Foundation
import LoggingModels
import SearchAPI
import SearchModels
import SearchSQLite
import SharedConstants
import SQLite3
import Testing

// MARK: - #1154 / #1155 multi-DB fan-out tests (task #223)

/// Two-depth suite for the per-source-DB-split AST search fan-out.
///
/// Pre-#1154 the 5 AST commands (`search-symbols`,
/// `search-property-wrappers`, `search-concurrency`,
/// `search-conformances`, `search-generics`) opened only
/// `apple-documentation.db` via `resolveAppleDocsDBURL` + a single
/// `--search-db` override. Post per-source split, `doc_symbols` rows
/// live across several DBs, so the commands fan out: they resolve a
/// participating-source DB list from the production registry (filtered
/// by `Search.Capabilities.searchers`) and merge per-DB results.
///
/// Behavioral coverage proves `resolveSymbolSearchDBURLs` (capability
/// filter, `--source` scoping, missing-DB skip) and `fanOutSymbolSearch`
/// (real two-DB merge + limit cap) actually work against seeded
/// fixtures. Surface coverage proves the new `--base-dir` / `--source`
/// flags parse on every command and the retired `--search-db` flag is
/// gone.
@Suite("#1154/#1155 — multi-DB symbol-search fan-out", .serialized)
struct Issue1154MultiDBFanOutTests {
    // MARK: - Fixtures

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-1154-fanout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The set of per-source DB filenames whose source advertises the
    /// `.symbols` searcher capability, derived from the production
    /// registry (not hardcoded, so the assertion tracks capability
    /// changes). Returned as filenames so the test can both create the
    /// fixture files and compute the expected URL set.
    private static func symbolBearingFilenames() -> [String] {
        CLIImpl.makeProductionSourceRegistry().allEnabled
            .filter { $0.capabilities.searchers.contains(.symbols) }
            .map(\.destinationDB.filename)
    }

    /// Every per-source DB filename in the production registry, keyed by
    /// source id, so the test can create the full sibling set and scope
    /// expectations per-source.
    private static func filenamesByID() -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: CLIImpl.makeProductionSourceRegistry().allEnabled.map {
                ($0.definition.id, $0.destinationDB.filename)
            }
        )
    }

    /// Touch an empty file at `dir/name`.
    private static func touch(_ dir: URL, _ name: String) throws {
        let url = dir.appendingPathComponent(name)
        try Data().write(to: url)
    }

    /// Seed a single genuinely-searchable symbol row into a fresh DB at
    /// `path`. Drives `Search.Index.indexDocument` first so the
    /// `docs_fts` + `docs_metadata` rows the `searchSymbols` INNER JOIN
    /// requires exist, then raw-inserts a `doc_symbols` row keyed on the
    /// same `doc_uri`. The symbol's `name` is the searchable token.
    private static func seedSymbolDB(at path: URL, uri: String, symbolName: String) async throws {
        let index = try await Search.Index(
            dbPath: path,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: uri,
            source: "apple-docs",
            framework: "swiftui",
            language: "swift",
            title: "Doc for \(symbolName)",
            content: "Body content mentioning \(symbolName) for the fan-out fixture.",
            filePath: "/tmp/fake/\(symbolName)",
            contentHash: "hash-\(symbolName)",
            lastCrawled: Date()
        ))
        await index.disconnect()

        var conn: OpaquePointer?
        try #require(sqlite3_open(path.path, &conn) == SQLITE_OK)
        defer { sqlite3_close(conn) }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        // Mirrors Issue837SearchDBGenericConstraintsBoostTests' doc_symbols
        // column list. `name` carries the searchable token; the symbol is
        // kind=struct so it lands in kind-tier 0 of the rank clause.
        let symSQL = """
        INSERT INTO doc_symbols
            (doc_uri, name, kind, line, column, signature, is_async, is_throws, is_public, is_static,
             attributes, conformances, generic_params, generic_constraints)
            VALUES (?, ?, 'struct', 1, 1, 'struct \(symbolName) {}', 0, 0, 1, 0,
                    '', '', '', '');
        """
        try #require(sqlite3_prepare_v2(conn, symSQL, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (symbolName as NSString).utf8String, -1, nil)
        try #require(sqlite3_step(stmt) == SQLITE_DONE)
    }

    // MARK: - Behavioral 1: capability filter

    @Test("resolveSymbolSearchDBURLs returns exactly the symbol-bearing sources' DBs, excluding text-only sources")
    func capabilityFilterReturnsSymbolBearingDBsOnly() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create empty files for EVERY source's DB so the existence
        // filter cannot be the thing that excludes the text-only ones.
        let allFilenames = Set(Self.filenamesByID().values)
        for name in allFilenames {
            try Self.touch(dir, name)
        }

        let resolved = try CLIImpl.resolveSymbolSearchDBURLs(searcher: .symbols, source: nil, baseDir: dir.path)
        let resolvedNames = Set(resolved.map(\.lastPathComponent))

        let expected = Set(Self.symbolBearingFilenames())
        #expect(!expected.isEmpty, "registry must advertise at least one .symbols source")
        #expect(
            resolvedNames == expected,
            "fan-out DB set must equal the registry's .symbols-capable sources. expected=\(expected.sorted()) got=\(resolvedNames.sorted())"
        )

        // The text-only sources (hig, evolution, archive) carry no
        // `.symbols` capability, so their DB files must be absent from
        // the result even though they exist on disk.
        let textOnly = CLIImpl.makeProductionSourceRegistry().allEnabled
            .filter { !$0.capabilities.searchers.contains(.symbols) }
            .map(\.destinationDB.filename)
        for name in textOnly {
            #expect(!resolvedNames.contains(name), "text-only source DB \(name) must not be in the symbol fan-out set")
        }
    }

    // MARK: - Behavioral 2: --source scoping

    @Test("--source scopes the fan-out to a single source DB; a bogus source throws SymbolSearchDBError")
    func sourceScopingNarrowsToOneDBAndRejectsUnknown() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let byID = Self.filenamesByID()
        for name in Set(byID.values) {
            try Self.touch(dir, name)
        }

        // swift-org is a symbol-bearing source in the production registry.
        let swiftOrgFilename = try #require(byID["swift-org"], "registry must carry a swift-org source")
        let scoped = try CLIImpl.resolveSymbolSearchDBURLs(searcher: .symbols, source: "swift-org", baseDir: dir.path)
        #expect(scoped.count == 1, "--source swift-org must resolve exactly one DB; got \(scoped.count)")
        #expect(scoped.first?.lastPathComponent == swiftOrgFilename)

        // A source id that does not exist must throw the typed error.
        var threw = false
        do {
            _ = try CLIImpl.resolveSymbolSearchDBURLs(searcher: .symbols, source: "not-a-source", baseDir: dir.path)
        } catch is CLIImpl.SymbolSearchDBError {
            threw = true
        }
        #expect(threw, "a bogus --source must throw CLIImpl.SymbolSearchDBError")
    }

    // MARK: - Behavioral 3: missing-DB skip

    @Test("resolveSymbolSearchDBURLs skips sources whose DB file is absent")
    func missingDBFilesAreSkipped() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create a file for only ONE of the symbol-bearing sources.
        let symbolNames = Self.symbolBearingFilenames()
        #expect(symbolNames.count >= 2, "this test needs at least 2 symbol-bearing sources to be meaningful")
        let present = try #require(symbolNames.first)
        try Self.touch(dir, present)

        let resolved = try CLIImpl.resolveSymbolSearchDBURLs(searcher: .symbols, source: nil, baseDir: dir.path)
        let resolvedNames = resolved.map(\.lastPathComponent)
        #expect(resolvedNames == [present], "only the on-disk DB should be returned; got \(resolvedNames)")
    }

    // MARK: - Behavioral 4: fan-out merge + limit cap

    @Test("fanOutSymbolSearch merges symbol rows from two real DBs")
    func fanOutMergesTwoRealDBs() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let db1 = dir.appendingPathComponent("alpha.db")
        let db2 = dir.appendingPathComponent("beta.db")
        try await Self.seedSymbolDB(at: db1, uri: "apple-docs://swiftui/alpha", symbolName: "AlphaFanoutSymbol")
        try await Self.seedSymbolDB(at: db2, uri: "apple-docs://swiftui/beta", symbolName: "BetaFanoutSymbol")

        let merged = try await CLIImpl.fanOutSymbolSearch(
            dbURLs: [db1, db2],
            logger: Logging.NoopRecording(),
            limit: 50
        ) { index in
            try await index.searchSymbols(query: nil, kind: nil, isAsync: nil, framework: nil, limit: 50)
        }

        let names = merged.map(\.symbolName)
        #expect(names.contains("AlphaFanoutSymbol"), "merged result must include db1's symbol; got \(names)")
        #expect(names.contains("BetaFanoutSymbol"), "merged result must include db2's symbol; got \(names)")
    }

    @Test("fanOutSymbolSearch caps the merged result at limit")
    func fanOutCapsAtLimit() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let db1 = dir.appendingPathComponent("alpha.db")
        let db2 = dir.appendingPathComponent("beta.db")
        try await Self.seedSymbolDB(at: db1, uri: "apple-docs://swiftui/alpha", symbolName: "AlphaFanoutSymbol")
        try await Self.seedSymbolDB(at: db2, uri: "apple-docs://swiftui/beta", symbolName: "BetaFanoutSymbol")

        let merged = try await CLIImpl.fanOutSymbolSearch(
            dbURLs: [db1, db2],
            logger: Logging.NoopRecording(),
            limit: 1
        ) { index in
            try await index.searchSymbols(query: nil, kind: nil, isAsync: nil, framework: nil, limit: 50)
        }

        #expect(merged.count == 1, "limit:1 must cap the merged fan-out at one result; got \(merged.count)")
    }

    // MARK: - Surface 5: new flags parse, old --search-db is gone

    @Test("all 5 AST commands parse --base-dir + --source")
    func newFlagsParseOnAllCommands() throws {
        let symbols = try CLIImpl.Command.SearchSymbols.parse(
            ["--query", "Task", "--base-dir", "/tmp/x", "--source", "apple-docs"]
        )
        #expect(symbols.baseDir == "/tmp/x")
        #expect(symbols.source == "apple-docs")

        let wrappers = try CLIImpl.Command.SearchPropertyWrappers.parse(
            ["--wrapper", "State", "--base-dir", "/tmp/x", "--source", "apple-docs"]
        )
        #expect(wrappers.baseDir == "/tmp/x")
        #expect(wrappers.source == "apple-docs")

        let concurrency = try CLIImpl.Command.SearchConcurrency.parse(
            ["--pattern", "async", "--base-dir", "/tmp/x", "--source", "apple-docs"]
        )
        #expect(concurrency.baseDir == "/tmp/x")
        #expect(concurrency.source == "apple-docs")

        let conformances = try CLIImpl.Command.SearchConformances.parse(
            ["--protocol", "View", "--base-dir", "/tmp/x", "--source", "apple-docs"]
        )
        #expect(conformances.baseDir == "/tmp/x")
        #expect(conformances.source == "apple-docs")

        let generics = try CLIImpl.Command.SearchGenerics.parse(
            ["--constraint", "Sendable", "--base-dir", "/tmp/x", "--source", "apple-docs"]
        )
        #expect(generics.baseDir == "/tmp/x")
        #expect(generics.source == "apple-docs")
    }

    @Test("the retired --search-db flag no longer parses on the AST commands")
    func retiredSearchDBFlagRejected() throws {
        var symbolsThrew = false
        do {
            _ = try CLIImpl.Command.SearchSymbols.parse(["--query", "Task", "--search-db", "/tmp/x"])
        } catch {
            symbolsThrew = true
        }
        #expect(symbolsThrew, "search-symbols must reject the retired --search-db flag")

        var wrappersThrew = false
        do {
            _ = try CLIImpl.Command.SearchPropertyWrappers.parse(["--wrapper", "State", "--search-db", "/tmp/x"])
        } catch {
            wrappersThrew = true
        }
        #expect(wrappersThrew, "search-property-wrappers must reject the retired --search-db flag")

        var concurrencyThrew = false
        do {
            _ = try CLIImpl.Command.SearchConcurrency.parse(["--pattern", "async", "--search-db", "/tmp/x"])
        } catch {
            concurrencyThrew = true
        }
        #expect(concurrencyThrew, "search-concurrency must reject the retired --search-db flag")

        var conformancesThrew = false
        do {
            _ = try CLIImpl.Command.SearchConformances.parse(["--protocol", "View", "--search-db", "/tmp/x"])
        } catch {
            conformancesThrew = true
        }
        #expect(conformancesThrew, "search-conformances must reject the retired --search-db flag")

        var genericsThrew = false
        do {
            _ = try CLIImpl.Command.SearchGenerics.parse(["--constraint", "Sendable", "--search-db", "/tmp/x"])
        } catch {
            genericsThrew = true
        }
        #expect(genericsThrew, "search-generics must reject the retired --search-db flag")
    }
}
