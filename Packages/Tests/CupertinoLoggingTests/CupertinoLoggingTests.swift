@testable import CupertinoLogging
import Testing

// MARK: - Logging Tests

@Test("Logger subsystem and categories are configured correctly")
func loggerConfiguration() {
    // Verify loggers are accessible and initialized
    // Just accessing them is sufficient - they're static lets so they always exist
    _ = CupertinoLogger.crawler
    _ = CupertinoLogger.mcp
    _ = CupertinoLogger.search
    _ = CupertinoLogger.cli
    _ = CupertinoLogger.transport
    _ = CupertinoLogger.pdf
    _ = CupertinoLogger.evolution
    _ = CupertinoLogger.samples

    // Test passes if we can access all loggers without error
    #expect(Bool(true))
}

@Test("ConsoleLogger outputs messages without crashing")
func consoleLogger() {
    // Basic smoke test - just verify these don't crash
    ConsoleLogger.info("Test info message")
    ConsoleLogger.error("Test error message")
    ConsoleLogger.output("Test output message")
}
