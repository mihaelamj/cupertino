import Foundation

// MARK: - Transport Protocol

/// Protocol for MCP transport layers (stdio, HTTP/SSE, etc.)
extension MCP.Core.Transport {
    public protocol Channel: Sendable {
        /// Start the transport and begin accepting messages
        func start() async throws

        /// Stop the transport and clean up resources
        func stop() async throws

        /// Send a JSON-RPC message
        func send(_ message: Message) async throws

        /// Receive messages from the transport
        var messages: AsyncStream<Message> { get async }

        /// Check if transport is currently connected
        var isConnected: Bool { get async }
    }
}

// MARK: - Message Types

/// Union type for all JSON-RPC messages
extension MCP.Core.Transport {
    public enum Message: Sendable {
        case request(MCP.Core.Protocols.JSONRPCRequest)
        case response(MCP.Core.Protocols.JSONRPCResponse)
        case error(MCP.Core.Protocols.JSONRPCError)
        case notification(MCP.Core.Protocols.JSONRPCNotification)

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
        public static func decode(from data: Data) throws -> Message {
            let decoder = JSONDecoder()

            // Try to determine message type by presence of fields
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if json["id"] != nil {
                    if json["method"] != nil {
                        // Has id + method = request
                        let req = try decoder.decode(MCP.Core.Protocols.JSONRPCRequest.self, from: data)
                        return .request(req)
                    } else if json["error"] != nil {
                        // Has id + error = error response
                        let err = try decoder.decode(MCP.Core.Protocols.JSONRPCError.self, from: data)
                        return .error(err)
                    } else if json["result"] != nil {
                        // Has id + result = success response
                        let res = try decoder.decode(MCP.Core.Protocols.JSONRPCResponse.self, from: data)
                        return .response(res)
                    }
                } else if json["method"] != nil {
                    // Has method but no id = notification
                    let notif = try decoder.decode(MCP.Core.Protocols.JSONRPCNotification.self, from: data)
                    return .notification(notif)
                }
            }

            throw Failure.invalidMessage("Invalid JSON-RPC message format")
        }
    }
}

// MARK: - Transport Errors

extension MCP.Core.Transport {
    public enum Failure: Error, LocalizedError {
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
}
