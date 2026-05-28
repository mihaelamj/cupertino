import Foundation
import Testing

// Enrichment #20 — Row Bookkeeping.
//
// Per-row housekeeping columns (content_hash for change detection,
// word_count, json_data for the raw payload) plus DB-level schema-version
// stamps. The schema versions are the contract the bundle ships under:
// docs = 18 (PRAGMA user_version), packages = 5 (PRAGMA user_version),
// samples = 4 (samples_schema_version table). DB-probe only.

@Suite("Enrichment #20 — Row Bookkeeping (real DBs)", .enabled(if: LocalDBs.anyAvailable))
struct Enrichment20RowBookkeepingTests {
    @Test("apple-documentation rows carry content_hash + word_count")
    func perRowMetadata() {
        guard LocalDBs.available(LocalDBs.appleDocumentation), let probe = DBProbe(LocalDBs.appleDocumentation) else { return }
        let total = probe.count("SELECT count(*) FROM docs_metadata")
        #expect(probe.count("SELECT count(*) FROM docs_metadata WHERE content_hash IS NOT NULL AND content_hash<>''") == total)
        #expect(probe.count("SELECT count(*) FROM docs_metadata WHERE word_count IS NOT NULL") == total)
        #expect(probe.tableColumns("docs_metadata").contains("json_data"))
    }

    @Test("docs DBs stamp schema version 18 (PRAGMA user_version)", arguments: LocalDBs.docsDBs)
    func docsSchemaVersion(db: String) {
        guard LocalDBs.available(db), let probe = DBProbe(db) else { return }
        #expect(probe.int("PRAGMA user_version") == 18, "\(db) schema version should be 18")
    }

    @Test("packages stamp schema version 5")
    func packagesSchemaVersion() {
        guard LocalDBs.packagesAvailable, let probe = DBProbe(LocalDBs.packages) else { return }
        #expect(probe.int("PRAGMA user_version") == 5)
    }

    @Test("samples stamp schema version 4 (samples_schema_version table)")
    func samplesSchemaVersion() {
        guard LocalDBs.samplesAvailable, let probe = DBProbe(LocalDBs.appleSampleCode) else { return }
        #expect(probe.hasTable("samples_schema_version"))
        #expect(probe.int("SELECT MAX(version) FROM samples_schema_version") == 4)
    }
}
