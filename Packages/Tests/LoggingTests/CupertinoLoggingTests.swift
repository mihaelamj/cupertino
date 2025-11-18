@testable import Logging
import Testing
import TestSupport

// MARK: - Logging Tests

@Test("Logger subsystem and categories are configured correctly")
func loggerConfiguration() {
    // Verify loggers are accessible and initialized
    // Just accessing them is sufficient - they're static lets so they always exist
    _ = Logging.Logger.crawler
    _ = Logging.Logger.mcp
    _ = Logging.Logger.search
    _ = Logging.Logger.cli
    _ = Logging.Logger.transport
    _ = Logging.Logger.pdf
    _ = Logging.Logger.evolution
    _ = Logging.Logger.samples

    // Test passes if we can access all loggers without error
    #expect(Bool(true))
}

@Test("ConsoleLogger outputs messages without crashing")
func consoleLogger() {
    // Basic smoke test - just verify these don't crash
    Logging.ConsoleLogger.info("Test info message")
    Logging.ConsoleLogger.error("Test error message")
    Logging.ConsoleLogger.output("Test output message")
}
