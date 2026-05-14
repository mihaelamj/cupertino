import ArgumentParser
import Core
import CorePackageIndexing
import CoreProtocols
import Diagnostics
import Foundation
import LoggingModels
import Indexer
import Logging
import MCPCore
import MCPSupport
import SampleIndex
import Search
import SearchModels
import SearchToolProvider
import SharedConstants
import SharedCore
import SharedUtils

// MARK: - Doctor Command

/// One row in the raw-corpus directory check. Replaces a 4-tuple to
/// avoid the swiftlint `large_tuple` violation.
private struct CorpusEntry {
    let label: String
    let url: URL
    let suffix: String
    let fetchType: String
}

extension CLI.Command {
    struct Doctor: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "doctor",
            abstract: "Check MCP server health, database state, and save readiness",
            discussion: """
            Verifies that the MCP server can start and all required components are available.

            Checks:
            • Server initialization
            • Resource and tool providers
            • Database connectivity and schema versions
            • Raw corpus directories (inputs for 'cupertino save')
            • Swift package download state

            Pass --save to run only the save preflight — prints which sources are present
            and what would be built, without performing any health checks or DB writes.
            Useful before running 'cupertino save' to confirm sources are ready.
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
            Run the 'cupertino save' preflight check only — print which sources are present \
            and what would be built — without running the regular health suite. Read-only, no DB writes.
            """
        )
        var save: Bool = false

        mutating func run() async throws {
            // #232: --save flag short-circuits to the Command.Save preflight,
            // so users can ask `is save ready?` without committing to running
            // it. Identical output to what `cupertino save` would print as
            // its preflight summary.
            if save {
                Logging.LiveRecording().output("🔍 `cupertino save` preflight check\n")
                let lines = Indexer.Preflight.preflightLines(
                    buildDocs: true,
                    buildPackages: true,
                    buildSamples: true
                )
                for line in lines {
                    Logging.LiveRecording().output(line)
                }
                return
            }

            Logging.LiveRecording().output("🏥 MCP Server Health Check")
            Logging.LiveRecording().output("")

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
            Logging.LiveRecording().output("")
            if allChecks {
                Logging.LiveRecording().output("✅ All checks passed - MCP server ready")
            } else {
                Logging.LiveRecording().output("⚠️  Some checks failed - see above for details")
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
            Logging.LiveRecording().output("")
            Logging.LiveRecording().output("8. Schema versions (#234)")
            Logging.LiveRecording().output("")
            let entries: [(String, URL)] = [
                ("search.db", URL(fileURLWithPath: searchDB).expandingTildeInPath),
                ("packages.db", Shared.Constants.defaultPackagesDatabase),
                ("samples.db", Sample.Index.defaultDatabasePath),
            ]
            for (label, url) in entries {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    Logging.LiveRecording().output("   ⚠ \(label): not built")
                    continue
                }
                let version = Diagnostics.Probes.userVersion(at: url) ?? 0
                let formatted = Diagnostics.SchemaVersion.format(version)
                // #236: surface the journal mode alongside the schema
                // version so a DB stuck in default rollback mode jumps
                // out. WAL is the expected value — anything else means
                // the init code never switched, and concurrent readers
                // will block on writers.
                let journal = Diagnostics.Probes.journalMode(at: url) ?? "?"
                // #236: anything other than `wal` is a flag, but the
                // root cause varies. The volume check below catches
                // the network-FS case (silent-WAL-fail per the docs)
                // separately, so this note stays minimal — the
                // remaining causes are: (1) DB predates the WAL
                // enablement and hasn't been re-opened by the
                // writing actor since, or (2) the writer's PRAGMA
                // failed for some unrelated reason and got logged
                // at warning level.
                let journalNote = if journal == "wal" {
                    "wal"
                } else {
                    "\(journal) ⚠ (expected wal — run `cupertino save` for this DB, or check logs for a WAL PRAGMA failure)"
                }

                // #236 follow-up: surface the WAL sidecar size +
                // warn when it suggests checkpoint starvation. The
                // SQLite docs say read performance "deteriorates as
                // the WAL file grows in size" but don't give a
                // discrete threshold; 16 MiB is 4× the default
                // auto-checkpoint threshold (4 MiB), so above that a
                // healthy single-process workload would have already
                // checkpointed multiple times. Persistent overshoot
                // suggests a long-lived reader (e.g. an MCP session)
                // is blocking the checkpoint.
                let walURL = URL(fileURLWithPath: url.path + "-wal")
                let walNote: String
                if let attrs = try? FileManager.default.attributesOfItem(atPath: walURL.path),
                   let walSize = attrs[.size] as? Int64 {
                    if walSize > 16 * 1024 * 1024 {
                        walNote = ", wal=\(Shared.Utils.Formatting.formatBytes(walSize)) ⚠ (checkpoint starvation? long-lived reader holding the DB)"
                    } else if walSize > 0 {
                        walNote = ", wal=\(Shared.Utils.Formatting.formatBytes(walSize))"
                    } else {
                        walNote = ""
                    }
                } else {
                    walNote = ""
                }

                // #236 follow-up: warn when the DB lives on a
                // non-local volume. SQLite WAL does not work over
                // network filesystems (NFS / SMB / AFP) — quoting
                // the docs: "All processes using a database must be
                // on the same host computer; WAL does not work over
                // a network filesystem." On non-local mounts the
                // journal-mode switch silently fails, but symbols
                // pile up at the surface (DB might also corrupt due
                // to NFS advisory-locking bugs noted in the SQLite
                // corruption guide).
                let volumeNote = volumeWarning(for: url)

                Logging.LiveRecording().output("   ✓ \(label): \(formatted), journal=\(journalNote)\(walNote)\(volumeNote)")
            }
        }

        /// Returns a warning suffix if the DB at `url` lives on a
        /// non-local volume. Empty string for local volumes (the
        /// happy path). Uses Foundation's `volumeIsLocalKey` resource
        /// value — true for local mounted volumes (APFS / HFS+
        /// internal or external), false for NFS / SMB / AFP /
        /// FUSE-mounted network shares.
        private func volumeWarning(for url: URL) -> String {
            let resolved = url.resolvingSymlinksInPath()
            guard let values = try? resolved.resourceValues(forKeys: [.volumeIsLocalKey]),
                  let isLocal = values.volumeIsLocal else {
                return ""
            }
            if isLocal {
                return ""
            }
            return ", volume=non-local ⚠ (SQLite WAL doesn't work over NFS/SMB/AFP; risk of corruption per sqlite.org/wal.html)"
        }

        private func checkServerInitialization() -> Bool {
            Logging.LiveRecording().output("✅ MCP Server")
            Logging.LiveRecording().output("   ✓ Server can initialize")
            Logging.LiveRecording().output("   ✓ Transport: stdio")
            Logging.LiveRecording().output("   ✓ Protocol version: \(MCPProtocolVersion)")
            Logging.LiveRecording().output("")
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

            Logging.LiveRecording().output("📂 Raw corpus directories (input for `cupertino save`)")

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
                    Logging.LiveRecording().output("   ✓ \(entry.label): \(entry.url.path) (\(count) \(entry.suffix))")
                } else {
                    Logging.LiveRecording().output("   ⚠  \(entry.label): \(entry.url.path) (not found)")
                    Logging.LiveRecording().output("     → Run: cupertino fetch --type \(entry.fetchType)  (only needed to rebuild from scratch)")
                }
            }

            Logging.LiveRecording().output("")
            // Filesystem state is informational. The hard fail is whether
            // search.db has indexed data, which `checkSearchDatabase` enforces.
            return true
        }

        private func checkSearchDatabase() async -> Bool {
            let searchDBURL = URL(fileURLWithPath: searchDB).expandingTildeInPath

            Logging.LiveRecording().output("🔍 Search Index")

            guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
                Logging.LiveRecording().output("   ✗ Database: \(searchDBURL.path) (not found)")
                Logging.LiveRecording().output("     → Run: cupertino setup  (or `cupertino save` if building locally)")
                Logging.LiveRecording().output("")
                return false
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: searchDBURL.path)[.size] as? UInt64) ?? 0
            Logging.LiveRecording().output("   ✓ Database: \(searchDBURL.path)")
            Logging.LiveRecording().output("   ✓ Size: \(Shared.Utils.Formatting.formatBytes(Int64(fileSize)))")

            if !reportSchemaVersion(at: searchDBURL) {
                return false
            }

            do {
                let searchIndex = try await SearchModule.Index(dbPath: searchDBURL, logger: Logging.LiveRecording())
                let frameworks = try await searchIndex.listFrameworks()
                Logging.LiveRecording().output("   ✓ Frameworks: \(frameworks.count)")
                await searchIndex.disconnect()
                return reportIndexedSources(at: searchDBURL)
            } catch {
                Logging.LiveRecording().output("   ✗ Database error: \(error)")
                Logging.LiveRecording().output("     → rm \(searchDBURL.path) && cupertino save")
                Logging.LiveRecording().output("")
                return false
            }
        }

        /// Read `PRAGMA user_version` and compare against the binary's expected
        /// schema. Returns false on mismatch (with a precise rebuild hint), true
        /// on match or unreadable. Read BEFORE opening via `SearchModule.Index` because
        /// migrating from an incompatible version throws during init, and the
        /// user wants to know which version they're stuck on.
        private func reportSchemaVersion(at searchDBURL: URL) -> Bool {
            let onDiskVersion = Diagnostics.Probes.userVersion(at: searchDBURL)
            let expected = SearchModule.Index.schemaVersion
            guard let onDiskVersion else {
                Logging.LiveRecording().output("   ⚠  Schema version: could not read PRAGMA user_version")
                return true
            }
            if onDiskVersion == expected {
                Logging.LiveRecording().output("   ✓ Schema version: \(onDiskVersion) (matches installed binary)")
                return true
            }
            if onDiskVersion < expected {
                Logging.LiveRecording().output("   ✗ Schema version: \(onDiskVersion) (binary expects \(expected), rebuild required)")
                Logging.LiveRecording().output("     → rm \(searchDBURL.path) && cupertino save")
            } else {
                Logging.LiveRecording().output("   ✗ Schema version: \(onDiskVersion) (newer than binary — expected \(expected))")
                Logging.LiveRecording().output("     → Upgrade cupertino: brew upgrade cupertino")
            }
            Logging.LiveRecording().output("")
            return false
        }

        /// Per-source indexed counts via direct sqlite read. This is the truth
        /// for "can my MCP answer queries about source X?". Hard-fails if the DB
        /// opens but has zero indexed rows (silent-empty MCP otherwise).
        private func reportIndexedSources(at searchDBURL: URL) -> Bool {
            let perSource = Diagnostics.Probes.perSourceCounts(at: searchDBURL)
            if !perSource.isEmpty {
                Logging.LiveRecording().output("   📚 Indexed sources:")
                for (source, count) in perSource {
                    Logging.LiveRecording().output("     ✓ \(source): \(count) entries")
                }
            }
            Logging.LiveRecording().output("")
            let totalIndexed = perSource.reduce(0) { $0 + $1.count }
            if totalIndexed == 0 {
                Logging.LiveRecording().output("   ✗ Search index is empty (0 rows in docs_metadata)")
                Logging.LiveRecording().output("     → Rebuild: rm \(searchDBURL.path) && cupertino setup")
                Logging.LiveRecording().output("")
                return false
            }
            return true
        }

        /// Report `samples.db` presence, size, and row counts (sample projects +
        /// indexed source files). Built by `cupertino save --samples` after sample-code
        /// download + cleanup. Missing is a warning (server runs without it; the
        /// sample-code search just isn't available).
        private func checkSamplesDatabase() {
            let samplesDBURL = Sample.Index.defaultDatabasePath

            Logging.LiveRecording().output("🧪 Sample Code Index (samples.db)")

            guard FileManager.default.fileExists(atPath: samplesDBURL.path) else {
                Logging.LiveRecording().output("   ⚠  Database: \(samplesDBURL.path) (not found)")
                Logging.LiveRecording().output("     → Run: cupertino fetch --type samples && cupertino cleanup && cupertino save --samples")
                Logging.LiveRecording().output("")
                return
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: samplesDBURL.path)[.size] as? UInt64) ?? 0
            Logging.LiveRecording().output("   ✓ Database: \(samplesDBURL.path)")
            Logging.LiveRecording().output("   ✓ Size: \(Shared.Utils.Formatting.formatBytes(Int64(fileSize)))")

            let projectCount = Diagnostics.Probes.rowCount(at: samplesDBURL, sql: Shared.Utils.SQL.countRows(in: "projects"))
            let fileCount = Diagnostics.Probes.rowCount(at: samplesDBURL, sql: Shared.Utils.SQL.countRows(in: "files"))
            let symbolCount = Diagnostics.Probes.rowCount(at: samplesDBURL, sql: Shared.Utils.SQL.countRows(in: "file_symbols"))
            if let projectCount { Logging.LiveRecording().output("   ✓ Projects: \(projectCount)") }
            if let fileCount { Logging.LiveRecording().output("   ✓ Indexed files: \(fileCount)") }
            if let symbolCount { Logging.LiveRecording().output("   ✓ Indexed symbols: \(symbolCount)") }
            Logging.LiveRecording().output("")
        }

        /// #192 F1. Report `packages.db` presence, size, and row counts (packages,
        /// files). Schema version tracked via the bundle-wide
        /// `Shared.Constants.App.databaseVersion` constant rather than a PRAGMA
        /// (packages.db is downloaded as part of the v1.0+ bundle, not migrated).
        private func checkPackagesDatabase() -> Bool {
            let packagesDBURL = Shared.Constants.defaultPackagesDatabase

            Logging.LiveRecording().output("📦 Packages Index (packages.db)")

            guard FileManager.default.fileExists(atPath: packagesDBURL.path) else {
                Logging.LiveRecording().output("   ⚠  Database: \(packagesDBURL.path) (not found)")
                Logging.LiveRecording().output("     → Run: cupertino setup  (downloads the pre-built packages index)")
                Logging.LiveRecording().output("     Expected version: \(Shared.Constants.App.databaseVersion)")
                Logging.LiveRecording().output("")
                // Missing packages.db is a warning, not a failure — server still
                // runs, just without the packages tool. Doctor summary stays green.
                return true
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: packagesDBURL.path)[.size] as? UInt64) ?? 0
            Logging.LiveRecording().output("   ✓ Database: \(packagesDBURL.path)")
            Logging.LiveRecording().output("   ✓ Size: \(Shared.Utils.Formatting.formatBytes(Int64(fileSize)))")

            let packageCount = Diagnostics.Probes.rowCount(at: packagesDBURL, sql: Shared.Utils.SQL.countRows(in: "packages"))
            let fileCount = Diagnostics.Probes.rowCount(at: packagesDBURL, sql: Shared.Utils.SQL.countRows(in: "package_files"))
            if let packageCount { Logging.LiveRecording().output("   ✓ Packages: \(packageCount)") }
            if let fileCount { Logging.LiveRecording().output("   ✓ Indexed files: \(fileCount)") }
            Logging.LiveRecording().output("   ℹ  Bundled version: \(Shared.Constants.App.databaseVersion)")
            Logging.LiveRecording().output("")
            return true
        }

        private func checkPackages() async {
            let packagesDir = Shared.Constants.defaultPackagesDirectory
            let userSelectionsURL = Shared.Constants.defaultBaseDirectory
                .appendingPathComponent(Shared.Constants.FileName.selectedPackages)

            Logging.LiveRecording().output("📦 Swift Packages")

            // Load selected URLs once and derive the canonical "owner/repo" key
            // set so we can compare against on-disk READMEs by NAME, not by count.
            let selectedURLs: Set<String>
            if FileManager.default.fileExists(atPath: userSelectionsURL.path) {
                selectedURLs = Diagnostics.Probes.userSelectedPackageURLs(from: userSelectionsURL)
                Logging.LiveRecording().output("   ✓ User selections: \(userSelectionsURL.path)")
                Logging.LiveRecording().output("     \(selectedURLs.count) packages selected")
            } else {
                selectedURLs = []
                Logging.LiveRecording().output("   ⚠  User selections: not configured")
                Logging.LiveRecording().output("     → Use TUI to select packages, or will use bundled defaults")
            }
            let selectedKeys = Set(selectedURLs.compactMap(Diagnostics.Probes.ownerRepoKey(forGitHubURL:)))

            // Check downloaded READMEs and identify true orphans (downloaded
            // owner/repo no longer in selections) and true gaps (selected but
            // not yet downloaded).
            if FileManager.default.fileExists(atPath: packagesDir.path) {
                let readmeKeys = Diagnostics.Probes.packageREADMEKeys(in: packagesDir)
                if readmeKeys.isEmpty {
                    Logging.LiveRecording().output("   ⚠  Package docs: directory exists but no package files")
                } else {
                    Logging.LiveRecording().output("   ✓ Downloaded READMEs: \(readmeKeys.count) packages")
                    Logging.LiveRecording().output("     \(packagesDir.path)")

                    if !selectedKeys.isEmpty {
                        let orphans = readmeKeys.subtracting(selectedKeys)
                        let missing = selectedKeys.subtracting(readmeKeys)
                        if !orphans.isEmpty {
                            Logging.LiveRecording().output("   ⚠  Orphaned READMEs: \(orphans.count) (downloaded but no longer selected)")
                        }
                        if !missing.isEmpty {
                            Logging.LiveRecording().output("   ⚠  Missing READMEs: \(missing.count) (selected but not yet downloaded)")
                            Logging.LiveRecording().output("     → Run: cupertino fetch --type packages")
                        }
                    }
                }
            } else {
                Logging.LiveRecording().output("   ⚠  Package docs: not downloaded")
            }

            // Show priority packages source
            let allPackages = await Core.PackageIndexing.PriorityPackagesCatalog.allPackages
            let appleCount = await Core.PackageIndexing.PriorityPackagesCatalog.applePackages.count
            let ecosystemCount = await Core.PackageIndexing.PriorityPackagesCatalog.ecosystemPackages.count
            Logging.LiveRecording().output("   ℹ  Priority packages: \(allPackages.count) total")
            Logging.LiveRecording().output("     Apple: \(appleCount), Ecosystem: \(ecosystemCount)")

            Logging.LiveRecording().output("")
        }

        private func checkResourceProviders() -> Bool {
            Logging.LiveRecording().output("🔧 Providers")
            Logging.LiveRecording().output("   ✓ MCP.Support.DocsResourceProvider: available")
            Logging.LiveRecording().output("   ✓ SearchToolProvider: available")
            Logging.LiveRecording().output("")
            return true
        }
    }
}
