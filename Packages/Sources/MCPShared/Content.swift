import Foundation

// MARK: - MCP Content Type Constants

/// MCP protocol content type identifiers
public enum MCPContentType {
    /// Text content type identifier
    public static let text = "text"

    /// Image content type identifier
    public static let image = "image"

    /// Resource content type identifier
    public static let resource = "resource"
}

// MARK: - Content Blocks

/// Content blocks that can be returned from tools, prompts, or resources
public enum ContentBlock: Codable, Sendable {
    case text(TextContent)
    case image(ImageContent)
    case resource(EmbeddedResource)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case MCPContentType.text:
            let textContent = try TextContent(from: decoder)
            self = .text(textContent)
        case MCPContentType.image:
            let imageContent = try ImageContent(from: decoder)
            self = .image(imageContent)
        case MCPContentType.resource:
            let resourceContent = try EmbeddedResource(from: decoder)
            self = .resource(resourceContent)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let content):
            try content.encode(to: encoder)
        case .image(let content):
            try content.encode(to: encoder)
        case .resource(let content):
            try content.encode(to: encoder)
        }
    }
}

/// Text content block
public struct TextContent: Codable, Sendable {
    public let type: String = MCPContentType.text
    public let text: String

    enum CodingKeys: String, CodingKey {
        case text
    }

    public init(text: String) {
        self.text = text
    }
}

/// Image content block (base64 encoded)
public struct ImageContent: Codable, Sendable {
    public let type: String = MCPContentType.image
    public let data: String // base64 encoded
    public let mimeType: String

    enum CodingKeys: String, CodingKey {
        case data, mimeType
    }

    public init(data: String, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

/// Embedded resource content
public struct EmbeddedResource: Codable, Sendable {
    public let type: String = MCPContentType.resource
    public let resource: ResourceContents

    enum CodingKeys: String, CodingKey {
        case resource
    }

    public init(resource: ResourceContents) {
        self.resource = resource
    }
}

// MARK: - Resource Contents

public enum ResourceContents: Codable, Sendable {
    case text(TextResourceContents)
    case blob(BlobResourceContents)

    private enum CodingKeys: String, CodingKey {
        case text
        case blob
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let textContents = try? container.decode(TextResourceContents.self) {
            self = .text(textContents)
        } else if let blobContents = try? container.decode(BlobResourceContents.self) {
            self = .blob(blobContents)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode resource contents"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let contents):
            try contents.encode(to: encoder)
        case .blob(let contents):
            try contents.encode(to: encoder)
        }
    }
}

public struct TextResourceContents: Codable, Sendable {
    public let uri: String
    public let mimeType: String?
    public let text: String

    public init(uri: String, mimeType: String? = nil, text: String) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
    }
}

public struct BlobResourceContents: Codable, Sendable {
    public let uri: String
    public let mimeType: String?
    public let blob: String // base64 encoded

    public init(uri: String, mimeType: String? = nil, blob: String) {
        self.uri = uri
        self.mimeType = mimeType
        self.blob = blob
    }
}
