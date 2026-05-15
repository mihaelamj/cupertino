@testable import CLI
import Foundation
import SharedConstants
import Testing

// Covers #280's opt-out surface: both `--no-reap` CLI flag and the
// `CUPERTINO_DISABLE_REAPER=1` env var must disable
// `ServeReaper.reapSiblings()`. The reap-or-skip decision lives in
// `Serve.run()` itself and is pure (boolean OR over flag + env), so
// we don't need to run the actor — we just pin the constants the
// decision reads.

@Suite("ServeReaper opt-out surface (#280)")
struct ServeReaperFlagAndEnvTests {
    @Test("EnvVar.disableReaper exposes the canonical CUPERTINO_DISABLE_REAPER name")
    func envVarName() {
        // Pin the env-var name. Codex CLI users put this in their TOML
        // (`env.CUPERTINO_DISABLE_REAPER = "1"`); a rename here would
        // silently break every working Codex install.
        #expect(Shared.Constants.EnvVar.disableReaper == "CUPERTINO_DISABLE_REAPER")
    }

    @Test("`Serve.noReap` flag defaults to false (reaper stays on by default)")
    func noReapFlagDefault() throws {
        // Parse `cupertino serve` with no flag — Claude Desktop / Cursor
        // case. ServeCommand should keep reaping by default; that's the
        // #242 contract.
        let serve = try CLIImpl.Command.Serve.parse([])
        #expect(serve.noReap == false)
    }

    @Test("`Serve.noReap` flag honoured when present")
    func noReapFlagExplicit() throws {
        // OpenAI Codex CLI case. The user opts out via `--no-reap` in
        // the Codex config's `args` list.
        let serve = try CLIImpl.Command.Serve.parse(["--no-reap"])
        #expect(serve.noReap == true)
    }
}
