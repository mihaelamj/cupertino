// swiftlint:disable large_tuple type_body_length
// (5-element platform tuples + 5-element audit event tuples are test
// fixtures; promoting them to structs adds boilerplate without
// improving readability. type_body_length is exceeded by the 17-case
// per-rule test matrix; the cases are short and uniformly shaped, so
// splitting across files would obscure the rule-table coverage view.)

import Foundation
import LoggingModels
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// MARK: - #1073 — applyHIGPlatformInference (HIG topic-aware platform inference)

//
// Pinned per the #1073 critic loop (P1 #4 in the multi-angle review):
// the 10-rule URI-prefix table operates destructively on docs_metadata,
// and a typo in a pattern or a wrong keep-set could silently corrupt
// hig.db with no signal. The pass had zero coverage at ship.
//
// Each test seeds rows in docs_metadata that exercise one of the 10
// rules + the cross-platform default, runs `applyHIGPlatformInference`,
// asserts the resulting `min_<platform>` NULL state matches the rule's
// keep-set. The audit observer is captured separately so per-URI
// evidence emission is also pinned (the original implementation
// emitted the LIKE pattern as `docURI`; the post-critic fix SELECTs
// matching URIs first and emits one entry per real URI).

@Suite("#1073 — applyHIGPlatformInference (HIG topic-aware platform inference)", .serialized)
struct Issue1073HIGPlatformInferenceTests {
    // MARK: - Fixtures

    /// #1073 flake fix: the original actor recorded events via fire-and-forget
    /// `Task { await append(...) }` inside nonisolated protocol methods. A
    /// snapshot taken right after the pass returned could miss appends whose
    /// Tasks had not been scheduled yet, leaving the snapshot empty under
    /// parallel CI load (the docURIs-is-empty flake). This lock-guarded class
    /// records SYNCHRONOUSLY: every record* call completes before the
    /// producer's call returns, so the snapshot is deterministic regardless of
    /// executor pressure. `@unchecked Sendable` is sound because every access
    /// to mutable state is serialized by `lock`.
    private final class RecordingAudit: Search.EnrichmentAuditObserver, @unchecked Sendable {
        private let lock = NSLock()
        private var startEvents: [(pass: String, dbPath: String)] = []
        private var entries: [(pass: String, docURI: String, value: String, matchType: String, rowsAffected: Int)] = []
        private var endEvents: [(pass: String, total: Int, skipped: Int, durationMs: Int)] = []

        func recordPassStart(passIdentifier: String, dbPath: String) {
            lock.lock()
            defer { lock.unlock() }
            startEvents.append((passIdentifier, dbPath))
        }

        func recordEntry(
            passIdentifier: String,
            docURI: String,
            value: String,
            matchType: String,
            rowsAffected: Int
        ) {
            lock.lock()
            defer { lock.unlock() }
            entries.append((passIdentifier, docURI, value, matchType, rowsAffected))
        }

        func recordPassEnd(
            passIdentifier: String,
            totalRowsAffected: Int,
            totalRowsSkipped: Int,
            durationMs: Int
        ) {
            lock.lock()
            defer { lock.unlock() }
            endEvents.append((passIdentifier, totalRowsAffected, totalRowsSkipped, durationMs))
        }

        func snapshotEntries() -> [(pass: String, docURI: String, value: String, matchType: String, rowsAffected: Int)] {
            lock.lock()
            defer { lock.unlock() }
            return entries
        }
    }

    private static func makeFreshDB() async throws -> (dbPath: URL, index: Search.Index) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-1073-hig-platforms-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("hig.db")
        let index = try await Search.Index(
            dbPath: dbPath,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        return (dbPath, index)
    }

