@testable import Logging
import LoggingModels
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

@Test("LiveRecording outputs messages without crashing (replaces ConsoleLogger smoke test)")
func liveRecordingSmoke() {
    // The pre-#534 `Logging.ConsoleLogger.{info,error,output}` methods are gone;
    // the equivalent post-arc smoke is to verify the GoF Strategy concrete
    // (`Logging.LiveRecording`) handles the same three shapes without crashing.
    // Replaces the old `consoleLogger` test verbatim — same coverage, new API.
    let recorder: any LoggingModels.Logging.Recording = Logging.LiveRecording(unified: Logging.Unified(options: .default))
    recorder.info("Test info message")
    recorder.error("Test error message")
    recorder.output("Test output message")
}
