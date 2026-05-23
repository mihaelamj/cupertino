import Foundation
import SharedConstants
import Testing

// MARK: - #919 coverage pins: package-audit invariants

@Suite("#919 coverage: package-audit invariants pinned by tests")
struct Issue919AuditInvariantTests {
    // The two audit scripts live in `scripts/` at the repo root, four
    // directory levels up from this test bundle's working directory
    // when run via `xcrun swift test`. The harness below walks
    // upward from the test bundle path to find the repo root so a
    // future move (Tests/ becomes nested) doesn't break the fixture.

    private static func repoRoot() -> URL {
        // FileManager's working directory when `swift test` runs is the
        // Packages/ root. The repo root is one level above that.
        let cwd = FileManager.default.currentDirectoryPath
        var url = URL(fileURLWithPath: cwd)
        // Walk up looking for the scripts/ directory.
        for _ in 0..<4 {
            let scripts = url.appendingPathComponent("scripts")
            if FileManager.default.fileExists(atPath: scripts.path) {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: cwd) // best-effort fallback
    }

    @Test("check-package-purity.sh GRANDFATHERED_TARGETS array is empty")
    func grandfatheredTargetsArrayIsEmpty() throws {
        let scriptURL = Self.repoRoot().appendingPathComponent("scripts/check-package-purity.sh")
        let body = try String(contentsOf: scriptURL, encoding: .utf8)
        // Pin the literal post-#919-arc state: 0 grandfather entries.
        // A future PR that adds a grandfather entry must update this
        // assertion AND the GRANDFATHERED_TARGETS array in lockstep,
        // surfacing the architectural regression explicitly.
        let lines = body.components(separatedBy: .newlines)
        guard let arrayDecl = lines.first(where: { $0.hasPrefix("GRANDFATHERED_TARGETS=") }) else {
            Issue.record("GRANDFATHERED_TARGETS array declaration not found in script")
            return
        }
        // The post-#919 array literal is empty: `GRANDFATHERED_TARGETS=()`.
        #expect(arrayDecl.trimmingCharacters(in: .whitespaces) == "GRANDFATHERED_TARGETS=()")
    }

    @Test("check-target-foundation-only.sh STRICT_PRODUCERS contains exactly 41 entries (post-#906 sub-PR B AppleConstraintsPass extract)")
    func strictProducersHasExpectedCount() throws {
        let scriptURL = Self.repoRoot().appendingPathComponent("scripts/check-target-foundation-only.sh")
        let body = try String(contentsOf: scriptURL, encoding: .utf8)
        // Walk the script line-by-line to locate the STRICT_PRODUCERS=(
        // declaration and its matching closing line (a line whose
        // trimmed content is exactly `)`). Inline `)` characters inside
        // commented-out parenthetical phrases (e.g. `(#536)`) would
        // confuse a substring-based parser; line-mode parsing avoids
        // that. Count every line inside the bounds that looks like a
        // bash identifier (target name).
        let lines = body.components(separatedBy: .newlines)
        guard let openIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "STRICT_PRODUCERS=(" }) else {
            Issue.record("STRICT_PRODUCERS=( opening line not found in script")
            return
        }
        guard let closeOffset = lines[(openIdx + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == ")" }) else {
            Issue.record("STRICT_PRODUCERS closing `)` line not found")
            return
        }
        let arrayLines = lines[(openIdx + 1)..<closeOffset]
        let entries = arrayLines
            .map { $0.split(separator: "#").first ?? "" } // strip inline comments
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { $0.first.map { $0.isLetter || $0 == "_" } ?? false } // identifier-shaped
        // Post-#906 sub-PR E: 44 producers strict.
        // - #899 sub-PR G closed the 6-of-6 strategy split (net +5).
        // - #906 sub-PR B extracts AppleConstraintsPass (+1).
        // - #906 sub-PR C extracts HierarchyPass (+1).
        // - #906 sub-PR D extracts PackagesAppleConstraintsPass (+1).
        // - #906 sub-PR E extracts PackagesAppleImportsPass (+1).
        #expect(entries.count == 44, "expected 44 strict producers, found \(entries.count): \(entries)")
    }

    @Test("FORBIDDEN_MODULES list contains every concrete + the two *SQLite siblings")
    func forbiddenModulesCoversArc() throws {
        let scriptURL = Self.repoRoot().appendingPathComponent("scripts/check-package-purity.sh")
        let body = try String(contentsOf: scriptURL, encoding: .utf8)
        // Pin the FORBIDDEN_MODULES set so today's two SQLite concretes
        // (SearchSQLite + SampleIndexSQLite) stay on the forbidden list:
        // they're concrete data layers; only composition roots may
        // import them.
        let mustContain: [String] = [
            "Search",
            "SearchSQLite",
            "SampleIndex",
            "SampleIndexSQLite",
            "Enrichment",
        ]
        for module in mustContain {
            #expect(
                body.contains("\n    \(module)\n"),
                "FORBIDDEN_MODULES should contain \(module)"
            )
        }
    }
}
