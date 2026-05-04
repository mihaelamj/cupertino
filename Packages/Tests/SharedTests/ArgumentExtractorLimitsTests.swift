import Foundation
import MCP
@testable import Shared
import Testing

// MARK: - ArgumentExtractor DoS Hardening Tests

/// Tests that ArgumentExtractor enforces size limits on string arguments,
/// defending against payload DoS via malformed or hostile MCP tool input.
@Suite("ArgumentExtractor size limits")
struct ArgumentExtractorLimitsTests {
    @Test("require throws on oversized string (17 KB)")
    func requireRejectsOversizedString() {
        let oversized = String(repeating: "a", count: 17 * 1024)
        let extractor = ArgumentExtractor(["q": AnyCodable(oversized)])

        #expect(throws: ToolError.self) {
            _ = try extractor.require("q")
        }
    }

    @Test("require accepts string just under the cap (1 KB)")
    func requireAcceptsSmallString() throws {
        let normal = String(repeating: "a", count: 1024)
        let extractor = ArgumentExtractor(["q": AnyCodable(normal)])

        let value = try extractor.require("q")
        #expect(value.count == 1024)
    }

    @Test("require accepts string at exactly the cap (16 KB)")
    func requireAcceptsAtCap() throws {
        let atCap = String(repeating: "a", count: ArgumentExtractor.maxStringLength)
        let extractor = ArgumentExtractor(["q": AnyCodable(atCap)])

        let value = try extractor.require("q")
        #expect(value.utf8.count == ArgumentExtractor.maxStringLength)
    }

    @Test("optional throws on oversized string")
    func optionalRejectsOversizedString() {
        let oversized = String(repeating: "x", count: 17 * 1024)
        let extractor = ArgumentExtractor(["framework": AnyCodable(oversized)])

        #expect(throws: ToolError.self) {
            _ = try extractor.optional("framework")
        }
    }

    @Test("optional returns nil for missing key without throwing")
    func optionalReturnsNilWhenMissing() throws {
        let extractor = ArgumentExtractor([:])
        let value = try extractor.optional("missing")
        #expect(value == nil)
    }

    @Test("optional with default accepts small string")
    func optionalWithDefaultAcceptsSmallString() throws {
        let extractor = ArgumentExtractor(["fmt": AnyCodable("json")])
        let value = try extractor.optional("fmt", default: "markdown")
        #expect(value == "json")
    }

    @Test("multibyte utf8 counted by byte length, not grapheme count")
    func multibyteCountedByUtf8Bytes() {
        // Each emoji is 4 utf8 bytes; 5000 emoji = 20000 bytes (over the 16 KB cap)
        // but only 5000 grapheme clusters.
        let manyEmoji = String(repeating: "😀", count: 5000)
        #expect(manyEmoji.utf8.count > ArgumentExtractor.maxStringLength)
        #expect(manyEmoji.count < ArgumentExtractor.maxStringLength)

        let extractor = ArgumentExtractor(["q": AnyCodable(manyEmoji)])
        #expect(throws: ToolError.self) {
            _ = try extractor.require("q")
        }
    }

    @Test("invalidArgument error includes the key name")
    func errorIncludesKeyName() {
        let oversized = String(repeating: "z", count: 17 * 1024)
        let extractor = ArgumentExtractor(["query": AnyCodable(oversized)])

        do {
            _ = try extractor.require("query")
            Issue.record("expected throw")
        } catch let error as ToolError {
            if case .invalidArgument(let key, _) = error {
                #expect(key == "query")
            } else {
                Issue.record("expected .invalidArgument, got \(error)")
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
