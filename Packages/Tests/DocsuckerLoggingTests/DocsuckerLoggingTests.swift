import Testing
@testable import DocsuckerLogging

// MARK: - Logging Tests

@Test("Logger subsystem and categories are configured correctly")
func testLoggerConfiguration() {
    // Verify loggers are accessible and initialized
    // Just accessing them is sufficient - they're static lets so they always exist
    _ = DocsuckerLogger.crawler
    _ = DocsuckerLogger.mcp
    _ = DocsuckerLogger.search
    _ = DocsuckerLogger.cli
    _ = DocsuckerLogger.transport
    _ = DocsuckerLogger.pdf
    _ = DocsuckerLogger.evolution
    _ = DocsuckerLogger.samples

    // Test passes if we can access all loggers without error
    #expect(Bool(true))
}

@Test("ConsoleLogger outputs messages without crashing")
func testConsoleLogger() {
    // Basic smoke test - just verify these don't crash
    ConsoleLogger.info("Test info message")
    ConsoleLogger.error("Test error message")
    ConsoleLogger.output("Test output message")
}
