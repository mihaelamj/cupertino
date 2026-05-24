import Diagnostics
import DistributionModels
import Foundation
import LoggingModels
import SearchAPI
import SharedConstants

extension CLIImpl.Command.Doctor {
    /// `Distribution.DatabaseHealthCheck` conformer for `search.db`.
    /// Hard-required: a missing or unreadable search index fails the
    /// overall doctor verdict (red exit). The conformer renders the
    /// same section as the pre-#930 `Doctor.checkSearchDatabase`
    /// private method, byte-for-byte, and opens `SearchModule.Index`
    /// to count frameworks + per-source rows.
    struct SearchHealthCheck: Distribution.DatabaseHealthCheck {
        let descriptor: Shared.Models.DatabaseDescriptor = .search
        let isRequired: Bool = true

        let searchDBURL: URL

        init(searchDBURL: URL) {
            self.searchDBURL = searchDBURL
        }

        func run(output recording: any Logging.Recording) async -> Bool {
            recording.output("🔍 Search Index")

            guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
                recording.output("   ✗ Database: \(searchDBURL.path) (not found)")
                recording.output("     → Run: cupertino setup  (or `cupertino save` if building locally)")
                recording.output("")
                return false
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
                recording.output("   ✗ Search index is empty (0 rows in docs_metadata)")
                recording.output("     → Rebuild: rm \(searchDBURL.path) && cupertino setup")
                recording.output("")
                return false
            }
            return true
        }
    }
}
