import SearchModels
import SearchSchema
import Testing

@Suite("SearchSchema smoke")
struct SearchSchemaSmokeTests {
    @Test("currentVersion is a non-zero positive value")
    func currentVersionIsPositive() {
        #expect(Search.Schema.currentVersion > 0)
    }

    @Test("createAllTablesSQL is non-empty and contains the docs_fts virtual table")
    func createAllTablesSQLContainsDocsFTS() {
        let sql = Search.Schema.createAllTablesSQL
        #expect(!sql.isEmpty)
        #expect(sql.contains("CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts"))
    }
}
