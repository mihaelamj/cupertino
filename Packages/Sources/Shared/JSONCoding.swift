import Foundation

// MARK: - Unified JSON Encoding/Decoding

/// Centralized JSON encoding/decoding utilities with consistent date strategies
/// This ensures all JSON operations use the same date format (ISO8601)
public enum JSONCoding {
    // MARK: - Standard Encoders

    /// Standard JSON encoder with ISO8601 date encoding
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Pretty-printed JSON encoder with ISO8601 date encoding
    public static func prettyEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // MARK: - Standard Decoders

    /// Standard JSON decoder with ISO8601 date decoding
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Convenience Methods

    /// Encode to JSON Data with standard encoder
    public static func encode(_ value: some Encodable) throws -> Data {
        try encoder().encode(value)
    }

    /// Encode to pretty-printed JSON Data
    public static func encodePretty(_ value: some Encodable) throws -> Data {
        try prettyEncoder().encode(value)
    }

    /// Decode from JSON Data with standard decoder
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }

    /// Decode from JSON file with standard decoder
    public static func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try decode(type, from: data)
    }

    /// Encode to JSON file with pretty-printed encoder
    public static func encode(_ value: some Encodable, to url: URL) throws {
        let data = try encodePretty(value)

        // Ensure directory exists
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        try data.write(to: url)
    }
}
