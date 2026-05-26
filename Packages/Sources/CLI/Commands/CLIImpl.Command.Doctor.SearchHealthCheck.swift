import Diagnostics
import DistributionModels
import Foundation
import LoggingModels
import SearchAPI
import SharedConstants

extension CLIImpl.Command.Doctor {
    /// `Distribution.DatabaseHealthCheck` conformer for FTS-tier
    /// databases (the legacy `search.db` plus every per-source DB
    /// post-#1036: apple-documentation.db / hig.db / apple-archive.db /
    /// swift-evolution.db / swift-documentation.db).
    ///
    /// The legacy `.search` instance is **hard-required** (red exit
    /// on failure) for back-compat with the pre-#1037 bundle shape.
    /// Per-source instances are **warning-only** — a missing
    /// per-source DB is expected for partial scopes (e.g. `cupertino
    /// save --source hig` only writes `hig.db`).
    ///
    /// Post-2026-05-26 audit Finding 7.1: pre-fix the descriptor was
    /// hardcoded to `.search` so adding a per-source DB to Doctor's
    /// coverage required either (a) extending the global `healthChecks`
    /// list with a new conformer type per source, or (b) silently
    /// skipping the new DB's health probe. Now SearchHealthCheck
    /// accepts the descriptor at init so the composition root can
    /// stamp one instance per registered docs-tier destinationDB.
    struct SearchHealthCheck: Distribution.DatabaseHealthCheck {
        let descriptor: Shared.Models.DatabaseDescriptor
        let isRequired: Bool

        let searchDBURL: URL

        init(
            descriptor: Shared.Models.DatabaseDescriptor = .search,
            searchDBURL: URL,
            isRequired: Bool = true
        ) {
            self.descriptor = descriptor
            self.searchDBURL = searchDBURL
            self.isRequired = isRequired
        }

        func run(output recording: any Logging.Recording) async -> Bool {
            // Section header reflects the descriptor. Legacy
            // `.search` keeps the original "Search Index" label;
            // per-source FTS DBs render with `descriptor.displayName`
            // so the operator sees what's on disk.
            if descriptor == .search {
                recording.output("🔍 Search Index")
            } else {
                recording.output("🔍 \(descriptor.displayName) (\(descriptor.filename))")
            }

            guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
                // Missing-file verdict scales with isRequired: hard
                // fail for the legacy required `.search`; informational
                // for per-source DBs the user may not have built yet.
                if isRequired {
                    recording.output("   ✗ Database: \(searchDBURL.path) (not found)")
                    recording.output("     → Run: cupertino setup  (or `cupertino save` if building locally)")
                    recording.output("")
                    return false
                } else {
                    recording.output("   ⚠  Database: \(searchDBURL.path) (not built — run `cupertino save --source \(descriptor.id)` to populate)")
                    recording.output("")
                    return true
                }
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: searchDBURL.path)[.size] as? UInt64) ?? 0
            recording.output("   ✓ Database: \(searchDBURL.path)")
            recording.output("   ✓ Size: \(Shared.Utils.Formatting.formatBytes(Int64(fileSize)))")

            if !reportSchemaVersion(recording: recording) {
                return false
            }

            // The init can throw (DB unopenable / schema-migration failure);
            // in that case there is no actor instance to disconnect.
            // listFrameworks can also throw after a successful init (FTS5
            // virtual table corrupt, locked, etc.); the actor was constructed,
            // so we MUST disconnect on the error path. The scoping below is
            // tight on purpose:
            //   * `reportIndexedSources` stays OUTSIDE the throwing do-block
            //     (it reads sqlite via `Diagnostics.Probes` directly, not the
            //     actor, and is non-throwing today). Keeping it out means a
            //     future refactor that surfaces a probe error would not be
            //     misattributed to the listFrameworks failure path.
            //   * `disconnect()` is called on both happy + error paths but
            //     never on the init-throw path (no actor exists). `defer`
            //     can't `await` so this is expressed as explicit calls.
            let searchIndex: SearchModule.Index
            do {
                // #932: doctor read-only probe; never calls indexItem.
                searchIndex = try await SearchModule.Index(dbPath: searchDBURL, logger: recording, indexers: [:], sourceLookup: .empty)
            } catch {
                recording.output("   ✗ Database error: \(error)")
                recording.output("     → rm \(searchDBURL.path) && cupertino save")
                recording.output("")
                return false
            }
            do {
                let frameworks = try await searchIndex.listFrameworks()
                recording.output("   ✓ Frameworks: \(frameworks.count)")
            } catch {
                recording.output("   ✗ Database error: \(error)")
                recording.output("     → rm \(searchDBURL.path) && cupertino save")
                recording.output("")
                await searchIndex.disconnect()
                return false
            }
            await searchIndex.disconnect()
            return reportIndexedSources(recording: recording)
        }

        /// Read `PRAGMA user_version` and compare against the binary's expected
        /// schema. Returns false on mismatch (with a precise rebuild hint), true
        /// on match or unreadable. Read BEFORE opening via `SearchModule.Index` because
        /// migrating from an incompatible version throws during init, and the
        /// user wants to know which version they're stuck on.
        private func reportSchemaVersion(recording: any Logging.Recording) -> Bool {
            let onDiskVersion = Diagnostics.Probes.userVersion(at: searchDBURL)
            let expected = SearchModule.Index.schemaVersion
            guard let onDiskVersion else {
                recording.output("   ⚠  Schema version: could not read PRAGMA user_version")
                return true
            }
            if onDiskVersion == expected {
                recording.output("   ✓ Schema version: \(onDiskVersion) (matches installed binary)")
                return true
            }
            if onDiskVersion < expected {
                recording.output("   ✗ Schema version: \(onDiskVersion) (binary expects \(expected), rebuild required)")
                recording.output("     → rm \(searchDBURL.path) && cupertino save")
            } else {
                recording.output("   ✗ Schema version: \(onDiskVersion) (newer than binary, expected \(expected))")
                recording.output("     → Upgrade cupertino: brew upgrade cupertino")
            }
            recording.output("")
            return false
        }

        /// Per-source indexed counts via direct sqlite read. This is the truth
        /// for "can my MCP answer queries about source X?". Hard-fails if the DB
        /// opens but has zero indexed rows (silent-empty MCP otherwise).
        private func reportIndexedSources(recording: any Logging.Recording) -> Bool {
            let perSource = Diagnostics.Probes.perSourceCounts(at: searchDBURL)
            if !perSource.isEmpty {
                recording.output("   📚 Indexed sources:")
                for (source, count) in perSource {
                    recording.output("     ✓ \(source): \(count) entries")
                }
            }
            recording.output("")
            let totalIndexed = perSource.reduce(0) { $0 + $1.count }
            if totalIndexed == 0 {
                // Empty-DB verdict scales with isRequired (mirror of the
                // missing-file branch). The legacy `.search` empties hard;
                // a fresh per-source DB that hasn't been populated by
                // `cupertino save --source <id>` yet stays informational.
                if isRequired {
                    recording.output("   ✗ Search index is empty (0 rows in docs_metadata)")
                    recording.output("     → Rebuild: rm \(searchDBURL.path) && cupertino setup")
                    recording.output("")
                    return false
                } else {
                    recording.output("   ⚠  Index is empty (0 rows in docs_metadata)")
                    recording.output("     → Populate: cupertino save --source \(descriptor.id)")
                    recording.output("")
                    return true
                }
            }
            return true
        }
    }
}
