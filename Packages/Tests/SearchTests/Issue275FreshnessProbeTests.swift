import Diagnostics
import Foundation
import SQLite3
import Testing

// MARK: - #275 — per-source freshness probe

//
// `Diagnostics.Probes.freshnessBySource(at:)` is the read-only
// probe that answers "how stale is my local index?" for brew-installed
// users without a `cupertino-docs-private` checkout. Spec resolution for
// the open design questions in #275:
//
//   Q1 (snapshot vs distribution vs save-time): per-source distribution
//      via oldest / p50 / p90 / newest — single snapshot hides per-page
//      staleness when a long crawl spans days; raw min/max would lie about
//      the bulk; p50 + p90 surfaces both typical age + tail.
//   Q2 (output surface): `cupertino doctor --freshness` sub-flag (matches
//      the existing `--kind-coverage` pattern).
//   Q3 (thresholds): raw ages only — no fresh/aging/stale labels; users
//      decide their own thresholds.
//
// These tests pin the probe's behaviour. The CLI rendering side
// (`Doctor.checkFreshness()`) is verified end-to-end via the live-built
// release binary (see the PR body); covered structurally here via the
// row shape the renderer reads.

@Suite("#275 freshness probe — Diagnostics.Probes.freshnessBySource", .serialized)
struct Issue275FreshnessProbeTests {
    // MARK: - Helpers

    /// Create a minimal `docs_metadata` table at the given URL stamped
    /// with `user_version = 15` (current binary schema). Inserts the
    /// supplied (source, lastCrawled-epoch) pairs so the probe sees
    /// realistic per-source distributions without needing to spin up
    /// a full `Search.Index` actor + run the migrator.
    private func makeDocsMetadataDB(at url: URL, rows: [(source: String, lastCrawled: Int64)]) {
        var db: OpaquePointer?
        _ = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        defer { sqlite3_close_v2(db) }

        _ = sqlite3_exec(db, "PRAGMA user_version = 15;", nil, nil, nil)
        // Minimal-shape docs_metadata — just enough columns for the SELECT
        // to work. The probe only reads `source` + `last_crawled`.
        let createSQL = """
        CREATE TABLE docs_metadata (
            uri TEXT PRIMARY KEY,
            source TEXT NOT NULL,
            framework TEXT NOT NULL DEFAULT 'x',
            language TEXT NOT NULL DEFAULT 'swift',
            kind TEXT NOT NULL DEFAULT 'article',
            file_path TEXT NOT NULL DEFAULT '/x',
            content_hash TEXT NOT NULL DEFAULT 'h',
            last_crawled INTEGER NOT NULL,
            word_count INTEGER NOT NULL DEFAULT 100
        );
        """
        _ = sqlite3_exec(db, createSQL, nil, nil, nil)

        for (idx, row) in rows.enumerated() {
            let insertSQL = "INSERT INTO docs_metadata (uri, source, last_crawled) VALUES ('uri\(idx)', '\(row.source)', \(row.lastCrawled));"
            _ = sqlite3_exec(db, insertSQL, nil, nil, nil)
        }
    }