    private static func seedHIGRow(
        dbPath: URL,
        uri: String,
        minIOS: String? = "2.0",
        minMacOS: String? = "10.0",
        minTvOS: String? = "9.0",
        minWatchOS: String? = "1.0",
        minVisionOS: String? = "1.0"
    ) throws {
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        INSERT OR IGNORE INTO docs_metadata
            (uri, source, framework, language, kind, file_path, content_hash, last_crawled, word_count,
             min_ios, min_macos, min_tvos, min_watchos, min_visionos)
        VALUES (?, 'hig', 'human-interface-guidelines', 'markdown', 'guideline', '/tmp/fake', '0', 0, 0,
                ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
        bindOptional(stmt, idx: 2, value: minIOS)
        bindOptional(stmt, idx: 3, value: minMacOS)
        bindOptional(stmt, idx: 4, value: minTvOS)
        bindOptional(stmt, idx: 5, value: minWatchOS)
        bindOptional(stmt, idx: 6, value: minVisionOS)
        try #require(sqlite3_step(stmt) == SQLITE_DONE)
    }

    private static func bindOptional(_ stmt: OpaquePointer?, idx: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(stmt, idx, (value as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private static func readPlatforms(dbPath: URL, uri: String) throws -> (ios: String?, macos: String?, tvos: String?, watchos: String?, visionos: String?) {
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = "SELECT min_ios, min_macos, min_tvos, min_watchos, min_visionos FROM docs_metadata WHERE uri = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
        try #require(sqlite3_step(stmt) == SQLITE_ROW)
        func read(_ col: Int32) -> String? {
            guard let cStr = sqlite3_column_text(stmt, col) else { return nil }
            return String(cString: cStr)
        }
        return (read(0), read(1), read(2), read(3), read(4))
    }

    // MARK: - Per-rule keep-set assertions

    @Test("designing-for-watchos keeps watchos only, NULLs the rest")
    func designingForWatchOSKeepsWatchOSOnly() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        let uri = "hig://platforms/designing-for-watchos"
        try Self.seedHIGRow(dbPath: dbPath, uri: uri)
        _ = try await index.applyHIGPlatformInference()
        let row = try Self.readPlatforms(dbPath: dbPath, uri: uri)
        #expect(row.ios == nil)
        #expect(row.macos == nil)
        #expect(row.tvos == nil)
        #expect(row.watchos == "1.0")
        #expect(row.visionos == nil)
        await index.disconnect()
    }

    @Test("designing-for-tvos keeps tvos only")
    func designingForTvOSKeepsTvOSOnly() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        let uri = "hig://platforms/designing-for-tvos"
        try Self.seedHIGRow(dbPath: dbPath, uri: uri)
        _ = try await index.applyHIGPlatformInference()
        let row = try Self.readPlatforms(dbPath: dbPath, uri: uri)
        #expect(row.ios == nil)
        #expect(row.macos == nil)
        #expect(row.tvos == "9.0")
        #expect(row.watchos == nil)
        #expect(row.visionos == nil)
        await index.disconnect()
    }

    @Test("designing-for-visionos keeps visionos only")
    func designingForVisionOSKeepsVisionOSOnly() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        let uri = "hig://platforms/designing-for-visionos"
        try Self.seedHIGRow(dbPath: dbPath, uri: uri)
        _ = try await index.applyHIGPlatformInference()
        let row = try Self.readPlatforms(dbPath: dbPath, uri: uri)
        #expect(row.ios == nil)
        #expect(row.macos == nil)
        #expect(row.tvos == nil)
        #expect(row.watchos == nil)
        #expect(row.visionos == "1.0")
        await index.disconnect()
    }

    @Test("designing-for-macos keeps macos only")
    func designingForMacOSKeepsMacOSOnly() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        let uri = "hig://platforms/designing-for-macos"
        try Self.seedHIGRow(dbPath: dbPath, uri: uri)
        _ = try await index.applyHIGPlatformInference()
        let row = try Self.readPlatforms(dbPath: dbPath, uri: uri)
        #expect(row.ios == nil)
        #expect(row.macos == "10.0")
        #expect(row.tvos == nil)
        #expect(row.watchos == nil)
        #expect(row.visionos == nil)
        await index.disconnect()
    }

