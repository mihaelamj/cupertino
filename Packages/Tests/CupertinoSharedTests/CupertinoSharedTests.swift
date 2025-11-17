@testable import CupertinoShared
import Testing

@Test func configuration() throws {
    let config = CrawlerConfiguration()
    #expect(config.maxPages > 0)
}
