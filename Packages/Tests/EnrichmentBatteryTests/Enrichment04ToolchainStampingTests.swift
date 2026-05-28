import Foundation
import Testing

// Enrichment #4 — Toolchain Stamping.
//
// Two Swift-version stamps:
//   - implementation_swift_version on docs_metadata (swift-evolution: the
//     toolchain a proposal shipped in; swift-book: the language version a
//     chapter targets, sparse by design per #1103).
//   - swift_tools_version on package_metadata (the // swift-tools-version
//     of each package's Package.swift).
//
// This is stored metadata with no `cupertino search` filter surface (the
// search pipeline does not filter or project the toolchain stamp), so the
// battery is DB-probe only.

@Suite("Enrichment #4 — Toolchain Stamping (real DBs)", .enabled(if: LocalDBs.anyAvailable))
struct Enrichment04ToolchainStampingTests {
    private func wellFormedVersion(_ version: String) -> Bool {
        let parts = version.split(separator: ".")
        return !parts.isEmpty && parts.allSatisfy { Int($0) != nil }
    }

    @Test("swift-evolution stamps implementation_swift_version on most proposals")
    func evolutionImplementationVersion() {
        guard LocalDBs.available(LocalDBs.swiftEvolution), let probe = DBProbe(LocalDBs.swiftEvolution) else { return }
        let total = probe.count("SELECT count(*) FROM docs_metadata")
        let stamped = probe.count("SELECT count(*) FROM docs_metadata WHERE implementation_swift_version IS NOT NULL")
        #expect(total > 0)
        #expect(stamped > total / 2, "expected majority of proposals stamped, got \(stamped)/\(total)")
        // Every stamped value is a well-formed version.
        let bad = probe.column(
            "SELECT DISTINCT implementation_swift_version FROM docs_metadata WHERE implementation_swift_version IS NOT NULL"
        ).filter { !wellFormedVersion($0) }
        #expect(bad.isEmpty, "malformed evolution swift versions: \(bad)")
    }

    @Test("swift-book stamps implementation_swift_version on at least the version-specific chapters")
    func swiftBookImplementationVersion() {
        guard LocalDBs.available(LocalDBs.swiftBook), let probe = DBProbe(LocalDBs.swiftBook) else { return }
        // Sparse by design: only chapters that introduce a versioned feature
        // (concurrency 5.5, macros 5.9) carry a stamp.
        let stamped = probe.count("SELECT count(*) FROM docs_metadata WHERE implementation_swift_version IS NOT NULL")
        #expect(stamped >= 1, "expected at least one stamped swift-book chapter, got \(stamped)")
    }

    @Test("packages stamp swift_tools_version on essentially every package")
    func packagesSwiftToolsVersion() {
        guard LocalDBs.packagesAvailable, let probe = DBProbe(LocalDBs.packages) else { return }
        let total = probe.count("SELECT count(*) FROM package_metadata")
        let stamped = probe.count("SELECT count(*) FROM package_metadata WHERE swift_tools_version IS NOT NULL")
        #expect(total > 0)
        #expect(stamped > total - 5, "expected nearly all packages stamped, got \(stamped)/\(total)")
        let bad = probe.column(
            "SELECT DISTINCT swift_tools_version FROM package_metadata WHERE swift_tools_version IS NOT NULL"
        ).filter { !wellFormedVersion($0) }
        #expect(bad.isEmpty, "malformed swift_tools_version values: \(bad)")
    }
}