    @Test("designing-for-ios keeps ios only")
    func designingForIOSKeepsIOSOnly() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        let uri = "hig://platforms/designing-for-ios"
        try Self.seedHIGRow(dbPath: dbPath, uri: uri)
        _ = try await index.applyHIGPlatformInference()
        let row = try Self.readPlatforms(dbPath: dbPath, uri: uri)
        #expect(row.ios == "2.0")
        #expect(row.macos == nil)
        #expect(row.tvos == nil)
        #expect(row.watchos == nil)
        #expect(row.visionos == nil)
        await index.disconnect()
    }

    @Test("designing-for-ipados keeps ios only (iPadOS is a flavor of iOS)")
    func designingForIPadOSKeepsIOSOnly() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        let uri = "hig://platforms/designing-for-ipados"
        try Self.seedHIGRow(dbPath: dbPath, uri: uri)
        _ = try await index.applyHIGPlatformInference()
        let row = try Self.readPlatforms(dbPath: dbPath, uri: uri)
        #expect(row.ios == "2.0")
        #expect(row.macos == nil)
        #expect(row.tvos == nil)
        #expect(row.watchos == nil)
        #expect(row.visionos == nil)
        await index.disconnect()
    }

    @Test("mac-catalyst keeps both ios and macos")
    func macCatalystKeepsIOSAndMacOS() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        let uri = "hig://platforms/mac-catalyst"
        try Self.seedHIGRow(dbPath: dbPath, uri: uri)
        _ = try await index.applyHIGPlatformInference()
        let row = try Self.readPlatforms(dbPath: dbPath, uri: uri)
        #expect(row.ios == "2.0")
        #expect(row.macos == "10.0")
        #expect(row.tvos == nil)
        #expect(row.watchos == nil)
        #expect(row.visionos == nil)
        await index.disconnect()
    }

    @Test("carplay keeps ios only (CarPlay head-unit is iOS-based)")
    func carPlayKeepsIOSOnly() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        let uri = "hig://carplay/audio-app"
        try Self.seedHIGRow(dbPath: dbPath, uri: uri)
        _ = try await index.applyHIGPlatformInference()
        let row = try Self.readPlatforms(dbPath: dbPath, uri: uri)
        #expect(row.ios == "2.0")
        #expect(row.macos == nil)
        #expect(row.tvos == nil)
        #expect(row.watchos == nil)
        #expect(row.visionos == nil)
        await index.disconnect()
    }

    @Test("watch-faces keeps watchos only")
    func watchFacesKeepsWatchOSOnly() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        let uri = "hig://watchos/watch-faces"
        try Self.seedHIGRow(dbPath: dbPath, uri: uri)
        _ = try await index.applyHIGPlatformInference()
        let row = try Self.readPlatforms(dbPath: dbPath, uri: uri)
        #expect(row.ios == nil)
        #expect(row.macos == nil)
        #expect(row.tvos == nil)
        #expect(row.watchos == "1.0")
        #expect(row.visionos == nil)
        await index.disconnect()
    }

    @Test("spatial-layout keeps visionos only")
    func spatialLayoutKeepsVisionOSOnly() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        let uri = "hig://foundations/spatial-layout"
        try Self.seedHIGRow(dbPath: dbPath, uri: uri)
        _ = try await index.applyHIGPlatformInference()
        let row = try Self.readPlatforms(dbPath: dbPath, uri: uri)
        #expect(row.ios == nil)
        #expect(row.macos == nil)
        #expect(row.tvos == nil)
        #expect(row.watchos == nil)
        #expect(row.visionos == "1.0")
        await index.disconnect()
    }

    // MARK: - Cross-platform default + idempotency + audit pins

    @Test("Cross-platform HIG topics (no rule match) keep every platform default")
    func crossPlatformTopicKeepsAllDefaults() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        let uri = "hig://components/buttons"
        try Self.seedHIGRow(dbPath: dbPath, uri: uri)
        _ = try await index.applyHIGPlatformInference()
        let row = try Self.readPlatforms(dbPath: dbPath, uri: uri)
        #expect(row.ios == "2.0")
        #expect(row.macos == "10.0")
        #expect(row.tvos == "9.0")
        #expect(row.watchos == "1.0")
        #expect(row.visionos == "1.0")
        await index.disconnect()
    }

    @Test("Idempotent re-run reports rowsAffected=0 the second time")
    func reRunIsIdempotent() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        try Self.seedHIGRow(dbPath: dbPath, uri: "hig://platforms/designing-for-watchos")
        let firstRun = try await index.applyHIGPlatformInference()
        let secondRun = try await index.applyHIGPlatformInference()
        #expect(firstRun > 0, "first run should have NULLed columns on the seeded watchOS row")
        #expect(secondRun == 0, "second run is idempotent: no rows still need NULLing")
        await index.disconnect()
    }

    @Test("audit.recordEntry emits per-URI events (real doc_uri, not LIKE pattern)")
    func auditEmitsPerURIEvents() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        try Self.seedHIGRow(dbPath: dbPath, uri: "hig://platforms/designing-for-watchos")
        try Self.seedHIGRow(dbPath: dbPath, uri: "hig://platforms/designing-for-tvos")
        let recorder = RecordingAudit()
        _ = try await index.applyHIGPlatformInference(audit: recorder, dbPath: "hig.db")
        let entries = recorder.snapshotEntries()
        let docURIs = Set(entries.map(\.docURI))
        #expect(docURIs.contains("hig://platforms/designing-for-watchos"))
        #expect(docURIs.contains("hig://platforms/designing-for-tvos"))
        // The pre-critic implementation emitted LIKE patterns;
        // confirm no patterns leak into the audit log.
        let likePatternLeaks = entries.filter { $0.docURI.contains("%") }
        #expect(likePatternLeaks.isEmpty, "no LIKE pattern should appear in audit docURI field")
        await index.disconnect()
    }
}
