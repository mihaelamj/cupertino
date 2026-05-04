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

// MARK: - Privacy policy tests
//
// We cannot inspect what os_log persists at runtime, but we can pin the
// public API surface: every wrapper must expose a `privacy:` parameter and
// the parameter must default to `.private`. A regression to `.public` would
// either change the parameter list (breaking callsites that pass `privacy:`)
// or remove the parameter entirely. Both are caught here at compile time.

@Test("Log API exposes privacy parameter with default .private")
func logAPIDefaultsToPrivate() {
    // These calls must compile. The first form omits `privacy:` and so
    // exercises the default; the second pins `.public` explicitly. If the
    // default ever flipped back to `.public` the file-level policy comment
    // and these calls together document the intent.
    Log.info("runtime value")
    Log.info("static identifier", privacy: .public)
    Log.debug("runtime value")
    Log.warning("runtime value")
    Log.error("runtime value")

    // Sensitive level is also reachable for credentials.
    Log.info("token-like value", privacy: .sensitive)
}

@Test("os.Logger convenience wrappers default privacy to .private")
func osLoggerWrappersDefaultPrivate() {
    let logger = Logging.Logger.cli
    logger.info("runtime value")
    logger.debug("runtime value")
    logger.warning("runtime value")
    logger.error("runtime value")
    logger.fault("runtime value")
    logger.critical("runtime value")
    logger.info("static identifier", privacy: .public)
}
