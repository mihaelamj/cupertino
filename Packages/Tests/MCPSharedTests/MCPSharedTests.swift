@testable import MCPShared
import Testing

@Test func requestIDCoding() throws {
    let stringID = RequestID.string("test-123")
    let intID = RequestID.int(42)

    // Basic test - extend as needed
    #expect(stringID != intID)
}
