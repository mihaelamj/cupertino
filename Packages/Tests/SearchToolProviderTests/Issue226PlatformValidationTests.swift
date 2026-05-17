import Foundation
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

// MARK: - #226 — platform value validation

// Pre-#226 the 5 `min_*` args silently accepted any string. Empty, whitespace,
// `"v18.0"`, `"18.0a"`, `"ios18"`, `"18..0"` all flowed through to
// `Search.PlatformFilter.passes(...)` and produced surprising matches against
// the lexicographic-after-split-on-dot comparator. #226 bullet 2 (in the
// shipped 5-field shape) is "reject malformed input at the MCP boundary so
// AI clients see a clear error rather than a silent no-op."
//
// `CompositeToolProvider.validatePlatformValue` is the central seam. These
// tests pin its decision tree directly without standing up the full MCP
// dispatch.

@Suite("#226 — CompositeToolProvider.validatePlatformValue")
struct Issue226PlatformValidationTests {
    private static let paramName = Shared.Constants.Search.schemaParamMinIOS

    @Test("nil input returns nil (no filter intended)")
    func nilPassesThrough() throws {
        let result = try CompositeToolProvider.validatePlatformValue(nil, paramName: Self.paramName)
        #expect(result == nil)
    }

    @Test(
        "Accepted shapes return the trimmed canonical form",
        arguments: [
            ("18", "18"),
            ("18.0", "18.0"),
            ("18.0.1", "18.0.1"),
            ("18.0.1.2", "18.0.1.2"),
            ("  18.0  ", "18.0"),
            ("\t18.0\n", "18.0"),
        ]
    )
    func acceptedShapes(input: String, expected: String) throws {
        let result = try CompositeToolProvider.validatePlatformValue(input, paramName: Self.paramName)
        #expect(result == expected)
    }

    @Test(
        "Rejected shapes throw invalidArgument",
        arguments: [
            "", // empty
            "   ", // whitespace only
            "v18.0", // leading letter
            "18.0a", // trailing letter
            "ios18", // platform-prefixed
            "18..0", // empty interior segment
            ".18", // leading dot
            "18.", // trailing dot
            "18.0.x", // letter in segment
            "18,0", // wrong separator
            "18 0", // space in middle
        ]
    )
    func rejectedShapes(input: String) {
        #expect(throws: Shared.Core.ToolError.self) {
            _ = try CompositeToolProvider.validatePlatformValue(input, paramName: Self.paramName)
        }
    }

    @Test("Empty / whitespace input carries clear error message")
    func emptyMessageIsClear() {
        do {
            _ = try CompositeToolProvider.validatePlatformValue("", paramName: Self.paramName)
            Issue.record("expected throw for empty input")
        } catch let error as Shared.Core.ToolError {
            switch error {
            case let .invalidArgument(name, message):
                #expect(name == Self.paramName)
                #expect(message.lowercased().contains("empty") || message.lowercased().contains("whitespace"))
            default:
                Issue.record("expected .invalidArgument, got \(error)")
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("Malformed input carries paramName + offending value in message")
    func malformedMessageNamesValue() {
        do {
            _ = try CompositeToolProvider.validatePlatformValue("v18.0", paramName: Self.paramName)
            Issue.record("expected throw for malformed input")
        } catch let error as Shared.Core.ToolError {
            switch error {
            case let .invalidArgument(name, message):
                #expect(name == Self.paramName)
                #expect(message.contains("v18.0"))
            default:
                Issue.record("expected .invalidArgument, got \(error)")
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
