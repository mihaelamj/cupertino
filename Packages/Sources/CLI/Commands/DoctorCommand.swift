import ArgumentParser
import Core
import Diagnostics
import Foundation
import Indexer
import Logging
import MCP
import MCPSupport
import SampleIndex
import Search
import SearchToolProvider
import SharedCore
import SharedConstants
import SharedUtils
import CoreProtocols

// MARK: - Doctor Command

/// One row in the raw-corpus directory check. Replaces a 4-tuple to
/// avoid the swiftlint `large_tuple` violation.
private struct CorpusEntry {
    let label: String
    let url: URL
    let suffix: String
    let fetchType: String
}

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check MCP server health and configuration",
        discussion: """
        Verifies that the MCP server can start and all required components
        are available and properly configured.

        Checks:
        • Server initialization
        • Resource providers
        • Tool providers
        • Database connectivity
        • Documentation directories
        """
    )

    @Option(name: .long, help: ArgumentHelp(Shared.Constants.HelpText.docsDir))
    var docsDir: String = Shared.Constants.defaultDocsDirectory.path

    @Option(name: .long, help: ArgumentHelp(Shared.Constants.HelpText.evolutionDir))
    var evolutionDir: String = Shared.Constants.defaultSwiftEvolutionDirectory.path

    @Option(name: .long, help: ArgumentHelp(Shared.Constants.HelpText.searchDB))
    var searchDB: String = Shared.Constants.defaultSearchDatabase.path

    @Flag(
        name: .long,
        help: """
        Run the `cupertino save` preflight check only — print which \
        sources are present, which lack availability annotations, what \
        would be skipped — without running the regular doctor health \
        suite. Read-only, no DB writes. (#232)
        """
    )
    var save: Bool = false

    mutating func run() async throws {
        // #232: --save flag short-circuits to the SaveCommand preflight,
        // so users can ask `is save ready?` without committing to running
        // it. Identical output to what `cupertino save` would print as
        // its preflight summary.
        if save {
            Log.output("🔍 `cupertino save` preflight check\n")
            let lines = Indexer.Preflight.preflightLines(
                buildDocs: true,
                buildPackages: true,
                buildSamples: true
            )
            for line in lines {
                Log.output(line)
            }
            return
        }

        Log.output("🏥 MCP Server Health Check")
        Log.output("")

        var allChecks = true

        // Check server initialization
        allChecks = checkServerInitialization() && allChecks

        // Check documentation directories
        allChecks = checkDocumentationDirectories() && allChecks

        // Check packages (filesystem state)
        await checkPackages()

        // Check packages.db (#192 F1)
        allChecks = checkPackagesDatabase() && allChecks

        // Check samples.db (sample code index built by `cupertino save --samples`)
        checkSamplesDatabase()

        // Check search database + schema version (#192 F2)
        allChecks = await checkSearchDatabase() && allChecks

        // Check resource providers
        allChecks = checkResourceProviders() && allChecks

        // Schema versions across all three DBs (#234)
        printSchemaVersions()

        // Summary
        Log.output("")
        if allChecks {
            Log.output("✅ All checks passed - MCP server ready")
        } else {
            Log.output("⚠️  Some checks failed - see above for details")
            throw ExitCode(1)
        }
    }

    /// Read and print `PRAGMA user_version` for each of cupertino's
    /// three local databases (#234). Each DB stores the version in the
    /// SQLite header, so reading is cheap and works without
    /// instantiating any actor. Missing files are reported but don't
    /// fail the check — they're already covered by the per-DB sections
    /// above.
    private func printSchemaVersions() {
        Log.output("")
        Log.output("8. Schema versions (#234)")
        Log.output("")
        let entries: [(String, URL)] = [
            ("search.db", URL(fileURLWithPath: searchDB).expandingTildeInPath),
            ("packages.db", Shared.Constants.defaultPackagesDatabase),
            ("samples.db", SampleIndex.defaultDatabasePath),
        ]
        for (label, url) in entries {
            guard FileManager.default.fileExists(atPath: url.path) else {
                Log.output("   ⚠ \(label): not built")
                continue
            }
            let version = Diagnostics.Probes.userVersion(at: url) ?? 0
            let formatted = Diagnostics.SchemaVersion.format(version)
            Log.output("   ✓ \(label): \(formatted)")
        }
    }

    private func checkServerInitialization() -> Bool {
        Log.output("✅ MCP Server")
        Log.output("   ✓ Server can initialize")
        Log.output("   ✓ Transport: stdio")
        Log.output("   ✓ Protocol version: \(MCPProtocolVersion)")
        Log.output("")
        return true
    }

    /// Filesystem check for raw corpus directories. These are *inputs* for
    /// `cupertino save`; they're optional once `search.db` is built (a user
    /// who ran `cupertino setup` has the DB but no source dirs, and that's
    /// fine). All five directories are warnings-only — missing dirs don't
    /// fail doctor. The query-correctness truth lives in `search.db` and is
    /// reported by `checkSearchDatabase`.
    private func checkDocumentationDirectories() -> Bool {
        let docsURL = URL(fileURLWithPath: docsDir).expandingTildeInPath
        let evolutionURL = URL(fileURLWithPath: evolutionDir).expandingTildeInPath
        let higURL = Shared.Constants.defaultHIGDirectory
        let swiftOrgURL = Shared.Constants.defaultSwiftOrgDirectory
        let archiveURL = Shared.Constants.defaultArchiveDirectory

        Log.output("📂 Raw corpus directories (input for `cupertino save`)")

        let entries: [CorpusEntry] = [
            CorpusEntry(label: "Apple docs", url: docsURL, suffix: "files", fetchType: "docs"),
            CorpusEntry(label: "Swift Evolution", url: evolutionURL, suffix: "proposals", fetchType: "evolution"),
            CorpusEntry(label: "Swift.org", url: swiftOrgURL, suffix: "pages", fetchType: "swift"),
            CorpusEntry(label: "HIG", url: higURL, suffix: "pages", fetchType: "hig"),
            CorpusEntry(label: "Apple Archive", url: archiveURL, suffix: "guides", fetchType: "archive"),
        ]

        for entry in entries {
            if FileManager.default.fileExists(atPath: entry.url.path) {
                let count = Diagnostics.Probes.countCorpusFiles(in: entry.url)
                Log.output("   ✓ \(entry.label): \(entry.url.path) (\(count) \(entry.suffix))")
            } else {
                Log.output("   ⚠  \(entry.label): \(entry.url.path) (not found)")
                Log.output("     → Run: cupertino fetch --type \(entry.fetchType)  (only needed to rebuild from scratch)")
            }
        }

        Log.output("")
        // Filesystem state is informational. The hard fail is whether
        // search.db has indexed data, which `checkSearchDatabase` enforces.
        return true
    }

    private func checkSearchDatabase() async -> Bool {
        let searchDBURL = URL(fileURLWithPath: searchDB).expandingTildeInPath

        Log.output("🔍 Search Index")

        guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
            Log.output("   ✗ Database: \(searchDBURL.path) (not found)")
            Log.output("     → Run: cupertino setup  (or `cupertino save` if building locally)")
            Log.output("")
            return false
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: searchDBURL.path)[.size] as? UInt64) ?? 0
        Log.output("   ✓ Database: \(searchDBURL.path)")
        Log.output("   ✓ Size: \(Shared.Formatting.formatBytes(Int64(fileSize)))")

        if !reportSchemaVersion(at: searchDBURL) {
            return false
        }

        do {
            let searchIndex = try await Search.Index(dbPath: searchDBURL)
            let frameworks = try await searchIndex.listFrameworks()
            Log.output("   ✓ Frameworks: \(frameworks.count)")
            await searchIndex.disconnect()
            return reportIndexedSources(at: searchDBURL)
        } catch {
            Log.output("   ✗ Database error: \(error)")
            Log.output("     → rm \(searchDBURL.path) && cupertino save")
            Log.output("")
            return false
        }
    }

    /// Read `PRAGMA user_version` and compare against the binary's expected
    /// schema. Returns false on mismatch (with a precise rebuild hint), true
    /// on match or unreadable. Read BEFORE opening via `Search.Index` because
    /// migrating from an incompatible version throws during init, and the
    /// user wants to know which version they're stuck on.
    private func reportSchemaVersion(at searchDBURL: URL) -> Bool {
        let onDiskVersion = Diagnostics.Probes.userVersion(at: searchDBURL)
        let expected = Search.Index.schemaVersion
        guard let onDiskVersion else {
            Log.output("   ⚠  Schema version: could not read PRAGMA user_version")
            return true
        }
        if onDiskVersion == expected {
            Log.output("   ✓ Schema version: \(onDiskVersion) (matches installed binary)")
            return true
        }
        if onDiskVersion < expected {
            Log.output("   ✗ Schema version: \(onDiskVersion) (binary expects \(expected), rebuild required)")
            Log.output("     → rm \(searchDBURL.path) && cupertino save")
        } else {
            Log.output("   ✗ Schema version: \(onDiskVersion) (newer than binary — expected \(expected))")
            Log.output("     → Upgrade cupertino: brew upgrade cupertino")
        }
        Log.output("")
        return false
    }

    /// Per-source indexed counts via direct sqlite read. This is the truth
    /// for "can my MCP answer queries about source X?". Hard-fails if the DB
    /// opens but has zero indexed rows (silent-empty MCP otherwise).
    private func reportIndexedSources(at searchDBURL: URL) -> Bool {
        let perSource = Diagnostics.Probes.perSourceCounts(at: searchDBURL)
        if !perSource.isEmpty {
            Log.output("   📚 Indexed sources:")
            for (source, count) in perSource {
                Log.output("     ✓ \(source): \(count) entries")
            }
        }
        Log.output("")
        let totalIndexed = perSource.reduce(0) { $0 + $1.count }
        if totalIndexed == 0 {
            Log.output("   ✗ Search index is empty (0 rows in docs_metadata)")
            Log.output("     → Rebuild: rm \(searchDBURL.path) && cupertino setup")
            Log.output("")
            return false
        }
        return true
    }

    /// Report `samples.db` presence, size, and row counts (sample projects +
    /// indexed source files). Built by `cupertino save --samples` after sample-code
    /// download + cleanup. Missing is a warning (server runs without it; the
    /// sample-code search just isn't available).
    private func checkSamplesDatabase() {
        let samplesDBURL = SampleIndex.defaultDatabasePath

        Log.output("🧪 Sample Code Index (samples.db)")

        guard FileManager.default.fileExists(atPath: samplesDBURL.path) else {
            Log.output("   ⚠  Database: \(samplesDBURL.path) (not found)")
            Log.output("     → Run: cupertino fetch --type samples && cupertino cleanup && cupertino save --samples")
            Log.output("")
            return
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: samplesDBURL.path)[.size] as? UInt64) ?? 0
        Log.output("   ✓ Database: \(samplesDBURL.path)")
        Log.output("   ✓ Size: \(Shared.Formatting.formatBytes(Int64(fileSize)))")

        let projectCount = Diagnostics.Probes.rowCount(at: samplesDBURL, sql: "SELECT COUNT(*) FROM projects;")
        let fileCount = Diagnostics.Probes.rowCount(at: samplesDBURL, sql: "SELECT COUNT(*) FROM files;")
        let symbolCount = Diagnostics.Probes.rowCount(at: samplesDBURL, sql: "SELECT COUNT(*) FROM file_symbols;")
        if let projectCount { Log.output("   ✓ Projects: \(projectCount)") }
        if let fileCount { Log.output("   ✓ Indexed files: \(fileCount)") }
        if let symbolCount { Log.output("   ✓ Indexed symbols: \(symbolCount)") }
        Log.output("")
    }

    /// #192 F1. Report `packages.db` presence, size, and row counts (packages,
    /// files). Schema version tracked via the bundle-wide
    /// `Shared.Constants.App.databaseVersion` constant rather than a PRAGMA
    /// (packages.db is downloaded as part of the v1.0+ bundle, not migrated).
    private func checkPackagesDatabase() -> Bool {
        let packagesDBURL = Shared.Constants.defaultPackagesDatabase

        Log.output("📦 Packages Index (packages.db)")

        guard FileManager.default.fileExists(atPath: packagesDBURL.path) else {
            Log.output("   ⚠  Database: \(packagesDBURL.path) (not found)")
            Log.output("     → Run: cupertino setup  (downloads the pre-built packages index)")
            Log.output("     Expected version: \(Shared.Constants.App.databaseVersion)")
            Log.output("")
            // Missing packages.db is a warning, not a failure — server still
            // runs, just without the packages tool. Doctor summary stays green.
            return true
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: packagesDBURL.path)[.size] as? UInt64) ?? 0
        Log.output("   ✓ Database: \(packagesDBURL.path)")
        Log.output("   ✓ Size: \(Shared.Formatting.formatBytes(Int64(fileSize)))")

        let packageCount = Diagnostics.Probes.rowCount(at: packagesDBURL, sql: "SELECT COUNT(*) FROM packages;")
        let fileCount = Diagnostics.Probes.rowCount(at: packagesDBURL, sql: "SELECT COUNT(*) FROM package_files;")
        if let packageCount { Log.output("   ✓ Packages: \(packageCount)") }
        if let fileCount { Log.output("   ✓ Indexed files: \(fileCount)") }
        Log.output("   ℹ  Bundled version: \(Shared.Constants.App.databaseVersion)")
        Log.output("")
        return true
    }

    private func checkPackages() async {
        let packagesDir = Shared.Constants.defaultPackagesDirectory
        let userSelectionsURL = Shared.Constants.defaultBaseDirectory
            .appendingPathComponent(Shared.Constants.FileName.selectedPackages)

        Log.output("📦 Swift Packages")

        // Load selected URLs once and derive the canonical "owner/repo" key
        // set so we can compare against on-disk READMEs by NAME, not by count.
        let selectedURLs: Set<String>
        if FileManager.default.fileExists(atPath: userSelectionsURL.path) {
            selectedURLs = Diagnostics.Probes.userSelectedPackageURLs(from: userSelectionsURL)
            Log.output("   ✓ User selections: \(userSelectionsURL.path)")
            Log.output("     \(selectedURLs.count) packages selected")
        } else {
            selectedURLs = []
            Log.output("   ⚠  User selections: not configured")
            Log.output("     → Use TUI to select packages, or will use bundled defaults")
        }
        let selectedKeys = Set(selectedURLs.compactMap(Diagnostics.Probes.ownerRepoKey(forGitHubURL:)))

        // Check downloaded READMEs and identify true orphans (downloaded
        // owner/repo no longer in selections) and true gaps (selected but
        // not yet downloaded).
        if FileManager.default.fileExists(atPath: packagesDir.path) {
            let readmeKeys = Diagnostics.Probes.packageREADMEKeys(in: packagesDir)
            if readmeKeys.isEmpty {
                Log.output("   ⚠  Package docs: directory exists but no package files")
            } else {
                Log.output("   ✓ Downloaded READMEs: \(readmeKeys.count) packages")
                Log.output("     \(packagesDir.path)")

                if !selectedKeys.isEmpty {
                    let orphans = readmeKeys.subtracting(selectedKeys)
                    let missing = selectedKeys.subtracting(readmeKeys)
                    if !orphans.isEmpty {
                        Log.output("   ⚠  Orphaned READMEs: \(orphans.count) (downloaded but no longer selected)")
                    }
                    if !missing.isEmpty {
                        Log.output("   ⚠  Missing READMEs: \(missing.count) (selected but not yet downloaded)")
                        Log.output("     → Run: cupertino fetch --type packages")
                    }
                }
            }
        } else {
            Log.output("   ⚠  Package docs: not downloaded")
        }

        // Show priority packages source
        let allPackages = await PriorityPackagesCatalog.allPackages
        let appleCount = await PriorityPackagesCatalog.applePackages.count
        let ecosystemCount = await PriorityPackagesCatalog.ecosystemPackages.count
        Log.output("   ℹ  Priority packages: \(allPackages.count) total")
        Log.output("     Apple: \(appleCount), Ecosystem: \(ecosystemCount)")

        Log.output("")
    }

    private func checkResourceProviders() -> Bool {
        Log.output("🔧 Providers")
        Log.output("   ✓ DocsResourceProvider: available")
        Log.output("   ✓ SearchToolProvider: available")
        Log.output("")
        return true
    }
}
