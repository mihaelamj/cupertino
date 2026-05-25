import Foundation
import SearchModels
import SharedConstants

// MARK: - Distribution.PerSourceDBSplitMigrator

/// One-shot migration shim that splits an existing legacy
/// `search.db` (the pre-per-source-db-split bundle shape, with rows
/// from all 6 search-style sources co-located) into per-source
/// destination DBs (one file per `Shared.Models.DatabaseDescriptor`).
///
/// Step 6 of `docs/design/per-source-db-split.md`. Runs once per
/// upgrade: detect legacy DB, copy rows into per-source DBs, rename
/// legacy to `search.db.legacy-pre-per-source-split` (preserved for
/// one release for forensic inspection), report per-source row counts.
///
/// **Step 6a scope (this commit)**: scaffolding + detection +
/// detailed plan/outcome value types. Row-copy implementation lands
/// in step 6b; CLI wiring (`cupertino setup` / `cupertino save`
/// first-run hook) lands in step 6c.
///
/// Lives in `Distribution` (the cupertino-setup composition tier),
/// not in `SearchSQLite`, because the migrator coordinates ACROSS
/// multiple `Search.Index` instances (one per destination DB) and
/// the orchestration is composition-root work.
extension Distribution {
    public enum PerSourceDBSplitMigrator {
        // MARK: - Value types

        /// Result of a migration-needed check at a candidate base dir.
        public enum DetectionOutcome: Sendable, Equatable {
            /// No legacy `search.db` exists at the checked path; nothing
            /// to migrate. Either a fresh-install user, or a user who
            /// already migrated in a prior run (legacy file was renamed
            /// to `.legacy-pre-per-source-split`).
            case noLegacyDBFound

            /// Legacy `search.db` exists but already looks split (per-source
            /// DBs are present alongside it). Migration should NOT run;
            /// the legacy file is a stale leftover the user can manually
            /// delete. The shim does NOT auto-delete; deletion is opt-in.
            case alreadyMigrated(legacyFile: URL, splitFiles: [URL])

            /// Legacy `search.db` exists and per-source DBs are absent
            /// or empty. Migration should run.
            case migrationNeeded(legacyFile: URL)

            /// A file named `search.db` exists but its schema does not
            /// match the expected legacy shape (no `docs_metadata` table
            /// with a `source` column). Shim refuses to operate.
            case legacyFileMalformed(legacyFile: URL, reason: String)
        }

        /// Per-source plan derived from the legacy DB's `source` column.
        public struct SourcePlan: Sendable, Equatable {
            /// The source-id literal as it appears in `docs_metadata.source`
            /// (e.g. `"apple-docs"`, `"hig"`, `"sample-code"`).
            public let sourceID: String

            /// The destination descriptor's `id` (e.g. `"apple-documentation"`).
            /// Mapping is via `SourceLookup`: row-emission source-id ->
            /// SourceProvider.definition.id -> destinationDB.id. For source
            /// ids the registry doesn't recognise (legacy data with no
            /// current provider), the plan still lists them; the migration
            /// uses `.search` (legacy file) as fallback destination so no
            /// rows are dropped.
            public let destinationDescriptorID: String

            /// Path the rows for this source will be written to.
            /// Convention: `<baseDirectory>/<destinationDescriptorID>.db`.
            public let destinationDBPath: URL

            /// Estimated row count (read from `SELECT COUNT(*) FROM
            /// docs_metadata WHERE source = ?` during planning).
            public let estimatedRowCount: Int

            public init(
                sourceID: String,
                destinationDescriptorID: String,
                destinationDBPath: URL,
                estimatedRowCount: Int
            ) {
                self.sourceID = sourceID
                self.destinationDescriptorID = destinationDescriptorID
                self.destinationDBPath = destinationDBPath
                self.estimatedRowCount = estimatedRowCount
            }
        }

        /// Full migration plan: legacy file + one SourcePlan per
        /// distinct source-id in the legacy DB + the target rename
        /// destination for the legacy file.
        public struct MigrationPlan: Sendable, Equatable {
            public let legacyFile: URL
            public let sourcePlans: [SourcePlan]
            public let legacyRenameTarget: URL

            public init(
                legacyFile: URL,
                sourcePlans: [SourcePlan],
                legacyRenameTarget: URL
            ) {
                self.legacyFile = legacyFile
                self.sourcePlans = sourcePlans
                self.legacyRenameTarget = legacyRenameTarget
            }

