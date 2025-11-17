@testable import CupertinoShared
import Foundation
import Testing

// MARK: - JSONCoding Tests

/// Tests for the unified JSONCoding utility
/// Ensures consistent date encoding/decoding across the codebase
@Suite("JSONCoding Utility Tests")
struct JSONCodingTests {
    // MARK: - Test Models

    struct ModelWithDate: Codable, Equatable {
        let name: String
        let createdAt: Date
        let count: Int
    }

    struct ModelWithoutDate: Codable, Equatable {
        let name: String
        let value: Int
    }

    struct NestedModelWithDates: Codable, Equatable {
        let title: String
        let created: Date
        let modified: Date
        let metadata: ModelWithDate
    }

    // MARK: - Encoder Tests

    @Test("Standard encoder uses ISO8601 date strategy")
    func standardEncoderUsesISO8601() throws {
        let date = Date(timeIntervalSince1970: 1700000000) // 2023-11-14T22:13:20Z
        let model = ModelWithDate(name: "Test", createdAt: date, count: 42)

        let encoder = JSONCoding.encoder()
        let data = try encoder.encode(model)
        let jsonString = String(data: data, encoding: .utf8)!

        // ISO8601 format: YYYY-MM-DDTHH:MM:SSZ
        #expect(jsonString.contains("2023-11-14T22:13:20Z"), "Should use ISO8601 date format")
        #expect(!jsonString.contains("1700000000"), "Should NOT use timestamp format")
    }

    @Test("Pretty encoder formats output nicely")
    func prettyEncoderFormatsOutput() throws {
        let model = ModelWithoutDate(name: "Test", value: 123)

        let encoder = JSONCoding.prettyEncoder()
        let data = try encoder.encode(model)
        let jsonString = String(data: data, encoding: .utf8)!

        // Check for pretty formatting
        #expect(jsonString.contains("\n"), "Should contain newlines")
        #expect(jsonString.contains("  "), "Should contain indentation")
    }

    @Test("Pretty encoder uses sorted keys")
    func prettyEncoderUsesSortedKeys() throws {
        let model = ModelWithoutDate(name: "Test", value: 123)

        let encoder = JSONCoding.prettyEncoder()
        let data = try encoder.encode(model)
        let jsonString = String(data: data, encoding: .utf8)!

        // Keys should appear in sorted order: name before value
        let nameIndex = jsonString.range(of: "\"name\"")!.lowerBound
        let valueIndex = jsonString.range(of: "\"value\"")!.lowerBound
        #expect(nameIndex < valueIndex, "Keys should be sorted alphabetically")
    }

    // MARK: - Decoder Tests

    @Test("Standard decoder decodes ISO8601 dates")
    func standardDecoderDecodesISO8601() throws {
        let jsonString = """
        {
            "name": "Test",
            "createdAt": "2023-11-14T22:13:20Z",
            "count": 42
        }
        """
        let data = Data(jsonString.utf8)

        let decoder = JSONCoding.decoder()
        let model = try decoder.decode(ModelWithDate.self, from: data)

        #expect(model.name == "Test")
        #expect(model.count == 42)
        // Date should be decoded correctly from ISO8601
        #expect(abs(model.createdAt.timeIntervalSince1970 - 1700000000) < 1.0)
    }

