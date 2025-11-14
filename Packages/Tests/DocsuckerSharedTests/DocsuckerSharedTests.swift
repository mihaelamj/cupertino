import Testing
@testable import DocsuckerShared

@Test func testConfiguration() throws {
    let config = CrawlerConfiguration()
    #expect(config.maxPages > 0)
}
