import Foundation
import MCPShared

// MARK: - Stdio Transport

/// Transport implementation using standard input/output streams
/// This is the primary transport for Claude Desktop and CLI tools
public actor StdioTransport: MCPTransport {
    private let input: FileHandle
    private let output: FileHandle
    private var inputTask: Task<Void, Never>?
    private let messagesContinuation: AsyncStream<JSONRPCMessage>.Continuation
    private let _messages: AsyncStream<JSONRPCMessage>
    private var _isConnected: Bool = false

    public var messages: AsyncStream<JSONRPCMessage> {
        get async { _messages }
    }

    public var isConnected: Bool {
        get async { _isConnected }
    }

    public init(
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput
    ) {
        self.input = input
        self.output = output

        var continuation: AsyncStream<JSONRPCMessage>.Continuation!
        _messages = AsyncStream { continuation = $0 }
        messagesContinuation = continuation
    }

    public func start() async throws {
        guard !_isConnected else {
            return
        }

        _isConnected = true

        // Start reading from stdin in background task
        inputTask = Task { [weak self] in
            await self?.readLoop()
        }
    }

    public func stop() async throws {
        guard _isConnected else {
            return
        }

        _isConnected = false
        inputTask?.cancel()
        inputTask = nil
        messagesContinuation.finish()
    }

    public func send(_ message: JSONRPCMessage) async throws {
        guard _isConnected else {
            throw TransportError.notConnected
        }

        do {
            let data = try message.encode()

            // Write newline-delimited JSON
            var outputData = data
            outputData.append(contentsOf: [0x0a]) // \n

            try output.write(contentsOf: outputData)

            // Log to stderr for debugging (not stdout which is used for protocol)
            if let messageStr = String(data: data, encoding: .utf8) {
                fputs("→ \(messageStr)\n", stderr)
            }
        } catch {
            throw TransportError.sendFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Methods

    private func readLoop() async {
        var buffer = Data()

        do {
            // Use async bytes sequence (non-blocking, async iteration)
            for try await byte in input.bytes {
                guard _isConnected else {
                    break
                }

                buffer.append(byte)

                // Process complete lines (newline-delimited JSON)
                if byte == 0x0a { // \n
                    let lineData = Data(buffer.dropLast()) // Remove the newline

                    // Skip empty lines
                    if !lineData.isEmpty {
                        // Parse and emit message
                        do {
                            let message = try JSONRPCMessage.decode(from: lineData)

                            // Log to stderr for debugging
                            if let messageStr = String(data: lineData, encoding: .utf8) {
                                fputs("← \(messageStr)\n", stderr)
                            }

                            messagesContinuation.yield(message)
                        } catch {
                            fputs("Error decoding message: \(error)\n", stderr)
                        }
                    }

                    // Clear buffer for next message
                    buffer.removeAll(keepingCapacity: true)
                }
            }
        } catch {
            if _isConnected {
                fputs("Error reading stdin: \(error)\n", stderr)
            }
        }

        // Clean up when loop exits
        messagesContinuation.finish()
    }
}

// MARK: - FileHandle Extensions

extension FileHandle {
    /// Write data to the file handle
    func write(contentsOf data: Data) throws {
        #if canImport(Darwin)
        write(data)
        #else
        try write(contentsOf: data)
        #endif
    }
}