            /// Sum of `estimatedRowCount` across all source plans.
            public var totalEstimatedRows: Int {
                sourcePlans.reduce(0) { $0 + $1.estimatedRowCount }
            }
        }

        /// Outcome of a completed migration run: one entry per source
        /// describing the actual row count written + the destination
        /// file path + bytes written.
        public struct MigrationOutcome: Sendable, Equatable {
            public struct SourceResult: Sendable, Equatable {
                public let sourceID: String
                public let destinationDBPath: URL
                public let rowsWritten: Int
                public let bytesWritten: Int64

                public init(
                    sourceID: String,
                    destinationDBPath: URL,
                    rowsWritten: Int,
                    bytesWritten: Int64
                ) {
                    self.sourceID = sourceID
                    self.destinationDBPath = destinationDBPath
                    self.rowsWritten = rowsWritten
                    self.bytesWritten = bytesWritten
                }
            }

            public let plan: MigrationPlan
            public let results: [SourceResult]

            /// `true` when the migrator successfully renamed
            /// `search.db` → `search.db.legacy-pre-per-source-split`
            /// after all per-source row-copies completed and verified.
            /// `false` when the rename step was skipped (dry-run mode)
            /// or aborted (rowCountMismatch before the rename ran).
            public let legacyFileRenamed: Bool

            /// The actual on-disk URL the legacy file was renamed to,
            /// when `legacyFileRenamed == true`. **Invariant**:
            /// non-nil iff `legacyFileRenamed == true`; nil iff
            /// `legacyFileRenamed == false`. Callers can force-unwrap
            /// when they have verified `legacyFileRenamed`.
            public let actualLegacyRenameTarget: URL?

            public init(
                plan: MigrationPlan,
                results: [SourceResult],
                legacyFileRenamed: Bool,
                actualLegacyRenameTarget: URL?
            ) {
                self.plan = plan
                self.results = results
                self.legacyFileRenamed = legacyFileRenamed
                self.actualLegacyRenameTarget = actualLegacyRenameTarget
            }

            public var totalRowsWritten: Int {
                results.reduce(0) { $0 + $1.rowsWritten }
            }
        }

        public enum MigrationError: Error, Sendable, Equatable {
            /// The legacy file is malformed (missing `docs_metadata`
            /// table, missing `source` column, schema mismatch). Shim
            /// refuses to run.
            case legacyFileMalformed(URL, reason: String)

            /// A source-id appears in `docs_metadata.source` that the
            /// supplied `SourceLookup` does not recognise. Per-row
            /// behavior: rows for unknown sources are LEFT BEHIND in
            /// the renamed legacy file (`search.db.legacy-pre-per-source-split`).
            /// The bytes are preserved on disk for forensic inspection
            /// but the production read path does NOT consult the
            /// renamed file, so those rows are effectively unreachable
            /// to `cupertino search`. The migration completes for
            /// known sources only. This case wraps the unknown-source
            /// list so callers can surface an actionable warning
            /// (e.g. "your bundle has 12 rows tagged 'experimental-x'
            /// that won't appear in search post-upgrade; if you need
            /// them, downgrade to v1.2.x or file an issue with the
            /// source-id list").
            case unknownSourceIDs([String])

            /// Verification step (post-copy row-count compare) detected
            /// a mismatch. The migration is aborted and the legacy file
            /// is NOT renamed; per-source DBs may be in a partial state
            /// and should be deleted before retry.
            case rowCountMismatch(sourceID: String, expected: Int, actual: Int)
        }

        // MARK: - Constants

        /// Suffix applied to the legacy `search.db` file once migration
        /// completes successfully. The renamed file is preserved for
        /// one release (until v1.4.x cleanup) for forensic inspection
        /// + manual rollback.
        public static let legacyRenameSuffix = ".legacy-pre-per-source-split"

        // MARK: - Detection (step 6a)

