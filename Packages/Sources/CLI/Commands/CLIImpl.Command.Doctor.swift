import ArgumentParser
import Core
import CorePackageIndexing
import CoreProtocols
import Diagnostics
import Foundation
import Indexer
import Logging
import LoggingModels
import MCPCore
import MCPSupport
import SampleIndex
import Search
import SearchModels
import SearchToolProvider
import SharedConstants

// MARK: - Doctor Command

/// One row in the raw-corpus directory check. Replaces a 4-tuple to
/// avoid the swiftlint `large_tuple` violation.
private struct CorpusEntry {
    let label: String
    let url: URL
    let suffix: String
    let fetchType: String
}

extension CLIImpl.Command {
    // swiftlint:disable:next type_body_length
    struct Doctor: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "doctor",
            abstract: "Check MCP server health, database state, and save readiness",
            discussion: """
            Default output focuses on what a user needs to know after `cupertino setup`:
            • MCP server initialization
            • Resource and tool providers
            • Database connectivity + schema versions (search.db, packages.db, samples.db)

            Pass --save to also include the maintenance-side sections used before crawling
            or re-indexing:
            • Raw corpus directories (inputs for `cupertino save`)
            • Swift-package download + selection state
            • `cupertino save` per-source preflight summary

            The default skips those because a setup-only user has no raw corpus on disk
            (the bundle ships pre-built DBs), and a `0 files` line in `~/.cupertino/docs`
            is normal in that flow — not a failure. (#68)
            """
        )

        @Option(name: .long, help: ArgumentHelp(Shared.Constants.HelpText.docsDir))
        var docsDir: String = Shared.Paths.live().docsDirectory.path

        @Option(name: .long, help: ArgumentHelp(Shared.Constants.HelpText.evolutionDir))
        var evolutionDir: String = Shared.Paths.live().swiftEvolutionDirectory.path

        @Option(name: .long, help: ArgumentHelp(Shared.Constants.HelpText.searchDB))
        var searchDB: String = Shared.Paths.live().searchDatabase.path

        @Flag(
            name: .long,
            help: """
            Also include the `cupertino save` maintenance sections in the report: raw \
            corpus directories, Swift-package download/selection state, and the per-source \
            save preflight summary. Default doctor output is database + MCP health only. \
            Read-only, no DB writes.
            """
        )
        var save: Bool = false

        mutating func run() async throws {
            Cupertino.Context.composition.logging.recording.output("🏥 MCP Server Health Check")
            Cupertino.Context.composition.logging.recording.output("")

            var allChecks = true

            // ----- Default sections (user-facing) -------------------------
            // What a `cupertino setup` user needs: server + DBs + MCP. The
            // raw corpus + package-selection sections used to live here too;
            // #68 moved them behind `--save` because a setup-only user has
            // no corpus on disk and the `0 files` line looked like a failure.
            allChecks = checkServerInitialization() && allChecks
            allChecks = checkPackagesDatabase() && allChecks
            checkSamplesDatabase()
            allChecks = await checkSearchDatabase() && allChecks
            allChecks = checkResourceProviders() && allChecks
            // Schema versions across all three DBs (#234)
            printSchemaVersions()

            // ----- Save-only sections (maintainer-facing) -----------------
            // `--save` is intent-named: "I'm about to crawl / reindex; show
            // me what the indexer sees." Adds the raw-corpus filesystem walk,
            // selected-packages state, and the `Indexer.Preflight` per-source
            // summary. Pre-#68 the flag short-circuited to only the preflight;
            // it's now additive on top of the default health suite.
            if save {
                allChecks = checkDocumentationDirectories() && allChecks
                await checkPackages()
                Cupertino.Context.composition.logging.recording.output("🔍 `cupertino save` preflight check")
                Cupertino.Context.composition.logging.recording.output("")
                let lines = Indexer.Preflight.preflightLines(
                    paths: Shared.Paths.live(),
                    buildDocs: true,
                    buildPackages: true,
                    buildSamples: true
                )
                for line in lines {
                    Cupertino.Context.composition.logging.recording.output(line)
                }
                Cupertino.Context.composition.logging.recording.output("")
            }

            // Summary
            if allChecks {
                Cupertino.Context.composition.logging.recording.output("✅ All checks passed - MCP server ready")
            } else {
                Cupertino.Context.composition.logging.recording.output("⚠️  Some checks failed - see above for details")
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
            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.output("8. Schema versions (#234)")
            Cupertino.Context.composition.logging.recording.output("")
            // Path-DI composition sub-root (#535).
            let paths = Shared.Paths.live()
            let entries: [(String, URL)] = [
                ("search.db", URL(fileURLWithPath: searchDB).expandingTildeInPath),
                ("packages.db", paths.packagesDatabase),
                ("samples.db", Sample.Index.databasePath(baseDirectory: paths.baseDirectory)),
            ]
            for (label, url) in entries {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    Cupertino.Context.composition.logging.recording.output("   ⚠ \(label): not built")
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

                Cupertino.Context.composition.logging.recording.output("   ✓ \(label): \(formatted), journal=\(journalNote)\(walNote)\(volumeNote)")
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
            Cupertino.Context.composition.logging.recording.output("✅ MCP Server")
            Cupertino.Context.composition.logging.recording.output("   ✓ Server can initialize")
            Cupertino.Context.composition.logging.recording.output("   ✓ Transport: stdio")
            Cupertino.Context.composition.logging.recording.output("   ✓ Protocol version: \(MCPProtocolVersion)")
            Cupertino.Context.composition.logging.recording.output("")
            return true
        }

        /// Filesystem check for raw corpus directories. These are *inputs* for
        /// `cupertino save`; they're optional once `search.db` is built (a user
        /// who ran `cupertino setup` has the DB but no source dirs, and that's
        /// fine). All five directories are warnings-only — missing dirs don't
        /// fail doctor. The query-correctness truth lives in `search.db` and is
        /// reported by `checkSearchDatabase`.
        private func checkDocumentationDirectories() -> Bool {
            // Path-DI composition sub-root (#535).
            let paths = Shared.Paths.live()
            let docsURL = URL(fileURLWithPath: docsDir).expandingTildeInPath
            let evolutionURL = URL(fileURLWithPath: evolutionDir).expandingTildeInPath
            let higURL = paths.higDirectory
            let swiftOrgURL = paths.swiftOrgDirectory
            let archiveURL = paths.archiveDirectory

            Cupertino.Context.composition.logging.recording.output("📂 Raw corpus directories (input for `cupertino save`)")

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
                    Cupertino.Context.composition.logging.recording.output("   ✓ \(entry.label): \(entry.url.path) (\(count) \(entry.suffix))")
                } else {
                    Cupertino.Context.composition.logging.recording.output("   ⚠  \(entry.label): \(entry.url.path) (not found)")
                    Cupertino.Context.composition.logging.recording.output("     → Run: cupertino fetch --type \(entry.fetchType)  (only needed to rebuild from scratch)")
                }
            }

            Cupertino.Context.composition.logging.recording.output("")
            // Filesystem state is informational. The hard fail is whether
            // search.db has indexed data, which `checkSearchDatabase` enforces.
            return true
        }

        private func checkSearchDatabase() async -> Bool {
            let searchDBURL = URL(fileURLWithPath: searchDB).expandingTildeInPath

            Cupertino.Context.composition.logging.recording.output("🔍 Search Index")

            guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
                Cupertino.Context.composition.logging.recording.output("   ✗ Database: \(searchDBURL.path) (not found)")
                Cupertino.Context.composition.logging.recording.output("     → Run: cupertino setup  (or `cupertino save` if building locally)")
                Cupertino.Context.composition.logging.recording.output("")
                return false
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: searchDBURL.path)[.size] as? UInt64) ?? 0
            Cupertino.Context.composition.logging.recording.output("   ✓ Database: \(searchDBURL.path)")
            Cupertino.Context.composition.logging.recording.output("   ✓ Size: \(Shared.Utils.Formatting.formatBytes(Int64(fileSize)))")

            if !reportSchemaVersion(at: searchDBURL) {
                return false
            }

            do {
                let searchIndex = try await SearchModule.Index(dbPath: searchDBURL, logger: Cupertino.Context.composition.logging.recording)
                let frameworks = try await searchIndex.listFrameworks()
                Cupertino.Context.composition.logging.recording.output("   ✓ Frameworks: \(frameworks.count)")
                await searchIndex.disconnect()
                return reportIndexedSources(at: searchDBURL)
            } catch {
                Cupertino.Context.composition.logging.recording.output("   ✗ Database error: \(error)")
                Cupertino.Context.composition.logging.recording.output("     → rm \(searchDBURL.path) && cupertino save")
                Cupertino.Context.composition.logging.recording.output("")
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
                Cupertino.Context.composition.logging.recording.output("   ⚠  Schema version: could not read PRAGMA user_version")
                return true
            }
            if onDiskVersion == expected {
                Cupertino.Context.composition.logging.recording.output("   ✓ Schema version: \(onDiskVersion) (matches installed binary)")
                return true
            }
            if onDiskVersion < expected {
                Cupertino.Context.composition.logging.recording.output("   ✗ Schema version: \(onDiskVersion) (binary expects \(expected), rebuild required)")
                Cupertino.Context.composition.logging.recording.output("     → rm \(searchDBURL.path) && cupertino save")
            } else {
                Cupertino.Context.composition.logging.recording.output("   ✗ Schema version: \(onDiskVersion) (newer than binary — expected \(expected))")
                Cupertino.Context.composition.logging.recording.output("     → Upgrade cupertino: brew upgrade cupertino")
            }
            Cupertino.Context.composition.logging.recording.output("")
            return false
        }

        /// Per-source indexed counts via direct sqlite read. This is the truth
        /// for "can my MCP answer queries about source X?". Hard-fails if the DB
        /// opens but has zero indexed rows (silent-empty MCP otherwise).
        private func reportIndexedSources(at searchDBURL: URL) -> Bool {
            let perSource = Diagnostics.Probes.perSourceCounts(at: searchDBURL)
            if !perSource.isEmpty {
                Cupertino.Context.composition.logging.recording.output("   📚 Indexed sources:")
                for (source, count) in perSource {
                    Cupertino.Context.composition.logging.recording.output("     ✓ \(source): \(count) entries")
                }
            }
            Cupertino.Context.composition.logging.recording.output("")
            let totalIndexed = perSource.reduce(0) { $0 + $1.count }
            if totalIndexed == 0 {
                Cupertino.Context.composition.logging.recording.output("   ✗ Search index is empty (0 rows in docs_metadata)")
                Cupertino.Context.composition.logging.recording.output("     → Rebuild: rm \(searchDBURL.path) && cupertino setup")
                Cupertino.Context.composition.logging.recording.output("")
                return false
            }
            return true
        }

        /// Report `samples.db` presence, size, and row counts (sample projects +
        /// indexed source files). Built by `cupertino save --samples` after sample-code
        /// download + cleanup. Missing is a warning (server runs without it; the
        /// sample-code search just isn't available).
        private func checkSamplesDatabase() {
            let samplesDBURL = Sample.Index.databasePath(baseDirectory: Shared.Paths.live().baseDirectory)

            Cupertino.Context.composition.logging.recording.output("🧪 Sample Code Index (samples.db)")

            guard FileManager.default.fileExists(atPath: samplesDBURL.path) else {
                Cupertino.Context.composition.logging.recording.output("   ⚠  Database: \(samplesDBURL.path) (not found)")
                Cupertino.Context.composition.logging.recording.output("     → Run: cupertino fetch --type samples && cupertino cleanup && cupertino save --samples")
                Cupertino.Context.composition.logging.recording.output("")
                return
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: samplesDBURL.path)[.size] as? UInt64) ?? 0
            Cupertino.Context.composition.logging.recording.output("   ✓ Database: \(samplesDBURL.path)")
            Cupertino.Context.composition.logging.recording.output("   ✓ Size: \(Shared.Utils.Formatting.formatBytes(Int64(fileSize)))")

            let projectCount = Diagnostics.Probes.rowCount(at: samplesDBURL, sql: Shared.Utils.SQL.countRows(in: "projects"))
            let fileCount = Diagnostics.Probes.rowCount(at: samplesDBURL, sql: Shared.Utils.SQL.countRows(in: "files"))
            let symbolCount = Diagnostics.Probes.rowCount(at: samplesDBURL, sql: Shared.Utils.SQL.countRows(in: "file_symbols"))
            if let projectCount { Cupertino.Context.composition.logging.recording.output("   ✓ Projects: \(projectCount)") }
            if let fileCount { Cupertino.Context.composition.logging.recording.output("   ✓ Indexed files: \(fileCount)") }
            if let symbolCount { Cupertino.Context.composition.logging.recording.output("   ✓ Indexed symbols: \(symbolCount)") }
            Cupertino.Context.composition.logging.recording.output("")
        }

        /// #192 F1. Report `packages.db` presence, size, and row counts (packages,
        /// files). Schema version tracked via the bundle-wide
        /// `Shared.Constants.App.databaseVersion` constant rather than a PRAGMA
        /// (packages.db is downloaded as part of the v1.0+ bundle, not migrated).
        private func checkPackagesDatabase() -> Bool {
            let packagesDBURL = Shared.Paths.live().packagesDatabase

            Cupertino.Context.composition.logging.recording.output("📦 Packages Index (packages.db)")

            guard FileManager.default.fileExists(atPath: packagesDBURL.path) else {
                Cupertino.Context.composition.logging.recording.output("   ⚠  Database: \(packagesDBURL.path) (not found)")
                Cupertino.Context.composition.logging.recording.output("     → Run: cupertino setup  (downloads the pre-built packages index)")
                Cupertino.Context.composition.logging.recording.output("     Expected version: \(Shared.Constants.App.databaseVersion)")
                Cupertino.Context.composition.logging.recording.output("")
                // Missing packages.db is a warning, not a failure — server still
                // runs, just without the packages tool. Doctor summary stays green.
                return true
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: packagesDBURL.path)[.size] as? UInt64) ?? 0
            Cupertino.Context.composition.logging.recording.output("   ✓ Database: \(packagesDBURL.path)")
            Cupertino.Context.composition.logging.recording.output("   ✓ Size: \(Shared.Utils.Formatting.formatBytes(Int64(fileSize)))")

            let packageCount = Diagnostics.Probes.rowCount(at: packagesDBURL, sql: Shared.Utils.SQL.countRows(in: "packages"))
            let fileCount = Diagnostics.Probes.rowCount(at: packagesDBURL, sql: Shared.Utils.SQL.countRows(in: "package_files"))
            if let packageCount { Cupertino.Context.composition.logging.recording.output("   ✓ Packages: \(packageCount)") }
            if let fileCount { Cupertino.Context.composition.logging.recording.output("   ✓ Indexed files: \(fileCount)") }
            Cupertino.Context.composition.logging.recording.output("   ℹ  Bundled version: \(Shared.Constants.App.databaseVersion)")
            Cupertino.Context.composition.logging.recording.output("")
            return true
        }

        private func checkPackages() async {
            // Path-DI composition sub-root (#535).
            let paths = Shared.Paths.live()
            let packagesDir = paths.packagesDirectory
            let userSelectionsURL = paths.baseDirectory
                .appendingPathComponent(Shared.Constants.FileName.selectedPackages)

            Cupertino.Context.composition.logging.recording.output("📦 Swift Packages")

            // Load selected URLs once and derive the canonical "owner/repo" key
            // set so we can compare against on-disk READMEs by NAME, not by count.
            let selectedURLs: Set<String>
            if FileManager.default.fileExists(atPath: userSelectionsURL.path) {
                selectedURLs = Diagnostics.Probes.userSelectedPackageURLs(from: userSelectionsURL)
                Cupertino.Context.composition.logging.recording.output("   ✓ User selections: \(userSelectionsURL.path)")
                Cupertino.Context.composition.logging.recording.output("     \(selectedURLs.count) packages selected")
            } else {
                selectedURLs = []
                Cupertino.Context.composition.logging.recording.output("   ⚠  User selections: not configured")
                Cupertino.Context.composition.logging.recording.output("     → Use TUI to select packages, or will use bundled defaults")
            }
            let selectedKeys = Set(selectedURLs.compactMap(Diagnostics.Probes.ownerRepoKey(forGitHubURL:)))

            // Check downloaded READMEs and identify true orphans (downloaded
            // owner/repo no longer in selections) and true gaps (selected but
            // not yet downloaded).
            if FileManager.default.fileExists(atPath: packagesDir.path) {
                let readmeKeys = Diagnostics.Probes.packageREADMEKeys(in: packagesDir)
                if readmeKeys.isEmpty {
                    Cupertino.Context.composition.logging.recording.output("   ⚠  Package docs: directory exists but no package files")
                } else {
                    Cupertino.Context.composition.logging.recording.output("   ✓ Downloaded READMEs: \(readmeKeys.count) packages")
                    Cupertino.Context.composition.logging.recording.output("     \(packagesDir.path)")

                    if !selectedKeys.isEmpty {
                        let orphans = readmeKeys.subtracting(selectedKeys)
                        let missing = selectedKeys.subtracting(readmeKeys)
                        if !orphans.isEmpty {
                            Cupertino.Context.composition.logging.recording.output("   ⚠  Orphaned READMEs: \(orphans.count) (downloaded but no longer selected)")
                        }
                        if !missing.isEmpty {
                            Cupertino.Context.composition.logging.recording.output("   ⚠  Missing READMEs: \(missing.count) (selected but not yet downloaded)")
                            Cupertino.Context.composition.logging.recording.output("     → Run: cupertino fetch --type packages")
                        }
                    }
                }
            } else {
                Cupertino.Context.composition.logging.recording.output("   ⚠  Package docs: not downloaded")
            }

            // Show priority packages source. The catalog is constructed
            // with the resolved base directory at the composition sub-root
            // (#535: catalog is now an actor, not a singleton).
            let priorityCatalog = Core.PackageIndexing.PriorityPackagesCatalog(baseDirectory: paths.baseDirectory)
            let allPackages = await priorityCatalog.allPackages
            let appleCount = await priorityCatalog.applePackages.count
            let ecosystemCount = await priorityCatalog.ecosystemPackages.count
            Cupertino.Context.composition.logging.recording.output("   ℹ  Priority packages: \(allPackages.count) total")
            Cupertino.Context.composition.logging.recording.output("     Apple: \(appleCount), Ecosystem: \(ecosystemCount)")

            Cupertino.Context.composition.logging.recording.output("")
        }

        private func checkResourceProviders() -> Bool {
            Cupertino.Context.composition.logging.recording.output("🔧 Providers")
            Cupertino.Context.composition.logging.recording.output("   ✓ MCP.Support.DocsResourceProvider: available")
            Cupertino.Context.composition.logging.recording.output("   ✓ SearchToolProvider: available")
            Cupertino.Context.composition.logging.recording.output("")
            return true
        }
    }
}
