@testable import CLI
import Foundation
import Testing

// MARK: - #885: `cupertino setup --force` migration hint

/// `--force` was removed from `setup` in v1.2.0 (setup now overwrites by
/// default). A user typing it from muscle memory used to hit the bare
/// swift-argument-parser `Unknown option '--force'` error, which names neither
/// v1.2.0 nor the replacement. `setup` now keeps `--force` as a hidden parse
/// target whose `validate()` throws an actionable migration hint instead.
///
/// Note: ArgumentParser runs `validate()` as part of `parse(_:)`, so the hint
/// surfaces when the arguments are parsed (wrapped in a `CommandError` whose
/// description carries the message), which is exactly the user-facing path.
struct Issue885SetupForceHintTests {
    @Test("setup --force throws the v1.2.0 migration hint, not a bare unknown-option error")
    func forceThrowsMigrationHint() {
        do {
            _ = try CLIImpl.Command.Setup.parse(["--force"])
            Issue.record("expected `setup --force` to throw")
        } catch {
            // The error must name the removal version and the replacement flag,
            // so the user does not have to dig through the README / CHANGELOG.
            let message = "\(error)"
            #expect(message.contains("--force was removed in v1.2.0"))
            #expect(message.contains("--keep-existing"))
        }
    }

    @Test("setup --force --keep-existing still rejects (the --force is the invalid token)")
    func forceWithKeepExistingStillRejects() {
        #expect(throws: (any Error).self) {
            _ = try CLIImpl.Command.Setup.parse(["--force", "--keep-existing"])
        }
    }

    @Test("setup without --force parses cleanly (the interception fires only on --force)")
    func cleanInvocationParses() throws {
        // Non-vacuous: proves the interception does not reject every invocation,
        // only the one carrying the removed flag. `parse` runs `validate()`, so
        // a no-force invocation completing without throwing is the assertion.
        _ = try CLIImpl.Command.Setup.parse(["--keep-existing"])
    }
}