        /// Inspect the candidate base directory and decide whether a
        /// per-source DB split migration is needed. Pure read-only:
        /// does NOT touch any file.
        ///
        /// **Registry-derived split destinations.** The migrator
        /// derives the list of split destinations from `registry`
        /// itself: every `destinationDB` declared by an enabled
        /// provider, MINUS `.packages` (its own pipeline) and
        /// `.search` (legacy descriptor; the split's SOURCE not a
        /// destination). Callers do NOT enumerate filenames; the
        /// registry is the single source of truth. If you add a new
        /// source whose destinationDB is a fresh DB, that DB's
        /// filename automatically joins the detection set.
        ///
        /// The detection rule:
        ///   1. If `<baseDirectory>/search.db` does not exist → `noLegacyDBFound`
        ///   2. If `<baseDirectory>/search.db` exists AND any of the
        ///      registry-derived split DBs exists with non-zero size
        ///      → `alreadyMigrated`
        ///   3. If `<baseDirectory>/search.db` exists AND no split DBs
        ///      are present → `migrationNeeded`
        ///   4. If `<baseDirectory>/search.db` exists but its schema is
        ///      malformed → `legacyFileMalformed`
        ///
        /// Step 6a stub: implements 1-3 via filesystem checks only.
        /// Schema validation (case 4) lands in step 6b once the row-
        /// copy implementation also touches the legacy DB's table
        /// metadata.
        public static func detect(
            inBaseDirectory baseDirectory: URL,
            registry: Search.SourceRegistry
        ) -> DetectionOutcome {
            let fileManager = FileManager.default
            let legacyFile = baseDirectory.appendingPathComponent(
                Shared.Constants.FileName.searchDatabase
            )

            guard fileManager.fileExists(atPath: legacyFile.path) else {
                return .noLegacyDBFound
            }

            // Registry-derived: every destination DB declared by an
            // enabled provider, excluding .packages (its own pipeline)
            // and .search (the legacy SOURCE, not a split destination).
            let splitDestinations = registry.groupedByDestinationDB(
                excluding: [.packages, .search]
            ).keys

            let splitFiles: [URL] = splitDestinations
                .map { baseDirectory.appendingPathComponent($0.filename) }
                .filter { fileManager.fileExists(atPath: $0.path) }
                .filter {
                    let attrs = try? fileManager.attributesOfItem(atPath: $0.path)
                    let size = (attrs?[.size] as? Int64) ?? 0
                    return size > 0
                }

            if !splitFiles.isEmpty {
                return .alreadyMigrated(legacyFile: legacyFile, splitFiles: splitFiles)
            }

            return .migrationNeeded(legacyFile: legacyFile)
        }

        // MARK: - Plan derivation (step 6b lands the implementation)

        /// Read the legacy DB's `docs_metadata.source` column, group by
        /// source-id + count, and derive a `MigrationPlan` mapping each
        /// source-id to its destination descriptor's DB file.
        ///
        /// **Registry-derived**: callers pass only the legacy source-id
        /// row counts (the part 6b reads from
        /// `SELECT source, COUNT(*) FROM docs_metadata GROUP BY source`).
        /// The migrator resolves each source-id to its destination
        /// descriptor via the registry. Source-ids the registry does
        /// not recognise are returned in the plan with a nil destination
        /// (callers surface as `MigrationError.unknownSourceIDs`); the
        /// migrator does NOT silently route them anywhere.
        ///
        /// Step 6a stub: takes `legacySourceIDRowCounts` as data. Step
        /// 6b replaces the data argument with the real SQL query that
        /// reads the counts from the legacy DB.
        public static func planFromLegacySourceIDCounts(
            legacyFile: URL,
            baseDirectory: URL,
            registry: Search.SourceRegistry,
            legacySourceIDRowCounts: [String: Int]
        ) -> MigrationPlan {
            let sourcePlans: [SourcePlan] = legacySourceIDRowCounts
                .sorted { $0.key < $1.key }
                .compactMap { sourceID, rowCount in
                    guard let provider = registry.entry(for: sourceID)?.provider else {
                        return nil
                    }
                    let descriptor = provider.destinationDB
                    return SourcePlan(
                        sourceID: sourceID,
                        destinationDescriptorID: descriptor.id,
                        destinationDBPath: baseDirectory.appendingPathComponent(descriptor.filename),
                        estimatedRowCount: rowCount
                    )
                }
            let renameTarget = legacyFile.appendingPathExtension(
                String(legacyRenameSuffix.dropFirst())
            )
            return MigrationPlan(
                legacyFile: legacyFile,
                sourcePlans: sourcePlans,
                legacyRenameTarget: renameTarget
            )
        }
    }
}
