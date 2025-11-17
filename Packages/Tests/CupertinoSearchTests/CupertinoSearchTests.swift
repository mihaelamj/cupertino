@testable import CupertinoSearch
import Foundation
import Testing

// MARK: - Search Tests

@Test("Search result model is Codable")
func searchResultCodable() throws {
    let result = SearchResult(
        uri: "apple://documentation/swift/array",
        framework: "swift",
        title: "Array",
        summary: "An ordered collection of elements",
        filePath: "/path/to/file.md",
        wordCount: 1000,
        rank: -5.5
    )

    // Verify score calculation
    #expect(result.score == 5.5)

    // Verify Codable
    let encoder = JSONEncoder()
    let data = try encoder.encode(result)
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(SearchResult.self, from: data)

    #expect(decoded.uri == result.uri)
    #expect(decoded.title == result.title)
    #expect(decoded.score == result.score)
}
