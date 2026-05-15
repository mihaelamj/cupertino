import Foundation
import MCPCore
@testable import MCPSupport
import SharedConstants
import Testing

// MARK: - #595 — MCP resources/list cursor strictness
//
// Pre-fix, `MCP.Support.DocsResourceProvider.decodeOffset(from:)`
// silently returned 0 for any malformed cursor — bad base64, wrong
// prefix, negative offset, NaN payload. Paginating clients that
// passed a mangled cursor would receive page 1 again instead of an
// error, infinite-loop re-reading the same 500 resources.
//
// Post-fix, only empty/nil cursors return 0 (valid bootstrap call).
// Non-empty cursors must decode cleanly or the function throws
// `Shared.Core.ToolError.invalidArgument("cursor", ...)`, which the
// JSON-RPC layer surfaces as a `-32602 invalidParams` error frame.

@Suite("MCP.Support.DocsResourceProvider.decodeOffset (#595 strict cursor)")
struct DocsResourceProviderCursorTests {
    typealias SUT = MCP.Support.DocsResourceProvider

    // MARK: - Valid cursors (round-trip through encode/decode)

    @Test("nil cursor → offset 0 (valid bootstrap call)")
    func nilCursorReturnsZero() throws {
        let nilCursor: String? = nil
        #expect(try SUT.decodeOffset(from: nilCursor) == 0)
    }

    @Test("empty string cursor → offset 0 (treated same as nil)")
    func emptyCursorReturnsZero() throws {
        #expect(try SUT.decodeOffset(from: "") == 0)
    }

    @Test("Valid encoded cursor round-trips")
    func validCursorRoundTrips() throws {
        let encoded = SUT.encodeOffset(500)
        #expect(try SUT.decodeOffset(from: encoded) == 500)
    }

    @Test(
        "Various valid offsets round-trip",
        arguments: [0, 1, 100, 500, 999, 12345, Int.max / 2]
    )
    func variousOffsetsRoundTrip(offset: Int) throws {
        let encoded = SUT.encodeOffset(offset)
        #expect(try SUT.decodeOffset(from: encoded) == offset)
    }

    // MARK: - Malformed cursors (the regression target — pre-#595 these all returned 0)

    @Test(
        "Malformed cursors throw invalidArgument instead of silently returning 0",
        arguments: [
            "INVALID_CURSOR_xyz",            // not valid base64
            "garbage123!@#",                  // not valid base64 (special chars)
            "bm90LWFuLW9mZnNldA==",           // valid base64 but decodes to "not-an-offset"
            "Zm9vOjEyMw==",                   // valid base64, decodes to "foo:123" — wrong prefix
            "b2Zmc2V0Og==",                   // valid base64, decodes to "offset:" — no integer
            "b2Zmc2V0OmFiYw==",               // valid base64, decodes to "offset:abc" — non-integer
            "b2Zmc2V0Oi0xMA==",               // valid base64, decodes to "offset:-10" — negative
        ]
    )
    func malformedCursorsThrow(cursor: String) {
        #expect(throws: Shared.Core.ToolError.self) {
            _ = try SUT.decodeOffset(from: cursor)
        }
    }

    @Test("Malformed cursor error carries the cursor string in the message")
    func errorMessageIncludesCursor() {
        let bad = "INVALID_CURSOR_xyz"
        #expect {
            try SUT.decodeOffset(from: bad)
        } throws: { error in
            guard case let Shared.Core.ToolError.invalidArgument(field, message) = error else {
                return false
            }
            return field == "cursor" && message.contains(bad)
        }
    }
}
