import SearchModels
import SearchSchema
import SearchSQLite
import Testing

@Suite("SearchSQLite smoke")
struct SearchSQLiteSmokeTests {
    @Test("Search.Index re-exports the schema version constant from SearchSchema")
    func searchIndexSchemaVersionMatchesSearchSchemaCurrentVersion() {
        #expect(Search.Index.schemaVersion == Search.Schema.currentVersion)
        #expect(Search.Index.schemaVersion > 0)
    }
}