    private func tempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test-275-freshness-\(UUID().uuidString).db")
    }

    // MARK: - Probe shape

    @Test("freshnessBySource returns per-source oldest / p50 / p90 / newest with correct quantiles")
    func quantilesAreNearestRank() throws {
        let url = tempDBURL()
        defer { try? FileManager.default.removeItem(at: url) }

        // 10 timestamps spread across 10 days, all on the same source
        // ('apple-docs'). Nearest-rank quantile on 10 samples: p50 = 5th
        // (0-indexed 4), p90 = 9th (0-indexed 8). Use ceil(N * fraction)
        // as the rank.
        var rows: [(source: String, lastCrawled: Int64)] = []
        let baseEpoch: Int64 = 1700000000 // 2023-11-14 UTC, arbitrary
        for day in 0..<10 {
            rows.append((source: "apple-docs", lastCrawled: baseEpoch + Int64(day) * 86400))
        }
        makeDocsMetadataDB(at: url, rows: rows)

        let report = try #require(Diagnostics.Probes.freshnessBySource(at: url))
        try #require(report.count == 1)
        let row = report[0]
        #expect(row.source == "apple-docs")
        #expect(row.count == 10)
        #expect(row.oldest == baseEpoch)
        #expect(row.newest == baseEpoch + 9 * 86400)
        // Nearest-rank p50 on 10 sorted samples = index ceil(10*0.5)-1 = 4
        #expect(row.p50 == baseEpoch + 4 * 86400)
        // p90 = index ceil(10*0.9)-1 = 8
        #expect(row.p90 == baseEpoch + 8 * 86400)
    }

    @Test("freshnessBySource groups by source and returns alphabetical order")
    func groupsBySource() throws {
        let url = tempDBURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let now: Int64 = 1700000000
        let rows: [(source: String, lastCrawled: Int64)] = [
            (source: "swift-org", lastCrawled: now),
            (source: "apple-docs", lastCrawled: now - 86400),
            (source: "apple-docs", lastCrawled: now),
            (source: "hig", lastCrawled: now - 7 * 86400),
        ]
        makeDocsMetadataDB(at: url, rows: rows)

        let report = try #require(Diagnostics.Probes.freshnessBySource(at: url))
        try #require(report.count == 3)
        // Sorted alphabetically by source.
        #expect(report[0].source == "apple-docs")
        #expect(report[0].count == 2)
        #expect(report[1].source == "hig")
        #expect(report[1].count == 1)
        #expect(report[2].source == "swift-org")
        #expect(report[2].count == 1)
    }

    @Test("freshnessBySource filters out `last_crawled = 0` (unset) rows")
    func ignoresUnsetTimestamps() throws {
        let url = tempDBURL()
        defer { try? FileManager.default.removeItem(at: url) }

        // 2 valid + 3 unset rows on the same source. Only the 2 valid
        // rows contribute to the quantiles (count == 2, not 5).
        let rows: [(source: String, lastCrawled: Int64)] = [
            (source: "apple-docs", lastCrawled: 1700000000),
            (source: "apple-docs", lastCrawled: 1700086400),
            (source: "apple-docs", lastCrawled: 0),
            (source: "apple-docs", lastCrawled: 0),
            (source: "apple-docs", lastCrawled: 0),
        ]
        makeDocsMetadataDB(at: url, rows: rows)

        let report = try #require(Diagnostics.Probes.freshnessBySource(at: url))
        try #require(report.count == 1)
        #expect(report[0].count == 2, "expected only the 2 stamped rows; got count=\(report[0].count)")
    }

    @Test("freshnessBySource returns nil when DB file is missing (no crash)")
    func missingDBReturnsNil() {
        let url = tempDBURL()
        // Don't create the file.
        let report = Diagnostics.Probes.freshnessBySource(at: url)
        #expect(report == nil)
    }

    @Test("freshnessBySource returns empty (NOT nil) on a stamped DB with no rows")
    func emptyDBReturnsEmpty() throws {
        let url = tempDBURL()
        defer { try? FileManager.default.removeItem(at: url) }

        makeDocsMetadataDB(at: url, rows: [])

        let report = try #require(Diagnostics.Probes.freshnessBySource(at: url))
        #expect(report.isEmpty, "empty DB should return empty array, not nil; got \(report)")
    }

    @Test("Single-row source: oldest == p50 == p90 == newest")
    func singleRowAllQuantilesEqual() throws {
        let url = tempDBURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let now: Int64 = 1700000000
        makeDocsMetadataDB(at: url, rows: [(source: "tabletopkit", lastCrawled: now)])

        let report = try #require(Diagnostics.Probes.freshnessBySource(at: url))
        try #require(report.count == 1)
        let row = report[0]
        #expect(row.oldest == now)
        #expect(row.p50 == now)
        #expect(row.p90 == now)
        #expect(row.newest == now)
    }
}
