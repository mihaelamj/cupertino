import MCP
import MCPSharedTools
import SharedCore
import Testing
import SharedConstants

@Suite("ArgumentExtractor")
struct ArgumentExtractorTests {
    // MARK: - Required arguments

    @Test("require returns string value when present")
    func requireReturnsStringValue() throws {
        let args: [String: AnyCodable] = ["query": AnyCodable("swiftui")]
        let extractor = ArgumentExtractor(args)
        #expect(try extractor.require("query") == "swiftui")
    }

    @Test("require throws missingArgument when key absent")
    func requireThrowsWhenAbsent() {
        let extractor = ArgumentExtractor(nil)
        #expect(throws: ToolError.self) {
            _ = try extractor.require("query")
        }
    }

    @Test("require throws when value has wrong type")
    func requireThrowsOnWrongType() {
        let args: [String: AnyCodable] = ["query": AnyCodable(42)]
        let extractor = ArgumentExtractor(args)
        #expect(throws: ToolError.self) {
            _ = try extractor.require("query")
        }
    }

    @Test("requireInt returns int value")
    func requireIntReturnsValue() throws {
        let args: [String: AnyCodable] = ["limit": AnyCodable(5)]
        let extractor = ArgumentExtractor(args)
        #expect(try extractor.requireInt("limit") == 5)
    }

    @Test("requireBool returns bool value")
    func requireBoolReturnsValue() throws {
        let args: [String: AnyCodable] = ["include_archive": AnyCodable(true)]
        let extractor = ArgumentExtractor(args)
        #expect(try extractor.requireBool("include_archive") == true)
    }

    // MARK: - Optional arguments

    @Test("optional returns nil when absent")
    func optionalReturnsNilWhenAbsent() {
        let extractor = ArgumentExtractor(nil)
        #expect(extractor.optional("framework") == nil)
    }

    @Test("optional returns value when present")
    func optionalReturnsValueWhenPresent() {
        let args: [String: AnyCodable] = ["framework": AnyCodable("swiftui")]
        let extractor = ArgumentExtractor(args)
        #expect(extractor.optional("framework") == "swiftui")
    }

    @Test("optional with default returns default when absent")
    func optionalWithDefaultReturnsDefault() {
        let extractor = ArgumentExtractor(nil)
        #expect(extractor.optional("language", default: "en") == "en")
    }

    @Test("optional with default returns value when present")
    func optionalWithDefaultReturnsValue() {
        let args: [String: AnyCodable] = ["language": AnyCodable("de")]
        let extractor = ArgumentExtractor(args)
        #expect(extractor.optional("language", default: "en") == "de")
    }

    // MARK: - limit clamping

    @Test("limit returns the default when absent")
    func limitReturnsDefaultWhenAbsent() {
        let extractor = ArgumentExtractor(nil)
        #expect(extractor.limit() == Shared.Constants.Limit.defaultSearchLimit)
    }

    @Test("limit returns requested value when below max")
    func limitReturnsValueBelowMax() {
        let args: [String: AnyCodable] = [
            Shared.Constants.Search.schemaParamLimit: AnyCodable(15),
        ]
        let extractor = ArgumentExtractor(args)
        #expect(extractor.limit() == 15)
    }

    @Test("limit clamps to maxSearchLimit when requested exceeds max")
    func limitClampsToMax() {
        let args: [String: AnyCodable] = [
            Shared.Constants.Search.schemaParamLimit: AnyCodable(9999),
        ]
        let extractor = ArgumentExtractor(args)
        #expect(extractor.limit() == Shared.Constants.Limit.maxSearchLimit)
    }

    // MARK: - format default

    @Test("format returns formatValueJSON when absent")
    func formatReturnsJSONDefault() {
        let extractor = ArgumentExtractor(nil)
        #expect(extractor.format() == Shared.Constants.Search.formatValueJSON)
    }

    @Test("format returns supplied value when present")
    func formatReturnsValueWhenPresent() {
        let args: [String: AnyCodable] = [
            Shared.Constants.Search.schemaParamFormat: AnyCodable(
                Shared.Constants.Search.formatValueMarkdown
            ),
        ]
        let extractor = ArgumentExtractor(args)
        #expect(extractor.format() == Shared.Constants.Search.formatValueMarkdown)
    }

    // MARK: - includeArchive default

    @Test("includeArchive defaults to false")
    func includeArchiveDefaultsFalse() {
        let extractor = ArgumentExtractor(nil)
        #expect(extractor.includeArchive() == false)
    }

    @Test("includeArchive reads supplied value")
    func includeArchiveReadsValue() {
        let args: [String: AnyCodable] = [
            Shared.Constants.Search.schemaParamIncludeArchive: AnyCodable(true),
        ]
        let extractor = ArgumentExtractor(args)
        #expect(extractor.includeArchive() == true)
    }

    // MARK: - platform-version filters

    @Test("minIOS reads supplied value, nil when absent")
    func minIOSReadsValue() {
        let absent = ArgumentExtractor(nil)
        #expect(absent.minIOS() == nil)

        let args: [String: AnyCodable] = [
            Shared.Constants.Search.schemaParamMinIOS: AnyCodable("17.0"),
        ]
        let extractor = ArgumentExtractor(args)
        #expect(extractor.minIOS() == "17.0")
    }

    @Test("minMacOS / minTvOS / minWatchOS / minVisionOS round-trip")
    func minPlatformsRoundTrip() {
        let args: [String: AnyCodable] = [
            Shared.Constants.Search.schemaParamMinMacOS: AnyCodable("14.0"),
            Shared.Constants.Search.schemaParamMinTvOS: AnyCodable("17.0"),
            Shared.Constants.Search.schemaParamMinWatchOS: AnyCodable("10.0"),
            Shared.Constants.Search.schemaParamMinVisionOS: AnyCodable("1.0"),
        ]
        let extractor = ArgumentExtractor(args)
        #expect(extractor.minMacOS() == "14.0")
        #expect(extractor.minTvOS() == "17.0")
        #expect(extractor.minWatchOS() == "10.0")
        #expect(extractor.minVisionOS() == "1.0")
    }
}
