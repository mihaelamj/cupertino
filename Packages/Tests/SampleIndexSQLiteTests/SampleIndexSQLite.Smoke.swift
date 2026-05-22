import SampleIndexModels
import SampleIndexSQLite
import SharedConstants
import Testing

@Suite("SampleIndexSQLite smoke")
struct SampleIndexSQLiteSmokeTests {
    @Test("Sample.Index.Database conforms to Sample.Index.Reader and Sample.Index.Writer")
    func databaseConformsToBothProtocolSeams() {
        let readerType: any (Sample.Index.Reader.Type) = Sample.Index.Database.self
        let writerType: any (Sample.Index.Writer.Type) = Sample.Index.Database.self
        #expect(readerType is Sample.Index.Database.Type)
        #expect(writerType is Sample.Index.Database.Type)
    }
}
