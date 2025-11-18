@testable import Shared
import Testing
import TestSupport

@Test func configuration() throws {
    let config = Shared.CrawlerConfiguration()
    #expect(config.maxPages > 0)
}