    @Test("Decoder rejects timestamp format when expecting ISO8601")
    func decoderRejectsTimestampFormat() throws {
        let jsonString = """
        {
            "name": "Test",
            "createdAt": 1700000000,
            "count": 42
        }
        """
        let data = Data(jsonString.utf8)

        let decoder = JSONCoding.decoder()

        // Should throw because we're sending Double timestamp but expecting ISO8601 string
        #expect(throws: (any Error).self) {
            _ = try decoder.decode(ModelWithDate.self, from: data)
        }
    }

    // MARK: - Convenience Method Tests

    @Test("Convenience encode() method works")
    func convenienceEncodeMethodWorks() throws {
        let date = Date(timeIntervalSince1970: 1700000000)
        let model = ModelWithDate(name: "Test", createdAt: date, count: 42)

        let data = try JSONCoding.encode(model)
        let jsonString = String(data: data, encoding: .utf8)!

        #expect(jsonString.contains("Test"))
        #expect(jsonString.contains("2023-11-14T22:13:20Z"))
        #expect(jsonString.contains("42"))
    }

    @Test("Convenience encodePretty() method works")
    func convenienceEncodePrettyMethodWorks() throws {
        let model = ModelWithoutDate(name: "Test", value: 123)

        let data = try JSONCoding.encodePretty(model)
        let jsonString = String(data: data, encoding: .utf8)!

        #expect(jsonString.contains("\n"), "Should be pretty-printed")
        #expect(jsonString.contains("Test"))
        #expect(jsonString.contains("123"))
    }

    @Test("Convenience decode() method works")
    func convenienceDecodeMethodWorks() throws {
        let jsonString = """
        {
            "name": "Test",
            "createdAt": "2023-11-14T22:13:20Z",
            "count": 42
        }
        """
        let data = Data(jsonString.utf8)

        let model = try JSONCoding.decode(ModelWithDate.self, from: data)

        #expect(model.name == "Test")
        #expect(model.count == 42)
    }

    // MARK: - File I/O Tests

    @Test("Encode to file creates directory and saves data")
    func encodeToFileCreatesDirAndSaves() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jsoncodingtest-\(UUID().uuidString)")
        let subdirPath = tempDir.appendingPathComponent("subdir")
        let filePath = subdirPath.appendingPathComponent("test.json")

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let date = Date(timeIntervalSince1970: 1700000000)
        let model = ModelWithDate(name: "Test", createdAt: date, count: 42)

        // Encode to file (should create directory automatically)
        try JSONCoding.encode(model, to: filePath)

        // Verify directory was created
        #expect(FileManager.default.fileExists(atPath: subdirPath.path))

        // Verify file was created
        #expect(FileManager.default.fileExists(atPath: filePath.path))

        // Verify content
        let savedData = try Data(contentsOf: filePath)
        let jsonString = String(data: savedData, encoding: .utf8)!
        #expect(jsonString.contains("Test"))
        #expect(jsonString.contains("2023-11-14T22:13:20Z"))
    }

    @Test("Decode from file loads and decodes data")
    func decodeFromFileLoadsAndDecodes() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).json")

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        // Create test file
        let jsonString = """
        {
            "name": "FileTest",
            "createdAt": "2023-11-14T22:13:20Z",
            "count": 99
        }
        """
        try Data(jsonString.utf8).write(to: tempFile)

        // Decode from file
        let model = try JSONCoding.decode(ModelWithDate.self, from: tempFile)

        #expect(model.name == "FileTest")
        #expect(model.count == 99)
        #expect(abs(model.createdAt.timeIntervalSince1970 - 1700000000) < 1.0)
    }

    // MARK: - Round-trip Tests

    @Test("Encode then decode produces same model")
    func encodeDecodeRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1700000000)
        let original = ModelWithDate(name: "RoundTrip", createdAt: date, count: 777)

        // Encode
        let data = try JSONCoding.encode(original)

        // Decode
        let decoded = try JSONCoding.decode(ModelWithDate.self, from: data)

        #expect(decoded == original)
    }

    @Test("File save then load produces same model")
    func fileSaveLoadRoundTrip() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip-\(UUID().uuidString).json")

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        let date = Date(timeIntervalSince1970: 1700000000)
        let original = ModelWithDate(name: "FileRoundTrip", createdAt: date, count: 888)

        // Save to file
        try JSONCoding.encode(original, to: tempFile)

        // Load from file
        let loaded = try JSONCoding.decode(ModelWithDate.self, from: tempFile)

        #expect(loaded == original)
    }

    @Test("Nested models with dates round-trip correctly")
    func nestedModelsRoundTrip() throws {
        let date1 = Date(timeIntervalSince1970: 1700000000)
        let date2 = Date(timeIntervalSince1970: 1700001000)
        let date3 = Date(timeIntervalSince1970: 1700002000)

        let nested = ModelWithDate(name: "Nested", createdAt: date1, count: 1)
        let original = NestedModelWithDates(
            title: "Parent",
            created: date2,
            modified: date3,
            metadata: nested
        )

        // Encode
        let data = try JSONCoding.encode(original)

        // Decode
        let decoded = try JSONCoding.decode(NestedModelWithDates.self, from: data)

        #expect(decoded == original)
        #expect(decoded.metadata.name == "Nested")
    }

    // MARK: - Edge Cases

    @Test("Empty model encodes and decodes")
    func emptyModelEncodesDecodes() throws {
        struct EmptyModel: Codable, Equatable {}

        let original = EmptyModel()
        let data = try JSONCoding.encode(original)
        let decoded = try JSONCoding.decode(EmptyModel.self, from: data)

        #expect(decoded == original)
    }

    @Test("Model with optional date field")
    func modelWithOptionalDate() throws {
        struct ModelWithOptionalDate: Codable, Equatable {
            let name: String
            let date: Date?
        }

        let withDate = ModelWithOptionalDate(name: "HasDate", date: Date(timeIntervalSince1970: 1700000000))
        let withoutDate = ModelWithOptionalDate(name: "NoDate", date: nil)

        // Test with date
        let data1 = try JSONCoding.encode(withDate)
        let decoded1 = try JSONCoding.decode(ModelWithOptionalDate.self, from: data1)
        #expect(decoded1 == withDate)

        // Test without date
        let data2 = try JSONCoding.encode(withoutDate)
        let decoded2 = try JSONCoding.decode(ModelWithOptionalDate.self, from: data2)
        #expect(decoded2 == withoutDate)
    }

    @Test("Array of models with dates")
    func arrayOfModelsWithDates() throws {
        let models = [
            ModelWithDate(name: "First", createdAt: Date(timeIntervalSince1970: 1700000000), count: 1),
            ModelWithDate(name: "Second", createdAt: Date(timeIntervalSince1970: 1700001000), count: 2),
            ModelWithDate(name: "Third", createdAt: Date(timeIntervalSince1970: 1700002000), count: 3),
        ]

        let data = try JSONCoding.encode(models)
        let decoded = try JSONCoding.decode([ModelWithDate].self, from: data)

        #expect(decoded.count == 3)
        #expect(decoded[0] == models[0])
        #expect(decoded[1] == models[1])
        #expect(decoded[2] == models[2])
    }

    @Test("Dictionary with date values")
    func dictionaryWithDateValues() throws {
        let dict: [String: Date] = [
            "created": Date(timeIntervalSince1970: 1700000000),
            "modified": Date(timeIntervalSince1970: 1700001000),
        ]

        let data = try JSONCoding.encode(dict)
        let decoded = try JSONCoding.decode([String: Date].self, from: data)

        #expect(decoded.count == 2)
        #expect(abs(decoded["created"]!.timeIntervalSince1970 - 1700000000) < 1.0)
        #expect(abs(decoded["modified"]!.timeIntervalSince1970 - 1700001000) < 1.0)
    }

    // MARK: - Consistency Tests

    @Test("Standard and pretty encoders produce compatible output")
    func standardAndPrettyEncodersCompatible() throws {
        let date = Date(timeIntervalSince1970: 1700000000)
        let model = ModelWithDate(name: "Test", createdAt: date, count: 42)

        // Encode with standard encoder
        let standardData = try JSONCoding.encode(model)

        // Encode with pretty encoder
        let prettyData = try JSONCoding.encodePretty(model)

        // Both should decode to the same model
        let decodedFromStandard = try JSONCoding.decode(ModelWithDate.self, from: standardData)
        let decodedFromPretty = try JSONCoding.decode(ModelWithDate.self, from: prettyData)

        #expect(decodedFromStandard == model)
        #expect(decodedFromPretty == model)
        #expect(decodedFromStandard == decodedFromPretty)
    }

    @Test("Encoder produces valid JSON")
    func encoderProducesValidJSON() throws {
        let date = Date(timeIntervalSince1970: 1700000000)
        let model = ModelWithDate(name: "Test", createdAt: date, count: 42)

        let data = try JSONCoding.encode(model)

        // Verify it's valid JSON by parsing with standard JSONSerialization
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        #expect(jsonObject is [String: Any])

        guard let dict = jsonObject as? [String: Any] else {
            #expect(Bool(false), "Failed to cast to dictionary")
            return
        }
        #expect(dict["name"] as? String == "Test")
        #expect(dict["count"] as? Int == 42)
        #expect(dict["createdAt"] as? String == "2023-11-14T22:13:20Z")
    }

    // MARK: - Error Handling Tests

    @Test("Decode throws on invalid JSON")
    func decodeThrowsOnInvalidJSON() throws {
        let invalidJSON = Data("{ this is not valid json }".utf8)

        #expect(throws: (any Error).self) {
            _ = try JSONCoding.decode(ModelWithDate.self, from: invalidJSON)
        }
    }

    @Test("Decode throws on type mismatch")
    func decodeThrowsOnTypeMismatch() throws {
        let jsonString = """
        {
            "name": "Test",
            "value": "this should be an int"
        }
        """
        let data = Data(jsonString.utf8)

        #expect(throws: (any Error).self) {
            _ = try JSONCoding.decode(ModelWithoutDate.self, from: data)
        }
    }

    @Test("Decode from file throws on missing file")
    func decodeFromFileThrowsOnMissingFile() throws {
        let nonExistentFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).json")

        #expect(throws: (any Error).self) {
            _ = try JSONCoding.decode(ModelWithDate.self, from: nonExistentFile)
        }
    }
}
