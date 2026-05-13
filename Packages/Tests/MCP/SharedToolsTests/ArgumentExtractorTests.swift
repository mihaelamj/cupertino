import MCP
import MCPSharedTools
import SharedConstants
import SharedCore
import Testing

@Suite("MCP.SharedTools.ArgumentExtractor")
struct ArgumentExtractorTests {
    // MARK: - Required arguments

    @Test("require returns string value when present")
    func requireReturnsStringValue() throws {
        let args: [String: MCP.Core.Protocols.AnyCodable] = ["query": MCP.Core.Protocols.AnyCodable("swiftui")]
        let extractor = MCP.SharedTools.ArgumentExtractor(args)
        #expect(try extractor.require("query") == "swiftui")
    }

    @Test("require throws missingArgument when key absent")
    func requireThrowsWhenAbsent() {
        let extractor = MCP.SharedTools.ArgumentExtractor(nil)
        #expect(throws: Shared.Core.ToolError.self) {
            _ = try extractor.require("query")
        }
    }

    @Test("require throws when value has wrong type")
    func requireThrowsOnWrongType() {
        let args: [String: MCP.Core.Protocols.AnyCodable] = ["query": MCP.Core.Protocols.AnyCodable(42)]
        let extractor = MCP.SharedTools.ArgumentExtractor(args)
        #expect(throws: Shared.Core.ToolError.self) {
            _ = try extractor.require("query")
        }
    }

    @Test("requireInt returns int value")
    func requireIntReturnsValue() throws {
        let args: [String: MCP.Core.Protocols.AnyCodable] = ["limit": MCP.Core.Protocols.AnyCodable(5)]
        let extractor = MCP.SharedTools.ArgumentExtractor(args)
        #expect(try extractor.requireInt("limit") == 5)
    }

    @Test("requireBool returns bool value")
    func requireBoolReturnsValue() throws {
        let args: [String: MCP.Core.Protocols.AnyCodable] = ["include_archive": MCP.Core.Protocols.AnyCodable(true)]
        let extractor = MCP.SharedTools.ArgumentExtractor(args)
        #expect(try extractor.requireBool("include_archive") == true)
    }

    // MARK: - Optional arguments

    @Test("optional returns nil when absent")
    func optionalReturnsNilWhenAbsent() {
        let extractor = MCP.SharedTools.ArgumentExtractor(nil)
        #expect(extractor.optional("framework") == nil)
    }

    @Test("optional returns value when present")
    func optionalReturnsValueWhenPresent() {
        let args: [String: MCP.Core.Protocols.AnyCodable] = ["framework": MCP.Core.Protocols.AnyCodable("swiftui")]
        let extractor = MCP.SharedTools.ArgumentExtractor(args)
        #expect(extractor.optional("framework") == "swiftui")
    }

    @Test("optional with default returns default when absent")
    func optionalWithDefaultReturnsDefault() {
        let extractor = MCP.SharedTools.ArgumentExtractor(nil)
        #expect(extractor.optional("language", default: "en") == "en")
    }

    @Test("optional with default returns value when present")
    func optionalWithDefaultReturnsValue() {
        let args: [String: MCP.Core.Protocols.AnyCodable] = ["language": MCP.Core.Protocols.AnyCodable("de")]
        let extractor = MCP.SharedTools.ArgumentExtractor(args)
        #expect(extractor.optional("language", default: "en") == "de")
    }

    // MARK: - limit clamping

    @Test("limit returns the default when absent")
    func limitReturnsDefaultWhenAbsent() {
        let extractor = MCP.SharedTools.ArgumentExtractor(nil)
        #expect(extractor.limit() == Shared.Constants.Limit.defaultSearchLimit)
    }

    @Test("limit returns requested value when below max")
    func limitReturnsValueBelowMax() {
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamLimit: MCP.Core.Protocols.AnyCodable(15),
        ]
        let extractor = MCP.SharedTools.ArgumentExtractor(args)
        #expect(extractor.limit() == 15)
    }

    @Test("limit clamps to maxSearchLimit when requested exceeds max")
    func limitClampsToMax() {
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamLimit: MCP.Core.Protocols.AnyCodable(9999),
        ]
        let extractor = MCP.SharedTools.ArgumentExtractor(args)
        #expect(extractor.limit() == Shared.Constants.Limit.maxSearchLimit)
    }

    // MARK: - format default

    @Test("format returns formatValueJSON when absent")
    func formatReturnsJSONDefault() {
        let extractor = MCP.SharedTools.ArgumentExtractor(nil)
        #expect(extractor.format() == Shared.Constants.Search.formatValueJSON)
    }

    @Test("format returns supplied value when present")
    func formatReturnsValueWhenPresent() {
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamFormat: MCP.Core.Protocols.AnyCodable(
                Shared.Constants.Search.formatValueMarkdown
            ),
        ]
        let extractor = MCP.SharedTools.ArgumentExtractor(args)
        #expect(extractor.format() == Shared.Constants.Search.formatValueMarkdown)
    }

    // MARK: - includeArchive default

    @Test("includeArchive defaults to false")
    func includeArchiveDefaultsFalse() {
        let extractor = MCP.SharedTools.ArgumentExtractor(nil)
        #expect(extractor.includeArchive() == false)
    }

    @Test("includeArchive reads supplied value")
    func includeArchiveReadsValue() {
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamIncludeArchive: MCP.Core.Protocols.AnyCodable(true),
        ]
        let extractor = MCP.SharedTools.ArgumentExtractor(args)
        #expect(extractor.includeArchive() == true)
    }

    // MARK: - platform-version filters

    @Test("minIOS reads supplied value, nil when absent")
    func minIOSReadsValue() {
        let absent = MCP.SharedTools.ArgumentExtractor(nil)
        #expect(absent.minIOS() == nil)

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamMinIOS: MCP.Core.Protocols.AnyCodable("17.0"),
        ]
        let extractor = MCP.SharedTools.ArgumentExtractor(args)
        #expect(extractor.minIOS() == "17.0")
    }

    @Test("minMacOS / minTvOS / minWatchOS / minVisionOS round-trip")
    func minPlatformsRoundTrip() {
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamMinMacOS: MCP.Core.Protocols.AnyCodable("14.0"),
            Shared.Constants.Search.schemaParamMinTvOS: MCP.Core.Protocols.AnyCodable("17.0"),
            Shared.Constants.Search.schemaParamMinWatchOS: MCP.Core.Protocols.AnyCodable("10.0"),
            Shared.Constants.Search.schemaParamMinVisionOS: MCP.Core.Protocols.AnyCodable("1.0"),
        ]
        let extractor = MCP.SharedTools.ArgumentExtractor(args)
        #expect(extractor.minMacOS() == "14.0")
        #expect(extractor.minTvOS() == "17.0")
        #expect(extractor.minWatchOS() == "10.0")
        #expect(extractor.minVisionOS() == "1.0")
    }
}
