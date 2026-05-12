import Foundation

// MARK: - Transport Protocol

/// Protocol for MCP transport layers (stdio, HTTP/SSE, etc.)
public protocol MCPTransport: Sendable {
    /// Start the transport and begin accepting messages
    func start() async throws

    /// Stop the transport and clean up resources
    func stop() async throws

    /// Send a JSON-RPC message
    func send(_ message: JSONRPCMessage) async throws

    /// Receive messages from the transport
    var messages: AsyncStream<JSONRPCMessage> { get async }

    /// Check if transport is currently connected
    var isConnected: Bool { get async }
}

// MARK: - Message Types

/// Union type for all JSON-RPC messages
public enum JSONRPCMessage: Sendable {
    case request(JSONRPCRequest)
    case response(JSONRPCResponse)
    case error(JSONRPCError)
    case notification(JSONRPCNotification)

    /// Encode message to JSON data
    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        switch self {
        case .request(let req):
            return try encoder.encode(req)
        case .response(let res):
            return try encoder.encode(res)
        case .error(let err):
            return try encoder.encode(err)
        case .notification(let notif):
            return try encoder.encode(notif)
        }
    }

    /// Decode message from JSON data
    public static func decode(from data: Data) throws -> JSONRPCMessage {
        let decoder = JSONDecoder()

        // Try to determine message type by presence of fields
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if json["id"] != nil {
                if json["method"] != nil {
                    // Has id + method = request
                    let req = try decoder.decode(JSONRPCRequest.self, from: data)
                    return .request(req)
                } else if json["error"] != nil {
                    // Has id + error = error response
                    let err = try decoder.decode(JSONRPCError.self, from: data)
                    return .error(err)
                } else if json["result"] != nil {
                    // Has id + result = success response
                    let res = try decoder.decode(JSONRPCResponse.self, from: data)
                    return .response(res)
                }
            } else if json["method"] != nil {
                // Has method but no id = notification
                let notif = try decoder.decode(JSONRPCNotification.self, from: data)
                return .notification(notif)
            }
        }

        throw TransportError.invalidMessage("Invalid JSON-RPC message format")
    }
}

// MARK: - Transport Errors

public enum TransportError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case sendFailed(String)
    case receiveFailed(String)
    case invalidMessage(String)
    case encodingFailed(Error)
    case decodingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Transport is not connected"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .sendFailed(let reason):
            return "Send failed: \(reason)"
        case .receiveFailed(let reason):
            return "Receive failed: \(reason)"
        case .invalidMessage(let reason):
            return "Invalid message: \(reason)"
        case .encodingFailed(let error):
            return "Encoding failed: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Decoding failed: \(error.localizedDescription)"
        }
    }
}
