import Foundation
@testable import CLI
import SharedConstants
import Testing

// MARK: - #597 — `--base-dir` must isolate ALL output DB paths
//
// Pre-fix, `cupertino save --base-dir /tmp/x` silently wrote to
// `~/.cupertino/samples.db` (and packages.db, depending on path) because
// the dispatchers hardcoded `Shared.Paths.live().baseDirectory` for the
// output DB locations. During the 2026-05-15 full-coverage sweep this
// destroyed ~180 MB of live samples.db data in 3 min between starting
// the save and noticing.
//
// These tests pin the three path-resolution helpers
// (`resolveSamplesDBPath`, `resolvePackagesDBPath`,
// `resolveSearchDBPath`) so a future regression that reintroduces the
// hardcoded `Shared.Paths.live()` is caught by CI rather than by
// another data-destruction incident.

@Suite("CLIImpl.Command.Save path-resolution helpers (#597 — --base-dir isolation)")
struct SaveBaseDirIsolationTests {
    typealias SUT = CLIImpl.Command.Save

    // MARK: - samples.db

    @Test("samples.db path derives from effectiveBase when no override")
    func samplesDBDerivesFromEffectiveBase() {
        let base = URL(fileURLWithPath: "/tmp/cupertino-iso-\(UUID().uuidString)")
        let resolved = SUT.resolveSamplesDBPath(effectiveBase: base, override: nil)
        // Must be under the given base — NOT under ~/.cupertino.
        #expect(resolved.path.hasPrefix(base.path))
        #expect(!resolved.path.contains(".cupertino/samples.db") || resolved.path.hasPrefix(base.path),
                "samples.db must not leak to ~/.cupertino when effectiveBase is set")
    }

    @Test("samples.db override flag wins over effectiveBase")
    func samplesDBOverrideWins() {
        let base = URL(fileURLWithPath: "/tmp/cupertino-iso-\(UUID().uuidString)")
        let override = "/tmp/custom-samples.db"
        let resolved = SUT.resolveSamplesDBPath(effectiveBase: base, override: override)
        #expect(resolved.path == override)
    }

    @Test("samples.db override expands ~ prefix")
    func samplesDBOverrideExpandsTilde() {
        let base = URL(fileURLWithPath: "/tmp/cupertino-iso")
        let resolved = SUT.resolveSamplesDBPath(effectiveBase: base, override: "~/my-samples.db")
        // ~ must have expanded to the real home, not stayed literal.
        #expect(!resolved.path.hasPrefix("~"))
        #expect(resolved.path.hasSuffix("/my-samples.db"))
    }

    // MARK: - packages.db

    @Test("packages.db path derives from effectiveBase when no override")
    func packagesDBDerivesFromEffectiveBase() {
        let base = URL(fileURLWithPath: "/tmp/cupertino-iso-\(UUID().uuidString)")
        let resolved = SUT.resolvePackagesDBPath(effectiveBase: base, override: nil)
        #expect(resolved.path.hasPrefix(base.path))
        #expect(resolved.lastPathComponent == Shared.Constants.FileName.packagesIndexDatabase)
    }

    @Test("packages.db override wins")
    func packagesDBOverrideWins() {
        let base = URL(fileURLWithPath: "/tmp/cupertino-iso")
        let override = "/tmp/custom-packages.db"
        let resolved = SUT.resolvePackagesDBPath(effectiveBase: base, override: override)
        #expect(resolved.path == override)
    }

    // MARK: - search.db (already correct pre-fix; pin the shape)

    @Test("search.db path derives from effectiveBase when no override")
    func searchDBDerivesFromEffectiveBase() {
        let base = URL(fileURLWithPath: "/tmp/cupertino-iso-\(UUID().uuidString)")
        let resolved = SUT.resolveSearchDBPath(effectiveBase: base, override: nil)
        #expect(resolved.path.hasPrefix(base.path))
        #expect(resolved.lastPathComponent == Shared.Constants.FileName.searchDatabase)
    }

    @Test("search.db override wins")
    func searchDBOverrideWins() {
        let base = URL(fileURLWithPath: "/tmp/cupertino-iso")
        let override = "/tmp/custom-search.db"
        let resolved = SUT.resolveSearchDBPath(effectiveBase: base, override: override)
        #expect(resolved.path == override)
    }

    // MARK: - Cross-cut: never leak to ~/.cupertino

    @Test("none of the three DB paths leak to ~/.cupertino when effectiveBase is custom")
    func noneLeakToHome() {
        let base = URL(fileURLWithPath: "/var/folders/77/test-base/")
        let samples = SUT.resolveSamplesDBPath(effectiveBase: base, override: nil).path
        let packages = SUT.resolvePackagesDBPath(effectiveBase: base, override: nil).path
        let search = SUT.resolveSearchDBPath(effectiveBase: base, override: nil).path

        // Real home — what the bug accidentally wrote to.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let liveCupertino = "\(home)/.cupertino"

        for path in [samples, packages, search] {
            #expect(!path.hasPrefix(liveCupertino),
                    "DB path \(path) leaked to ~/.cupertino despite effectiveBase=\(base.path)")
        }
    }
}
