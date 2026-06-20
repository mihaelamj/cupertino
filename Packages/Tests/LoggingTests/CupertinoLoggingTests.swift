@testable import Logging
import LoggingModels
import Testing
import TestSupport

// MARK: - Logging Tests

@Test("Logger subsystem and categories are configured correctly")
func loggerConfiguration() {
    // 2026-05-26 post-#1056: the previous shape was a closed set of
    // `public static let <category>` os.Logger instances on
    // `Logging.Logger`. Post-fix the source of truth is a dict
    // keyed by category rawValue; this test pins that every shipped
    // category resolves via the dict.
    for category in Logging.Unified.Category.allKnownCases {
        let raw = category.rawValue == "packages" ? "package-downloader" : category.rawValue
        _ = Logging.Logger.osLogger(for: raw)
    }
    // #1163 item 3: pin the subsystem identifier. `Logging.Logger.subsystem`
    // aliases `Shared.Constants.Logging.subsystem`, so this catches a change
    // to the shared constant that would silently move every log record to a
    // new subsystem and break operator `log show --predicate` playbooks.
    #expect(Logging.Logger.subsystem == "com.cupertino.cli")
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
