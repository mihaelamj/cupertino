import Foundation

// MARK: - JSON-RPC 2.0 Base Types

/// Type alias for request/response IDs (can be string or integer)
public enum RequestID: Codable, Hashable, Sendable {
    case string(String)
    case int(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                RequestID.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected String or Int"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        }
    }
}

/// JSON-RPC 2.0 Request
public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: RequestID
    public let method: String
    public let params: [String: AnyCodable]?

    public init(id: RequestID, method: String, params: [String: AnyCodable]? = nil) {
        jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 Notification (no response expected)
public struct JSONRPCNotification: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: [String: AnyCodable]?

    public init(method: String, params: [String: AnyCodable]? = nil) {
        jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

/// Generic MCP Request wrapper for type-safe requests
public struct MCPRequest<Params: Codable>: Codable, Sendable where Params: Sendable {
    public let jsonrpc: String
    public let id: RequestID
    public let method: String
    public let params: Params

    public init(jsonrpc: String = "2.0", id: RequestID, method: String, params: Params) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 Success Response
public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: RequestID
    public let result: [String: AnyCodable]

    public init(id: RequestID, result: [String: AnyCodable]) {
        jsonrpc = "2.0"
        self.id = id
        self.result = result
    }
}

/// JSON-RPC 2.0 Error Response
public struct JSONRPCError: Codable, Sendable {
    public let jsonrpc: String
    public let id: RequestID
    public let error: ErrorDetail

    public init(id: RequestID, error: ErrorDetail) {
        jsonrpc = "2.0"
        self.id = id
        self.error = error
    }

    public struct ErrorDetail: Codable, Sendable {
        public let code: Int
        public let message: String
        public let data: AnyCodable?

        public init(code: Int, message: String, data: AnyCodable? = nil) {
            self.code = code
            self.message = message
            self.data = data
        }
    }
}

/// Standard JSON-RPC error codes + MCP extensions
public enum ErrorCode: Int, Sendable {
    // JSON-RPC standard errors
    case parseError = -32700
    case invalidRequest = -32600
    case methodNotFound = -32601
    case invalidParams = -32602
    case internalError = -32603

    // MCP-specific errors
    case connectionClosed = -32000
    case requestTimeout = -32001

    public var message: String {
        switch self {
        case .parseError:
            return "Parse error"
        case .invalidRequest:
            return "Invalid request"
        case .methodNotFound:
            return "Method not found"
        case .invalidParams:
            return "Invalid params"
        case .internalError:
            return "Internal error"
        case .connectionClosed:
            return "Connection closed"
        case .requestTimeout:
            return "Request timeout"
        }
    }
}

/// JSON value type for tool arguments and similar use cases
public enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode JSONValue"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

/// Type-erased Codable wrapper for heterogeneous JSON values
public struct AnyCodable: Codable, Sendable {
    private enum Storage: Sendable {
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        case array([AnyCodable])
        case dictionary([String: AnyCodable])
        case null
    }

    private let storage: Storage

    public var value: Any {
        switch storage {
        case .bool(let boolValue): return boolValue
        case .int(let intValue): return intValue
        case .double(let doubleValue): return doubleValue
        case .string(let stringValue): return stringValue
        case .array(let arrayValue): return arrayValue.map(\.value)
        case .dictionary(let dictValue): return dictValue.mapValues { $0.value }
        case .null: return NSNull()
        }
    }

    /// Extract dictionary value preserving AnyCodable wrappers
    public var dictionaryValue: [String: AnyCodable]? {
        if case .dictionary(let dict) = storage {
            return dict
        }
        return nil
    }

    public init(_ value: some Sendable & Encodable) {
        switch value {
        case let bool as Bool:
            storage = .bool(bool)
        case let int as Int:
            storage = .int(int)
        case let double as Double:
            storage = .double(double)
        case let string as String:
            storage = .string(string)
        case let array as [AnyCodable]:
            storage = .array(array)
        case let dict as [String: AnyCodable]:
            storage = .dictionary(dict)
        default:
            // Fallback for complex types
            storage = .null
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            storage = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            storage = .int(int)
        } else if let double = try? container.decode(Double.self) {
            storage = .double(double)
        } else if let string = try? container.decode(String.self) {
            storage = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            storage = .array(array)
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            storage = .dictionary(dictionary)
        } else {
            storage = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch storage {
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
