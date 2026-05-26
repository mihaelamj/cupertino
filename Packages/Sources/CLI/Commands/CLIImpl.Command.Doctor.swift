import ArgumentParser
import Core
import CorePackageIndexing
import CoreProtocols
import Diagnostics
import DistributionModels
import Foundation
import Indexer
import Logging
import LoggingModels
import MCPCore
import MCPSupport
import SampleIndex
import SearchAPI
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
            is normal in that flow — not a failure.
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

        /// #626 — kind distribution audit. When set, doctor walks
        /// `docs_structured.kind` joined with `docs_metadata.source` and
        /// prints per-source kind histograms + the `unknown` rate per
        /// source. Designed as a release-time metric so the team can
        /// see whether the indexer-side improvements landed (#633 / #664
        /// / future tiers) actually moved the needle on the corpus.
        /// Read-only, no DB writes. Independent of `--save` — the kind
        /// distribution is informational; doesn't gate doctor verdict.
        @Flag(
            name: .long,
            help: """
            Print a kind distribution audit per source (`apple-docs`, `samples`, etc.). \
            Reports total rows per kind, percentage, and `unknown` rate. Useful after a \
            reindex to verify kind-extraction improvements landed. Read-only.
            """
        )
        var kindCoverage: Bool = false

        /// #275 — per-source freshness / drift report from `docs_metadata.last_crawled`.
        /// Brew-installed users have no git-level access to the raw corpus repo, so neither
        /// `git log` nor filesystem mtimes give them a useful answer to "how stale is
        /// my local index?". `last_crawled` is on every row and is stamped at indexer
        /// save time, so it's the authoritative signal available without external state.
        /// Independent of `--save`; doesn't gate doctor verdict.
        @Flag(
            name: .long,
            help: """
            Print a per-source freshness report from docs_metadata.last_crawled timestamps. \
            Shows row count + oldest / p50 / p90 / newest crawl dates per source. Answers \
            "how stale is my local index?" for brew users without a corpus checkout. Read-only.
            """
        )
        var freshness: Bool = false

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

            // #930: per-DB sections lifted into `Distribution.DatabaseHealthCheck`
            // conformers. `healthChecks` is the canonical ordered list; the
            // composition-root assembly is the sole edit point. Adding a 4th
            // DB is one new conformer + one append to this list, no other
            // changes. Every element of the list is iterated (no `prefix`,
            // no out-of-loop calls), so a new conformer cannot silently
            // disappear from `cupertino doctor`'s output.
            //
            // Post-2026-05-26 audit Finding 7.1: extend coverage to every
            // per-source destinationDB declared by the registry. Pre-fix
            // only the legacy 3-DB shape (packages / samples / search)
            // got a health probe; the 5-6 per-source FTS DBs landed by
            // #1036 (apple-documentation.db, hig.db, apple-archive.db,
            // swift-evolution.db, swift-documentation.db) were SILENTLY
            // un-probed — a corrupt per-source DB would let doctor
            // report "healthy" while MCP returned partial results.
            //
            // Composition: 2 dedicated conformers for the two non-FTS
            // DB families (PackagesHealthCheck for packages.db's
            // BM25+chunk schema; SamplesHealthCheck for apple-sample-code.db's
            // catalog-metadata tables which use a different schema_version
            // probe) + the legacy `.search` SearchHealthCheck (transitional)
            // + one SearchHealthCheck per registered FTS-tier destinationDB.
            let recording = Cupertino.Context.composition.logging.recording
            let paths = Shared.Paths.live()
            let registry = CLIImpl.makeProductionSourceRegistry()
            var healthChecks: [any Distribution.DatabaseHealthCheck] = [
                PackagesHealthCheck(packagesDBURL: paths.packagesDatabase),
                SamplesHealthCheck(samplesDBURL: Sample.Index.databasePath(baseDirectory: paths.baseDirectory)),
                SearchHealthCheck(
                    descriptor: .search,
                    searchDBURL: URL(fileURLWithPath: searchDB).expandingTildeInPath,
                    isRequired: true
                ),
            ]
            // One conformer per FTS-tier per-source destinationDB.
            // Excluded: .search (already added above as legacy required),
            // .packages (its own non-FTS conformer), .appleSampleCode
            // (its own dual-schema conformer). Uniquify by descriptor.id
            // because view-source pairs (swift-org + swift-book) share
            // `.swiftDocumentation`.
            var seen: Set<String> = [
                Shared.Models.DatabaseDescriptor.search.id,
                Shared.Models.DatabaseDescriptor.packages.id,
                Shared.Models.DatabaseDescriptor.appleSampleCode.id,
            ]
            for provider in registry.allEnabled {
                let descriptor = provider.destinationDB
                guard !seen.contains(descriptor.id) else { continue }
                seen.insert(descriptor.id)
                healthChecks.append(SearchHealthCheck(
                    descriptor: descriptor,
                    searchDBURL: paths.baseDirectory.appendingPathComponent(descriptor.filename),
                    isRequired: false
                ))
            }
            for check in healthChecks {
                let ok = await check.run(output: recording)
                if check.isRequired { allChecks = ok && allChecks }
            }

            // `checkSampleArchiveIntegrity` is intentionally OUTSIDE the
            // healthChecks loop: it probes on-disk sample-code zip files
            // (`~/.cupertino/sample-code/*.zip`), not the samples SQLite
            // database. Pre-#930 it rendered between the Samples and Search
            // sections, keyed on textual sequence; coupling it to a DB
            // conformer would make a future "drop samples.db" refactor
            // silently kill this orthogonal probe. Running it after the
            // DB loop keeps its presence explicit and trivially auditable
            // (one line, one call, no coupling). The section order changes
            // from {Packages, Samples, SampleArchive, Search, Resources}
            // to {Packages, Samples, Search, SampleArchive, Resources};
            // both are descriptive sequences with no functional dependency.
            checkSampleArchiveIntegrity()

            allChecks = checkResourceProviders() && allChecks
            // Schema versions across all three DBs (#234)
            printSchemaVersions()
            // #673 Phase F — disk-space red flag. Surfaces low free disk
            // on the volume backing ~/.cupertino so users see the risk
            // before a `cupertino save` / `cupertino setup` would refuse
            // partway through. Always runs (independent of --save / etc.)
            // — disk pressure affects every cupertino operation.
            checkDiskSpace()

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

            // ----- #626 kind-coverage audit (informational) ---------------
            // Doesn't gate the doctor verdict — purely a release-time
            // metric. When the user wakes after a reindex, this is the
            // one-liner that says "yes, your indexer fixes moved the
            // unknown rate from 57% to N%". Reads `search.db` directly;
            // skipped silently when the file is missing or schema-
            // mismatched (the regular `checkSearchDatabase` already
            // surfaced that).
            if kindCoverage {
                checkKindCoverage()
            }

            // ----- #275 freshness / drift signal (informational) ---------
            // Independent of `--save` / `--kind-coverage`. Doesn't gate
            // the verdict — purely informational. Targets brew users who
            // can't `git log` the corpus repo to answer "how stale is my
            // bundle?". The doctor's existing schema-version / journal-
            // mode lines tell them how their DB compares to the binary;
            // this tells them how their DB compares to Apple's "now".
            if freshness {
                checkFreshness()
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
        /// fail the check (they're already covered by the per-DB sections
        /// above).
        ///
        /// #248 third cut: the entries list inside THIS method is keyed
        /// by canonical `Shared.Models.DatabaseDescriptor` constants, so
        /// adding a 4th DB to the schema-versions section is a 2-line
        /// edit. #930 (fourth cut) lifted the 3 sibling per-DB sections
        /// into `Distribution.DatabaseHealthCheck` conformers (each with
        /// its own verdict policy + probe set); this method retains its
        /// own iteration because its policy is "missing is informational,
        /// never gates the verdict" which differs from every conformer.
        private func printSchemaVersions() {
            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.output("8. Schema versions (#234)")
            Cupertino.Context.composition.logging.recording.output("")
            // Path-DI composition sub-root (#535).
            let paths = Shared.Paths.live()
            // Per-source DB sections (post-#1037 split + #1038
            // swift-org/swift-book separation). Each descriptor's
            // filename is the on-disk path under the base directory;
            // the legacy `.search` descriptor (pre-#1037 monolithic
            // search.db) is kept for transition-period visibility but
            // post-migration users see "not built" for it once the
            // per-source DBs are populated.
            //
            // `.appleSampleCode` uses the per-pipeline
            // `samples_schema_version` table probe instead of PRAGMA
            // user_version (post-#1037 the Sample.Index pipeline does
            // not stamp the PRAGMA so it can coexist with Search.Index
            // tables in the same file).
            //
            // Post-2026-05-26 audit (Finding 7.2): derive the entries
            // list from the production source registry so adding a new
            // source automatically extends Doctor's schema-version
            // output without an edit here. The legacy `.search`
            // descriptor stays as a leading transitional entry for
            // pre-#1037 users; the 2 non-uniform path resolvers
            // (`.packages` → `paths.packagesDatabase`; `.appleSampleCode`
            // → `Sample.Index.databasePath`) handle the special cases.
            // Every other descriptor's path is `baseDirectory + filename`.
            let docsBase = paths.baseDirectory
            let registry = CLIImpl.makeProductionSourceRegistry()
            var entries: [(Shared.Models.DatabaseDescriptor, URL)] = [
                (.search, URL(fileURLWithPath: searchDB).expandingTildeInPath),
            ]
            // Each registered destination — uniquify via Set since
            // view-source pairs (swift-org + swift-book) share a
            // destinationDB.
            var seenDescriptors: Set<String> = [Shared.Models.DatabaseDescriptor.search.id]
            for provider in registry.allEnabled {
                let descriptor = provider.destinationDB
                guard !seenDescriptors.contains(descriptor.id) else { continue }
                seenDescriptors.insert(descriptor.id)
                let url: URL
                if descriptor == .packages {
                    url = paths.packagesDatabase
                } else if descriptor == .appleSampleCode {
                    url = Sample.Index.databasePath(baseDirectory: docsBase)
                } else {
                    url = docsBase.appendingPathComponent(descriptor.filename)
                }
                entries.append((descriptor, url))
            }
            for (descriptor, url) in entries {
                let label = descriptor.filename
                guard FileManager.default.fileExists(atPath: url.path) else {
                    Cupertino.Context.composition.logging.recording.output("   ⚠ \(label): not built")
                    continue
                }
                let version: Int32 = if descriptor == .appleSampleCode {
                    Diagnostics.Probes.samplesSchemaVersion(at: url) ?? 0
                } else {
                    Diagnostics.Probes.userVersion(at: url) ?? 0
                }
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

                let line = Self.renderSchemaVersionLine(
                    descriptor: descriptor,
                    formatted: formatted,
                    journalNote: journalNote,
                    walNote: walNote,
                    volumeNote: volumeNote
                )
                Cupertino.Context.composition.logging.recording.output(line)
            }
        }

        /// Pure formatter for one schema-version line in
        /// `cupertino doctor`'s output. Extracted out of
        /// `printSchemaVersions` so the line format can be pinned by a
        /// unit test (#919 ironclad coverage pins, 2026-05-22).
        ///
        /// The label is `descriptor.filename` (NOT `descriptor.id`)
        /// because the doctor's output is filesystem-oriented: users
        /// looking at the line want to see `search.db` / `samples.db` /
        /// `packages.db` to correlate against their `~/.cupertino/`
        /// directory listing, not the short identifier the indexer
        /// uses internally.
        static func renderSchemaVersionLine(
            descriptor: Shared.Models.DatabaseDescriptor,
            formatted: String,
            journalNote: String,
            walNote: String,
            volumeNote: String
        ) -> String {
            "   ✓ \(descriptor.filename): \(formatted), journal=\(journalNote)\(walNote)\(volumeNote)"
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

        // MARK: - #673 Phase F — disk-space red flag

        /// Inspect free disk on the volume backing the user's base
        /// directory and emit a status line: green ≥ 20 % free, orange
        /// 10-20 % (warn), red < 10 % free (will refuse to save / setup
        /// on next write), CRITICAL if even less than the smallest
        /// per-command estimate could fit.
        ///
        /// Pinned by `Issue673PhaseFDiskPreflightTests` on the probe +
        /// preflight sides; the doctor-side rendering is verified via
        /// the end-to-end binary check in PR #695's live verification.
        private func checkDiskSpace() {
            let target = Shared.Paths.live().baseDirectory
            Cupertino.Context.composition.logging.recording.output("💾 Disk space (#673 Phase F)")
            guard let usage = Diagnostics.Probes.diskUsage(at: target) else {
                Cupertino.Context.composition.logging.recording.output(
                    "   ⚠  Could not read volume stats for \(target.path) (skipped)"
                )
                Cupertino.Context.composition.logging.recording.output("")
                return
            }
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB, .useMB]
            formatter.countStyle = .file
            let free = formatter.string(fromByteCount: usage.freeBytes)
            let total = formatter.string(fromByteCount: usage.totalBytes)
            let pct = String(format: "%.0f", usage.freeFraction * 100)
            let savedEstimate = Shared.Constants.DiskBudget.docsSaveBytes
            let savedNeed = Int64(Double(savedEstimate) * 1.10)
            let savedNeedStr = formatter.string(fromByteCount: savedNeed)

            // Classification thresholds match the preflight: refuse
            // (< 10 % default warningFraction reflects 1/2 of the
            // existing 20 % threshold; we surface "would refuse" as
            // its own line for actionability) / orange / green.
            if usage.freeBytes < savedNeed {
                Cupertino.Context.composition.logging.recording.output(
                    "   ✗ Volume \(target.path): \(free) free of \(total) (\(pct) %); `cupertino save --source apple-docs` would REFUSE (needs \(savedNeedStr))"
                )
                Cupertino.Context.composition.logging.recording.output(
                    "     → Free at least \(formatter.string(fromByteCount: savedNeed - usage.freeBytes)) on this volume before the next save / setup"
                )
            } else if usage.freeFraction < 0.10 {
                Cupertino.Context.composition.logging.recording.output(
                    "   ⚠  Volume \(target.path): \(free) free of \(total) (\(pct) %) — critically low; consider freeing space"
                )
            } else if usage.freeFraction < 0.20 {
                Cupertino.Context.composition.logging.recording.output(
                    "   ⚠  Volume \(target.path): \(free) free of \(total) (\(pct) %) — low; next save will warn"
                )
            } else {
                Cupertino.Context.composition.logging.recording.output(
                    "   ✓ Volume \(target.path): \(free) free of \(total) (\(pct) %)"
                )
            }
            Cupertino.Context.composition.logging.recording.output("")
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
        /// fine). All directories are warnings-only — missing dirs don't
        /// fail doctor. The query-correctness truth lives in `search.db` and is
        /// reported by `checkSearchDatabase`.
        ///
        /// 2026-05-26 audit follow-up: pre-fix the entries list was a
        /// hardcoded 5-element literal naming `(label, url, suffix,
        /// fetchType)` inline; adding a new web-crawlable source meant
        /// editing Doctor AND the `fetchType` values had drifted —
        /// `"docs"` / `"evolution"` / `"swift"` / `"archive"` were not
        /// valid `--source` values post-#1007 registry-driven dispatch,
        /// so Doctor's "→ Run: cupertino fetch --source X" guidance
        /// pointed at commands that would error out with "Unknown
        /// --source value 'docs'". Post-fix the list is derived from
        /// the production registry — every FTS-tier source with a
        /// non-nil `fetchInfo` contributes one entry, each pulling its
        /// label from `fetchInfo.displayName`, its URL from
        /// `Shared.Paths.directory(named: fetchInfo.defaultOutputDirKey.rawValue)`,
        /// its `suffix` from `fetchInfo.corpusFileSuffix`, and its
        /// `fetchType` from `fetchInfo.sourceID` (the canonical
        /// `--source` flag value).
        private func checkDocumentationDirectories() -> Bool {
            let paths = Shared.Paths.live()
            let registry = CLIImpl.makeProductionSourceRegistry()
            let cliDocsURL = URL(fileURLWithPath: docsDir).expandingTildeInPath
            let cliEvolutionURL = URL(fileURLWithPath: evolutionDir).expandingTildeInPath

            Cupertino.Context.composition.logging.recording.output("📂 Raw corpus directories (input for `cupertino save`)")

            let entries: [CorpusEntry] = registry.allEnabled.compactMap { provider in
                guard provider.isSearchTier, let info = provider.fetchInfo else { return nil }
                let dirKey = info.defaultOutputDirKey.rawValue
                let url: URL = switch info.sourceID {
                case Shared.Constants.SourcePrefix.appleDocs: cliDocsURL
                case Shared.Constants.SourcePrefix.swiftEvolution: cliEvolutionURL
                default: paths.directory(named: dirKey)
                }
                return CorpusEntry(
                    label: info.displayName,
                    url: url,
                    suffix: info.corpusFileSuffix,
                    fetchType: info.sourceID
                )
            }

            for entry in entries {
                if FileManager.default.fileExists(atPath: entry.url.path) {
                    let count = Diagnostics.Probes.countCorpusFiles(in: entry.url)
                    Cupertino.Context.composition.logging.recording.output("   ✓ \(entry.label): \(entry.url.path) (\(count) \(entry.suffix))")
                } else {
                    Cupertino.Context.composition.logging.recording.output("   ⚠  \(entry.label): \(entry.url.path) (not found)")
                    Cupertino.Context.composition.logging.recording.output("     → Run: cupertino fetch --source \(entry.fetchType)  (only needed to rebuild from scratch)")
                }
            }

            Cupertino.Context.composition.logging.recording.output("")
            // Filesystem state is informational. The hard fail is whether
            // search.db has indexed data, which `checkSearchDatabase` enforces.
            return true
        }

        /// #657 — scan `~/.cupertino/sample-code/*.zip` for files whose
        /// first 4 bytes don't match a ZIP magic signature. Apple's CDN
        /// occasionally returns an HTML landing page or partial body
        /// with HTTP 200; pre-#657 the fetcher trusted the status code
        /// and the body lingered with a `.zip` extension. The fetcher
        /// now renames such bodies to `<filename>.invalid` at download
        /// time (and counts them in `Sample.Core.Statistics
        /// .invalidDownloads`), but this probe is the safety net for
        /// any pre-#657 corpora and for files that survived earlier
        /// fetch runs. Soft warning; doctor summary stays green when
        /// the count is non-zero so a stale corpus doesn't fail the
        /// post-promote health check.
        private func checkSampleArchiveIntegrity() {
            let directory = Shared.Paths.live().sampleCodeDirectory
            Cupertino.Context.composition.logging.recording.output("📦 Sample Code Archive Integrity (#657)")

            guard FileManager.default.fileExists(atPath: directory.path) else {
                Cupertino.Context.composition.logging.recording.output("   ⚠  Directory: \(directory.path) (not found)")
                Cupertino.Context.composition.logging.recording.output("     → Run: cupertino fetch --source samples")
                Cupertino.Context.composition.logging.recording.output("")
                return
            }

            let contents = (try? Shared.Utils.FileSystem.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            let zips = contents.filter { $0.pathExtension.lowercased() == "zip" }
            let invalid = zips.filter { !Shared.Utils.ZipMagic.isValid(at: $0) }

            Cupertino.Context.composition.logging.recording.output("   ✓ Directory: \(directory.path)")
            Cupertino.Context.composition.logging.recording.output("   ✓ Total archives: \(zips.count)")
            if invalid.isEmpty {
                Cupertino.Context.composition.logging.recording.output("   ✓ Invalid ZIP archives: 0")
            } else {
                Cupertino.Context.composition.logging.recording.output("   ⚠  Invalid ZIP archives: \(invalid.count)")
                // Cap the list at 5 to keep doctor output bounded; the
                // count is the actionable signal, the names are a
                // breadcrumb.
                for url in invalid.prefix(5) {
                    Cupertino.Context.composition.logging.recording.output("     - \(url.lastPathComponent)")
                }
                if invalid.count > 5 {
                    Cupertino.Context.composition.logging.recording.output("     - … and \(invalid.count - 5) more")
                }
                Cupertino.Context.composition.logging.recording.output("     → These are likely HTML landing pages saved as .zip (Apple CDN transient 200s).")
                Cupertino.Context.composition.logging.recording.output("     → Remove them manually, or re-run: cupertino fetch --source samples --force")
            }
            Cupertino.Context.composition.logging.recording.output("")
        }

        /// #626 — kind distribution audit. Walks `docs_structured.kind`
        /// joined with `docs_metadata.source` and prints per-source
        /// histograms ordered by count desc. Highlights the `unknown`
        /// rate per source so a reindex audit answers "did the
        /// indexer-side improvements (#615 / #633 / #664) actually
        /// land on this bundle?". Informational; doesn't gate the
        /// doctor verdict. Skipped silently when `search.db` is
        /// missing or unopenable (the regular `checkSearchDatabase`
        /// already surfaced that).
        private func checkKindCoverage() {
            let searchDBURL = URL(fileURLWithPath: searchDB).expandingTildeInPath
            Cupertino.Context.composition.logging.recording.output("🧩 Kind distribution audit (#626)")

            guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
                Cupertino.Context.composition.logging.recording.output("   ⚠  search.db not found at \(searchDBURL.path) (skipped)")
                Cupertino.Context.composition.logging.recording.output("")
                return
            }

            guard let rows = Diagnostics.Probes.kindHistogramBySource(at: searchDBURL) else {
                Cupertino.Context.composition.logging.recording.output("   ⚠  Could not read kind histogram from \(searchDBURL.path) (skipped — schema mismatch or DB unopenable)")
                Cupertino.Context.composition.logging.recording.output("")
                return
            }

            // Group rows by source. Each source gets its own per-kind
            // breakdown + an `unknown`-rate summary line.
            var bySource: [String: [(kind: String, count: Int)]] = [:]
            for row in rows {
                bySource[row.source, default: []].append((kind: row.kind, count: row.count))
            }
            guard !bySource.isEmpty else {
                Cupertino.Context.composition.logging.recording.output("   ⚠  No rows in docs_metadata (DB present but empty)")
                Cupertino.Context.composition.logging.recording.output("")
                return
            }

            for source in bySource.keys.sorted() {
                let kinds = bySource[source] ?? []
                let total = kinds.reduce(0) { $0 + $1.count }
                let unknown = kinds.first { $0.kind == "unknown" }?.count ?? 0
                let missing = kinds.first { $0.kind == "(missing)" }?.count ?? 0
                let unrecognised = unknown + missing
                let unknownPct = total > 0 ? Double(unrecognised) / Double(total) * 100 : 0
                let summary = String(format: "%.1f", unknownPct)
                Cupertino.Context.composition.logging.recording.output("   \(source) — \(total) rows, unknown/missing: \(unrecognised) (\(summary)%)")
                // Show the top 5 kinds per source to keep output bounded
                // on a 280k-row bundle. The dominant kinds are the
                // signal; the long tail of `actor` / `macro` / `case`
                // matters for #626 follow-up tiers but is noisy at the
                // doctor level.
                for entry in kinds.prefix(5) {
                    let pct = total > 0 ? Double(entry.count) / Double(total) * 100 : 0
                    // Manual padding — `%s` in Swift's String(format:)
                    // expects a C string; passing a Swift String renders
                    // garbage. Pad via Swift `padding(toLength:withPad:
                    // startingAt:)` for the kind name and `String(
                    // repeating:count:)` for the right-aligned count.
                    let kindPadded = entry.kind.padding(toLength: 14, withPad: " ", startingAt: 0)
                    let countRaw = String(entry.count)
                    let countPadded = String(repeating: " ", count: max(0, 8 - countRaw.count)) + countRaw
                    let pctStr = String(format: "%5.1f", pct)
                    Cupertino.Context.composition.logging.recording.output(
                        "     \(kindPadded)\(countPadded)  (\(pctStr)%)"
                    )
                }
                if kinds.count > 5 {
                    Cupertino.Context.composition.logging.recording.output("     … and \(kinds.count - 5) more")
                }
            }
            Cupertino.Context.composition.logging.recording.output("")
        }

        // MARK: - #275 — freshness / drift signal

        /// Per-source freshness report driven by `Diagnostics.Probes.freshnessBySource`.
        /// Renders each source's row count + oldest / p50 / p90 / newest
        /// crawl dates. Skipped silently when `search.db` is missing or
        /// unopenable (the regular `checkSearchDatabase` already surfaced
        /// that). No thresholds — raw ages only, per #275's scoping
        /// discussion. Users decide their own "fresh / aging / stale"
        /// definitions; thresholds are a separate follow-up if needed.
        private func checkFreshness() {
            let searchDBURL = URL(fileURLWithPath: searchDB).expandingTildeInPath
            Cupertino.Context.composition.logging.recording.output("📅 Freshness / drift signal (#275)")

            guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
                Cupertino.Context.composition.logging.recording.output("   ⚠  search.db not found at \(searchDBURL.path) (skipped)")
                Cupertino.Context.composition.logging.recording.output("")
                return
            }

            guard let rows = Diagnostics.Probes.freshnessBySource(at: searchDBURL) else {
                Cupertino.Context.composition.logging.recording.output(
                    "   ⚠  Could not read freshness from \(searchDBURL.path) (skipped — schema mismatch or DB unopenable)"
                )
                Cupertino.Context.composition.logging.recording.output("")
                return
            }

            guard !rows.isEmpty else {
                Cupertino.Context.composition.logging.recording.output("   ⚠  No rows in docs_metadata (DB present but empty)")
                Cupertino.Context.composition.logging.recording.output("")
                return
            }

            // Header row — column layout matches kindCoverage's style
            // (left-pad source, right-pad numeric, manual formatting
            // because Swift's String(format:) on %s expects C strings).
            Cupertino.Context.composition.logging.recording.output(
                "   source              rows    oldest                p50                   p90                   newest"
            )
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            for row in rows {
                let sourcePadded = row.source.padding(toLength: 18, withPad: " ", startingAt: 0)
                let countRaw = String(row.count)
                let countPadded = String(repeating: " ", count: max(0, 8 - countRaw.count)) + countRaw
                let oldest = Self.renderDate(row.oldest, formatter: formatter)
                let p50 = Self.renderDate(row.p50, formatter: formatter)
                let p90 = Self.renderDate(row.p90, formatter: formatter)
                let newest = Self.renderDate(row.newest, formatter: formatter)
                Cupertino.Context.composition.logging.recording.output(
                    "   \(sourcePadded)\(countPadded)  \(oldest)    \(p50)    \(p90)    \(newest)"
                )
            }
            Cupertino.Context.composition.logging.recording.output("")
        }

        /// Format a `last_crawled` Unix epoch (seconds) as a YYYY-MM-DD
        /// string. Returns a constant `"(unset)"` for `0` / negative
        /// values so the row stays right-aligned and the reader sees
        /// the empty-state explicitly.
        private static func renderDate(_ epoch: Int64, formatter: ISO8601DateFormatter) -> String {
            guard epoch > 0 else { return "(unset)   " }
            let date = Date(timeIntervalSince1970: TimeInterval(epoch))
            return formatter.string(from: date)
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
                            Cupertino.Context.composition.logging.recording.output("     → Run: cupertino fetch --source packages")
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
