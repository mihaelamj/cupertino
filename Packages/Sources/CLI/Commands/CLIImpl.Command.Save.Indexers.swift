import AppleArchiveSource
import AppleConstraintsKit
import AppleConstraintsPass
import AppleDocsSource
import CoreJSONParser
import CoreProtocols
import CoreSampleCode
import Enrichment
import EnrichmentModels
import Foundation
import HierarchyPass
import HIGSource
import Indexer
import Logging
import LoggingModels
import PackagesAppleConstraintsPass
import PackagesAppleImportsPass
import SampleCodeSource
import SampleIndex
import SampleIndexSQLite
import SamplesAppleConstraintsPass
import SearchAPI
import SearchModels
import SearchSQLite
import SharedConstants
import SwiftBookSource
import SwiftEvolutionSource
import SwiftOrgSource
import SynonymsPass

// MARK: - Indexer dispatch + progress rendering (#244)

/// Per-source indexer dispatchers split out of `CLIImpl.Command.Save.swift` so the
/// struct body stays under SwiftLint's `type_body_length` 300-line
/// ceiling. Each dispatcher converts CLI flags into an
/// `Indexer.<X>Service.Request`, runs the service, renders progress
/// events to the terminal, and prints a final summary.
extension CLIImpl.Command.Save {
    // MARK: - Docs

    /// Side-channel that lets the CLI composition layer read the
    /// `Search.ImportDiligenceBreakdown` produced by the docs runner
    /// without smuggling it through `Indexer.DocsService.Outcome` (which
    /// would force `IndexerModels` to import `SearchModels` and violate
    /// the foundation-only seam rule from #536 / per-package-import-contract).
    /// The CLI is the only place that links both targets, so the
    /// breakdown crosses the seam *inside* the composition root.
    final class DocsDiligenceBreakdownCapture: @unchecked Sendable {
        var breakdown: Search.ImportDiligenceBreakdown = .zero
    }

    /// Sibling side-channel for the #588 per-doc audit log path
    /// (`Search.JSONLImportLogSink`'s output file). Same composition-
    /// root-only pattern as `DocsDiligenceBreakdownCapture` — keeps
    /// `IndexerModels` dep-free.
    final class DocsImportLogPathCapture: @unchecked Sendable {
        var path: URL?
    }

    // swiftlint:disable:next function_body_length
    func runDocsIndexer(effectiveBase: URL, selectedSourceIDs: Set<String>?) async throws {
        // Resolve searchDB destination. In --dry-run, route writes to a
        // throwaway temp file so the existing on-disk search.db is
        // untouched; the temp file is deleted after the run regardless of
        // outcome. Same code path otherwise, so the dry-run is a
        // faithful preview of what a real save would produce.
        let actualSearchDB: URL
        let isDryRun = dryRun
        if isDryRun {
            let name = "cupertino-dryrun-\(UUID().uuidString).db"
            actualSearchDB = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
            Cupertino.Context.composition.logging.recording.info(
                "🧪 Dry-run: writing to throwaway \(actualSearchDB.path)"
            )
        } else if let userPath = searchDB {
            actualSearchDB = URL(fileURLWithPath: userPath).expandingTildeInPath
        } else {
            actualSearchDB = effectiveBase.appendingPathComponent(Shared.Constants.FileName.searchDatabase)
        }

        // #673 Phase G — sidecar-rename for crash safety. When --clear
        // is set, the runner would otherwise truncate the existing DB
        // before writing new data; kill -9 mid-save leaves the original
        // empty / partial. Writing to <db>.in-flight and atomic-renaming
        // on success means the original DB stays intact through any
        // mid-save crash. SQLite WAL already covers in-place transaction
        // atomicity for non-clear saves; sidecar mode is only needed
        // for --clear's full-wipe semantics.
        //
        // Dry-run already routes to a throwaway path; sidecar adds no
        // value there (the user explicitly asked for a temp DB).
        //
        // #1062: post-#1036 per-source-DB-split saves write directly to
        // `<base>/<destinationDB.filename>` per source, never touching
        // `actualSearchDB` / the sidecar. Skip the sidecar setup + log
        // entirely for per-source saves (the common case post-#1036)
        // so the misleading `🛡️ writing to search.db.in-flight` line
        // doesn't appear when the actual write target is e.g. hig.db.
        // The legacy `--all` no-selection path keeps sidecar mode for
        // any future code that still routes through search.db. A
        // deeper refactor that creates per-destination-DB sidecars is
        // tracked as the proper #1062 close-out.
        let resolvedSearchDB: URL
        let sidecarPath: URL?
        let perSourceSave = !(selectedSourceIDs?.isEmpty ?? true)
        if clear, !isDryRun, !perSourceSave {
            let sidecar = actualSearchDB.appendingPathExtension("in-flight")
            // Clean up any orphan sidecar from a prior crashed save.
            // .in-flight files should never persist between runs; if
            // we find one, it means a previous save was killed before
            // it could rename. Log + remove so the new save starts clean.
            Self.cleanUpOrphanSidecar(at: sidecar)
            resolvedSearchDB = sidecar
            sidecarPath = sidecar
            Cupertino.Context.composition.logging.recording.info(
                "🛡️  Sidecar mode (#673 Phase G): writing to \(sidecar.lastPathComponent) — original DB stays intact until atomic-rename on success"
            )
        } else {
            resolvedSearchDB = actualSearchDB
            sidecarPath = nil
        }

        Cupertino.Context.composition.logging.recording.info("🔨 Building Search Index\n")

        // #1045 Gap 4 wiring: build per-source dir map from the
        // production source registry. Production call site uses
        // `CLIImpl.makeDocsIndexingDirectoryByKey(...)` so the
        // assembly logic is single-sourced + behavioural tests can
        // exercise it directly.
        //
        // CLI-flag overrides (`--docs-dir` / `--evolution-dir` /
        // `--swift-org-dir` / `--archive-dir`) layer in here so the
        // dict path honours user-supplied paths. Pre-fix the dict
        // ALWAYS won (registry-default value); user overrides on
        // typed fields were silently dropped by `resolveSourceDirectory`'s
        // dict-first lookup. Post-fix overrides win in the dict
        // itself, so the precedence is correct + the typed fields
        // become redundant (kept on the Input struct for back-compat
        // pending #1052/#1053 cleanup).
        let savePaths = Shared.Paths(baseDirectory: effectiveBase)
        let cliOverrides: [String: URL?] = [
            Shared.Constants.SourcePrefix.appleDocs:
                docsDir.map { URL(fileURLWithPath: $0).expandingTildeInPath },
            Shared.Constants.SourcePrefix.swiftEvolution:
                evolutionDir.map { URL(fileURLWithPath: $0).expandingTildeInPath },
            Shared.Constants.SourcePrefix.swiftOrg:
                swiftOrgDir.map { URL(fileURLWithPath: $0).expandingTildeInPath },
            Shared.Constants.SourcePrefix.appleArchive:
                archiveDir.map { URL(fileURLWithPath: $0).expandingTildeInPath },
        ]
        let saveDirectoryByKey = CLIImpl.makeDocsIndexingDirectoryByKey(
            registry: CLIImpl.makeProductionSourceRegistry(),
            paths: savePaths,
            overrides: cliOverrides
        )

        let request = Indexer.DocsService.Request(
            baseDir: effectiveBase,
            docsDir: docsDir.map { URL(fileURLWithPath: $0).expandingTildeInPath },
            evolutionDir: evolutionDir.map { URL(fileURLWithPath: $0).expandingTildeInPath },
            swiftOrgDir: swiftOrgDir.map { URL(fileURLWithPath: $0).expandingTildeInPath },
            archiveDir: archiveDir.map { URL(fileURLWithPath: $0).expandingTildeInPath },
            higDir: nil,
            searchDB: resolvedSearchDB,
            clear: clear,
            directoryByKey: saveDirectoryByKey,
            // #1059: thread the selection through so DocsService gates
            // its optional-dir presence-check info lines by source-id.
            selectedSourceIDs: selectedSourceIDs,
            // 2026-05-27: pass `--allow-degraded-enrichment` so the
            // runner can hard-fail on missing apple-constraints.json
            // unless the user opts out explicitly.
            allowDegradedEnrichment: allowDegradedEnrichment
        )

        // Path-DI composition sub-root (#535): catalog actor takes
        // the resolved sample-code directory at construction.
        let sampleCatalogActor = Sample.Core.Catalog(
            sampleCodeDirectory: Shared.Paths.live().sampleCodeDirectory
        )

        let tracker = ProgressTracker()
        let breakdownCapture = DocsDiligenceBreakdownCapture()
        let logPathCapture = DocsImportLogPathCapture()
        let outcome: Indexer.DocsService.Outcome
        do {
            outcome = try await Indexer.DocsService.run(
                request,
                markdownStrategy: LiveMarkdownToStructuredPageStrategy(),
                sampleCatalogProvider: LiveSampleCatalogProvider(catalog: sampleCatalogActor),
                docsIndexingRunner: LiveDocsIndexingRunner(
                    breakdownCapture: breakdownCapture,
                    logPathCapture: logPathCapture,
                    selectedSourceIDs: selectedSourceIDs
                ),
                events: DocsEventObserver(tracker: tracker)
            )
        } catch {
            if isDryRun {
                try? FileManager.default.removeItem(at: resolvedSearchDB)
            }
            // #673 Phase G — on failure, leave the sidecar in place for
            // forensic inspection. It'll be cleaned up at the start of
            // the next save (or by the user manually). The original DB
            // is untouched because we never wrote to it.
            if let sidecarPath {
                Cupertino.Context.composition.logging.recording.error(
                    "❌ Save failed; sidecar preserved at \(sidecarPath.path) for inspection. " +
                        "Original DB at \(actualSearchDB.path) is intact. " +
                        "Re-run `cupertino save --clear` to retry."
                )
            }
            throw error
        }
        Self.printDocsSummary(
            outcome: outcome,
            selectedSourceIDs: selectedSourceIDs ?? [],
            baseDirectory: effectiveBase,
            breakdown: breakdownCapture.breakdown,
            importLogPath: logPathCapture.path
        )

        // #673 Phase G — atomic-rename the sidecar over the original.
        // FileManager.replaceItem is the right primitive on Darwin: it's
        // atomic when both items are on the same volume (always true
        // here — sidecar is `<actual>.in-flight` in the same directory).
        // The rename swap also handles SQLite's WAL/SHM files implicitly
        // because Search.Index disconnects cleanly inside DocsService.run
        // before returning (WAL checkpoints into the main file on close).
        //
        // 2026-05-27 (#1062): post-#1036 per-source DB split the runner
        // writes directly to `<base>/<destinationDB.filename>` per
        // source and never touches `searchDBURL` (the sidecar path).
        // The sidecar at `<base>/search.db.in-flight` is therefore not
        // created by the run; attempting the rename throws "file
        // doesn't exist" after a successful save. Gate the rename on
        // sidecar existence so per-source saves complete cleanly. The
        // legacy bucket-tier search.db path (if any future code path
        // re-introduces it) still gets the atomic-rename treatment.
        // A deeper refactor that creates per-destination-DB sidecars
        // is tracked as the proper #1062 close-out.
        if let sidecarPath, !isDryRun {
            if FileManager.default.fileExists(atPath: sidecarPath.path) {
                try Self.atomicReplaceWithSidecar(actual: actualSearchDB, sidecar: sidecarPath)
                Cupertino.Context.composition.logging.recording.info(
                    "✅ Sidecar atomic-renamed to \(actualSearchDB.lastPathComponent) (#673 Phase G crash-safety)"
                )
            }
            // No `else` branch with a log line — the post-#1036 per-source
            // path is the common case now; logging on every save would be
            // noise. The sidecar's crash-protection guarantee is silently
            // degraded for per-source DBs until #1062's proper close.
        }
        if isDryRun {
            try? FileManager.default.removeItem(at: resolvedSearchDB)
            // Clean up the audit log alongside the temp DB so dry-runs
            // don't strew JSONL files in $TMPDIR. If the user wants to
            // inspect the audit trail, they re-run without --dry-run
            // against a real base-dir (the JSONL lives next to search.db
            // there and persists).
            if let logPath = logPathCapture.path {
                try? FileManager.default.removeItem(at: logPath)
            }
            Cupertino.Context.composition.logging.recording.info(
                "🧪 Dry-run complete: throwaway DB + audit log deleted (\(resolvedSearchDB.lastPathComponent))"
            )
        }
    }

    /// Closure-free GoF Observer for `Indexer.DocsService` lifecycle
    /// events. Holds the shared `ProgressTracker` reference and routes
    /// each event into the existing `handleDocsEvent` static dispatcher.
    /// Replaces the trailing-closure pattern at the call site.
    private struct DocsEventObserver: Indexer.DocsService.EventObserving {
        let tracker: ProgressTracker

        func observe(event: Indexer.DocsService.Event) {
            CLIImpl.Command.Save.handleDocsEvent(event, tracker: tracker)
        }
    }

    /// Concrete `Search.DocsIndexingRunner` (GoF Strategy) used by
    /// `Indexer.DocsService`. Wraps `Search.Index` + `Search.IndexBuilder`.
    /// Lives at the CLI composition root so Indexer doesn't need
    /// `import SearchAPI` for these actor types.
    ///
    /// Post-Observer-protocol cleanup: this runner is now closure-free.
    /// The `progress: any Search.IndexingProgressReporting` value
    /// flows straight through from `Indexer.DocsService` to
    /// `Search.IndexBuilder.buildIndex` with no adapter struct in
    /// between. The closure-to-protocol bridge now lives one layer
    /// up at `Indexer.DocsService.HandlerProgressReporter`.
    struct LiveDocsIndexingRunner: Search.DocsIndexingRunner {
        let breakdownCapture: DocsDiligenceBreakdownCapture
        /// Side-channel where the runner stashes the per-doc audit log
        /// path so `runDocsIndexer` can surface it in the final report
        /// after `Indexer.DocsService.run` returns. Same pattern as
        /// `breakdownCapture`; keeps `IndexerModels` dep-free.
        let logPathCapture: DocsImportLogPathCapture

        /// Per-source-id filter for the docs runner's group fan-out.
        /// When non-nil, only DB groups whose providers include at
        /// least one matching `definition.id` are built; the rest are
        /// skipped. When nil, every group fires (backward compat with
        /// the pre-#1037 bucket-level dispatch).
        ///
        /// **View-source co-location is preserved**: filtering selects
        /// DESTINATIONS, not individual providers within a destination.
        /// If `selectedSourceIDs = ["swift-org"]`, the swift-documentation
        /// destination is in scope, and BOTH SwiftOrgSource and
        /// SwiftBookSource run against it (they share a DB by design
        /// per the view-source pattern in
        /// `docs/design/corpus-structure.md` §3.5.5). User-direction
        /// settled 2026-05-25: "swift-org pulls swift-book (one DB,
        /// one unit)".
        ///
        /// PackagesSource is excluded by `groupedByDestinationDB(
        /// excluding: [.packages])` regardless of the filter; its write
        /// pipeline is the standalone `Indexer.PackagesService`.
        let selectedSourceIDs: Set<String>?

        func run(
            input: Search.DocsIndexingInput,
            progress: any Search.IndexingProgressReporting
        ) async throws -> Search.DocsIndexingOutcome {
            // #588 step 5: open the per-doc JSONL audit log alongside
            // the DB. Path is `<db-parent>/save-<ISO8601>.jsonl` so the
            // audit lives next to whichever DB the run targets
            // (real `~/.cupertino/`, dry-run temp dir, or user override).
            // No nested `.cupertino/`: when the DB is already in
            // `~/.cupertino/`, the JSONL is its sibling rather than a
            // nested grandchild.
            let isoStamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let logURL = input.searchDBPath.deletingLastPathComponent()
                .appendingPathComponent("save-\(isoStamp).jsonl")
            let importLogSink = try? Search.JSONLImportLogSink(path: logURL)
            logPathCapture.path = importLogSink == nil ? nil : logURL

            // Step 5b of per-source-db-split.md: replaces the
            // transitional `destinationDB != .packages` filter with a
            // per-DB fan-out via `Search.SourceRegistry.groupedByDestinationDB`.
            // Each group opens its own `Search.Index` (path derived from
            // its descriptor's filename), builds a per-group indexer
            // dict + strategies list, runs an IndexBuilder against
            // that DB, and contributes its stats to aggregate totals
            // returned at the end. PackagesSource is excluded because
            // its DB is written by the dedicated `Indexer.PackagesService`
            // outside `Search.IndexBuilder` (post-#789).
            //
            // Adding a new source post-step-5b is still one
            // `.register(<X>Source())` line in
            // `CLIImpl.SourceRegistry.swift`; zero edits here.
            let productionRegistry = CLIImpl.makeProductionSourceRegistry()
            let logger = Cupertino.Context.composition.logging.recording
            let baseDirectory = input.searchDBPath.deletingLastPathComponent()

            // Load the authoritative Apple-type constraints once;
            // shared across every per-DB enrichment runner. (#759 iter 3)
            //
            // 2026-05-27: mandatory unless caller passed
            // `--allow-degraded-enrichment`. Pre-fix the missing-file
            // case silently degraded to iter 1+2 (~16% constraint
            // coverage on doc_symbols) instead of iter 3 (~38%). A
            // 9.5-hour Claw mini reindex finished in that degraded
            // state with no warning; we caught it only by manually
            // inspecting the DB after the fact. Now: hard-fail at the
            // start of save so the user notices BEFORE burning 12
            // hours of wall time.
            let constraintsPath = baseDirectory.appendingPathComponent("apple-constraints.json")
            let staticConstraintsLookup: (any Search.StaticConstraintsLookup)? = try {
                guard FileManager.default.fileExists(atPath: constraintsPath.path) else {
                    if input.allowDegradedEnrichment {
                        logger.warning(
                            "apple-constraints.json absent from \(baseDirectory.path). " +
                                "Save proceeding at iter 1+2 enrichment coverage (~16%) per " +
                                "--allow-degraded-enrichment. Without the flag this is a hard error.",
                            category: .search
                        )
                        return nil
                    }
                    throw Search.Error.invalidQuery(
                        "apple-constraints.json missing from \(baseDirectory.path). " +
                            "Without it the constraints enrichment pass silently runs at iter 1+2 " +
                            "(~16% coverage) instead of iter 3 (~38%). Run `cupertino setup` to " +
                            "fetch it, or `cupertino-constraints-gen` to produce it locally. To " +
                            "save anyway with degraded coverage, pass --allow-degraded-enrichment."
                    )
                }
                do {
                    return try AppleConstraintsKit.Table.from(fileURL: constraintsPath)
                } catch {
                    if input.allowDegradedEnrichment {
                        logger.warning(
                            "Failed to load \(constraintsPath.lastPathComponent): \(error). " +
                                "Falling back to iter 1 + iter 2 per --allow-degraded-enrichment.",
                            category: .search
                        )
                        return nil
                    }
                    throw Search.Error.invalidQuery(
                        "Failed to parse \(constraintsPath.lastPathComponent): \(error). " +
                            "Pass --allow-degraded-enrichment to proceed anyway."
                    )
                }
            }()

            // Per-save enrichment audit JSONL writer. Captures
            // pass-start / per-entry / pass-end events across every
            // per-source DB in this run; the user can grep the
            // resulting file to verify the constraints pass actually
            // affected the rows it was supposed to. Lives next to the
            // indexing audit log in the base dir.
            let enrichmentAudit = CLIImpl.LiveEnrichmentAuditWriter(baseDirectory: baseDirectory)
            logger.info(
                "📒 Enrichment audit: \(enrichmentAudit.path.lastPathComponent)",
                category: .search
            )

            // Cross-DB SourceLookup so each per-DB index can resolve
            // any source-id at result-formatting time (a swift-org row
            // reading a swift-evolution-flavored URI still gets the
            // right display name). Built once, shared across groups.
            let sourceLookup = Search.SourceLookup(
                definitions: productionRegistry.allEnabled.map(\.definition)
            )

            let allGroups = productionRegistry.groupedByDestinationDB(excluding: [.packages])

            // Per-source dispatch filter (#1037 follow-up). When
            // `selectedSourceIDs` is non-nil, narrow the groups to only
            // the destinations that contain at least one selected
            // provider — OR a view-source aliased to one of the
            // selected providers (post-#1082 follow-up). The latter
            // rule ensures `cupertino save --source swift-org` also
            // rebuilds `swift-book.db`: swift-book is a view-source
            // over swift-org's corpus, so a fresh swift-org corpus
            // implies a fresh swift-book index too. Leaving the
            // aliased DB stale would surprise the user (they re-
            // crawled but searches against the view-source still
            // return old content).
            //
            // The expanded selection is computed once, up-front, so
            // every consumer of `selectedSourceIDs` downstream
            // (`makeIndexingRunInput`, the strategy compactMap, the
            // disk-preflight estimator) sees the same set.
            let effectiveSelection: Set<String>?
            if let selectedSourceIDs {
                var expanded = selectedSourceIDs
                for provider in productionRegistry.allEnabled {
                    if let alias = provider.corpusDirectoryAlias,
                       selectedSourceIDs.contains(alias) {
                        expanded.insert(provider.definition.id)
                    }
                }
                effectiveSelection = expanded
            } else {
                effectiveSelection = nil
            }

            let groups: [Shared.Models.DatabaseDescriptor: [any Search.SourceProvider]]
            if let effectiveSelection {
                groups = allGroups.filter { _, providers in
                    providers.contains { provider in
                        effectiveSelection.contains(provider.definition.id)
                    }
                }
            } else {
                groups = allGroups
            }
            // Sort by descriptor.id for deterministic build order +
            // stable progress reporting; counts + frameworks + breakdown
            // aggregate across DBs.
            let orderedGroups = groups.sorted { $0.key.id < $1.key.id }

            var aggregateDocCount = 0
            var aggregateFrameworks: Set<String> = []
            var aggregateBreakdown = Search.ImportDiligenceBreakdown.zero

            for (descriptor, providers) in orderedGroups {
                let dbPath = baseDirectory.appendingPathComponent(descriptor.filename)
                let index = try await Search.Index(
                    dbPath: dbPath,
                    logger: logger,
                    indexers: providers.reduce(into: [:]) { dict, provider in
                        dict[provider.definition.id] = provider.makeIndexer()
                    },
                    sourceLookup: sourceLookup
                )

                // Per-DB enrichment runner: passes bind to THIS index;
                // the same `staticConstraintsLookup` table is reused.
                // Each constraint-related pass receives the shared
                // `enrichmentAudit` observer + the per-DB path so the
                // JSONL audit can distinguish events from different DBs
                // in the same save run.
                let dbPathString = dbPath.lastPathComponent
                // 2026-05-27 (#1073): source-specific enrichment is
                // pluggable. The CLI composition root assembles the
                // shared docs-tier passes (synonyms, apple constraints,
                // hierarchy) and then asks each provider for any
                // source-specific passes via
                // `makeSourceSpecificEnrichmentPasses`. The HIG
                // platform-inference pass lives on HIGSource, not on
                // the CLI. Default provider extension returns `[]`.
                // Pluggability invariant: adding a source-specific
                // enrichment pass must not touch this file.
                var passes: [any EnrichmentPass] = [
                    Enrichment.SynonymsPass(searchIndex: index),
                    Enrichment.AppleConstraintsPass(
                        searchIndex: index,
                        lookup: staticConstraintsLookup,
                        audit: enrichmentAudit,
                        dbPath: dbPathString
                    ),
                    Enrichment.HierarchyPass(
                        searchIndex: index,
                        audit: enrichmentAudit,
                        dbPath: dbPathString
                    ),
                ]
                for provider in providers {
                    passes.append(contentsOf: provider.makeSourceSpecificEnrichmentPasses(
                        searchIndex: index,
                        audit: enrichmentAudit,
                        dbPath: dbPathString
                    ))
                }
                let enrichmentRunner: any EnrichmentRunner = Enrichment.LiveRunner(passes: passes)

                // Per-group strategies. compactMap drops providers
                // whose CLI input directory is nil (pre-#1029 shape).
                let strategies: [any Search.SourceIndexingStrategy] = providers
                    .compactMap { provider -> (any Search.SourceIndexingStrategy)? in
                        guard let sourceDir = Self.resolveSourceDirectory(for: provider, input: input) else {
                            return nil
                        }
                        let env = Search.IndexEnvironment(
                            sourceDirectory: sourceDir,
                            logger: logger,
                            markdownStrategy: input.markdownStrategy,
                            importLogSink: importLogSink,
                            sampleCatalogProvider: input.sampleCatalogProvider
                        )
                        return provider.makeStrategy(env: env)
                    }

                let builder = Search.IndexBuilder(
                    searchIndex: index,
                    strategies: strategies,
                    logger: logger,
                    staticConstraintsLookup: staticConstraintsLookup,
                    enrichmentRunner: enrichmentRunner
                )
                try await builder.buildIndex(
                    clearExisting: input.clearExisting,
                    onProgress: progress
                )

                let docCount = try await index.documentCount()
                let frameworks = try await index.listFrameworks()
                let breakdown = await builder.lastBuildStats
                    .map(\.breakdown)
                    .reduce(Search.ImportDiligenceBreakdown.zero, +)

                aggregateDocCount += docCount
                aggregateFrameworks.formUnion(frameworks.keys)
                aggregateBreakdown = aggregateBreakdown + breakdown // swiftlint:disable:this shorthand_operator

                await index.disconnect()
            }

            await importLogSink?.close()
            breakdownCapture.breakdown = aggregateBreakdown

            return Search.DocsIndexingOutcome(
                documentCount: aggregateDocCount,
                frameworkCount: aggregateFrameworks.count,
                breakdown: aggregateBreakdown
            )
        }

        // MARK: - Phase 1I.c.1 source-directory resolution helper

        /// Bridge between the per-field `Search.DocsIndexingInput`
        /// (docsDirectory / evolutionDirectory / swiftOrgDirectory /
        /// archiveDirectory / higDirectory) and the post-#1029
        /// registry-driven strategies-list assembly. Maps each
        /// provider's source-id to the matching optional input
        /// directory. Returns `nil` when the CLI input did not supply
        /// a directory for the source, which causes the compactMap
        /// at the call site to skip that source's strategy (mirrors
        /// the pre-#1029 conditional-append shape).
        ///
        /// The switch is intentional bridge code: it pairs the legacy
        /// per-field input struct shape with the registry-driven
        /// dispatch. When `Search.DocsIndexingInput` is redesigned to
        /// a sourceID-keyed dict (separate follow-up), this switch
        /// dissolves entirely.
        ///
        /// SampleCodeSource receives a sentinel `/dev/null` URL —
        /// its strategy consumes `env.sampleCatalogProvider` instead
        /// of reading the directory, but must still appear in the
        /// strategies list so the dispatch stays uniform.
        ///
        /// SwiftBookSource (post-#1082 follow-up) is no longer a
        /// sentinel: it resolves to swift-org's directory via the
        /// `corpusDirectoryAlias` propagation in
        /// `makeDocsIndexingDirectoryByKey`. Its strategy walks the
        /// real corpus tree and emits swift-book-tagged pages.
        static func resolveSourceDirectory(
            for provider: any Search.SourceProvider,
            input: Search.DocsIndexingInput
        ) -> URL? {
            // #1045 Gap 4: registry-supplied dict wins. The Save
            // composition site populates `input.directoryByKey` from
            // `provider.fetchInfo?.outputDir` (with corpus-alias
            // inheritance for view-sources, #1082) for every
            // registered provider, so a NEW source's directory
            // resolves here without touching this resolver.
            //
            // The `requiresCorpusDirectory` fallthrough remains for
            // alternate-input sources (today: SampleCodeSource) that
            // don't read a directory at all. View-sources go through
            // the dict via `corpusDirectoryAlias`, not the sentinel.
            let sourceID = provider.definition.id
            if let mapped = input.directoryByKey[sourceID], let url = mapped {
                return url
            }
            guard provider.requiresCorpusDirectory else {
                return URL(fileURLWithPath: "/dev/null")
            }
            return nil
        }
    }

    // MARK: - Markdown strategy adapter

    /// Concrete `Search.MarkdownToStructuredPageStrategy` (GoF Strategy)
    /// wrapping the `Core.JSONParser.MarkdownToStructuredPage.convert`
    /// static method. Lives at the CLI composition root so neither
    /// Search nor Indexer needs to import `CoreJSONParser` —
    /// the SearchAPI target sees only the protocol from SearchModels.
    struct LiveMarkdownToStructuredPageStrategy: Search.MarkdownToStructuredPageStrategy {
        func convert(markdown: String, url: URL?) -> Shared.Models.StructuredDocumentationPage? {
            Core.JSONParser.MarkdownToStructuredPage.convert(markdown, url: url)
        }
    }

    // MARK: - Sample catalog adapter

    /// Concrete `Search.SampleCatalogProvider` (GoF Strategy) that
    /// bridges `Sample.Core.Catalog` (a per-install actor, post-#535)
    /// to the catalog-state shape the Search `SampleCodeStrategy`
    /// reads. Lives at the CLI composition root so neither Search nor
    /// Indexer needs to import `CoreSampleCode`.
    struct LiveSampleCatalogProvider: Search.SampleCatalogProvider {
        let catalog: Sample.Core.Catalog

        func fetch() async -> Search.SampleCatalogState {
            let entries = await catalog.allEntries
            let loaded = await catalog.loadedSource ?? .missing
            switch loaded {
            case .onDisk:
                let mapped = entries.map { entry in
                    Search.SampleCatalogEntry(
                        title: entry.title,
                        url: entry.url,
                        framework: entry.framework,
                        description: entry.description,
                        zipFilename: entry.zipFilename,
                        webURL: entry.webURL
                    )
                }
                return .loaded(entries: mapped)
            case .missing:
                let path = Shared.Paths.live().sampleCodeDirectory
                    .appendingPathComponent(Sample.Core.Catalog.onDiskCatalogFilename)
                    .path
                return .missing(onDiskPath: path)
            }
        }
    }

    static func handleDocsEvent(
        _ event: Indexer.DocsService.Event,
        tracker: ProgressTracker
    ) {
        switch event {
        case .databaseTarget(let url):
            Cupertino.Context.composition.logging.recording.info("💾 Output: \(url.path)")
        case .removingExistingDB:
            Cupertino.Context.composition.logging.recording.info("🗑️  Removing existing database for clean re-index...")
        case .initializingIndex:
            Cupertino.Context.composition.logging.recording.info("🗄️  Initializing search database...")
        case .missingOptionalSource(let label, let url):
            Cupertino.Context.composition.logging.recording.info("ℹ️  \(label) directory not found at \(url.path), skipping")
        case .foundOptionalSource(let label, let url):
            Cupertino.Context.composition.logging.recording.info("✅ \(label) directory found at \(url.path)")
        case .availabilityMissing:
            Cupertino.Context.composition.logging.recording.info("")
            Cupertino.Context.composition.logging.recording.info("⚠️  Docs don't have availability data yet")
            Cupertino.Context.composition.logging.recording.info("   Run 'cupertino fetch --source availability' first for best results")
            Cupertino.Context.composition.logging.recording.info("")
        case .progress(let processed, let total, let percent):
            if percent - tracker.lastPercent >= 5.0 {
                Cupertino.Context.composition.logging.recording.output(
                    "   \(String(format: "%.0f%%", percent)) complete (\(processed)/\(total))"
                )
                tracker.lastPercent = percent
            }
        case .finished:
            break
        }
    }

    static func printDocsSummary(
        outcome: Indexer.DocsService.Outcome,
        selectedSourceIDs: Set<String>,
        baseDirectory: URL,
        breakdown: Search.ImportDiligenceBreakdown = .zero,
        importLogPath: URL? = nil
    ) {
        let recording = Cupertino.Context.composition.logging.recording
        recording.output("")
        recording.info("✅ Search index built successfully!")
        recording.info("   Total documents: \(outcome.documentCount)")
        recording.info("   Frameworks: \(outcome.frameworkCount)")

        // #1047: post-#1036 each source writes to its OWN per-source DB
        // (apple-documentation.db / hig.db / etc.), not the legacy
        // monolithic search.db that `outcome.searchDBPath` still names.
        // Derive the actual destinations from the registry + the
        // selected source-ids. For `--all` we list every registered
        // source's destination DB; for `--source <id>` we list only
        // that one. Both cases print the actual file the save wrote.
        //
        // Mirror the docs runner's own scope (line ~323 in this file):
        // `groupedByDestinationDB(excluding: [.packages])`. Packages have
        // their own separate `runPackagesIndexer` pipeline that writes
        // packages.db; the docs summary must not claim authorship of
        // that file even when `--all` puts "packages" in `selectedSourceIDs`.
        let registry = CLIImpl.makeProductionSourceRegistry()
        let dbFilenames: [String] = Array(
            Set(
                registry.allEnabled
                    .filter { selectedSourceIDs.contains($0.definition.id) }
                    .filter { $0.destinationDB != .packages }
                    .map(\.destinationDB.filename)
            )
        ).sorted()
        if dbFilenames.isEmpty {
            // Defensive: an empty selectedSourceIDs (or one with no
            // registered match) should never reach here, but fall back
            // to the legacy outcome.searchDBPath so the summary stays
            // non-empty rather than silently dropping the line.
            recording.info("   Database: \(outcome.searchDBPath.path)")
            recording.info("   Size: \(CLIImpl.Command.Save.formatFileSize(outcome.searchDBPath))")
        } else if dbFilenames.count == 1 {
            let path = baseDirectory.appendingPathComponent(dbFilenames[0])
            recording.info("   Database: \(path.path)")
            recording.info("   Size: \(CLIImpl.Command.Save.formatFileSize(path))")
        } else {
            recording.info("   Databases (\(dbFilenames.count) in \(baseDirectory.path)):")
            for filename in dbFilenames {
                let path = baseDirectory.appendingPathComponent(filename)
                recording.info("     - \(filename) (\(CLIImpl.Command.Save.formatFileSize(path)))")
            }
        }

        // #588 import-diligence breakdown.
        // Print the block whenever apple-docs ran (signalled by a
        // non-nil audit log path) OR any counter fired. Non-apple-docs
        // and pre-#588 builds keep their original summary shape because
        // both signals are empty.
        let breakdownActive = !breakdown.isEmpty || importLogPath != nil
        if breakdownActive {
            recording.output("")
            recording.info("📊 Import diligence (#588):")
            recording.info("   Benign duplicates (tier A, byte-identical):     \(breakdown.benignDupTierA)")
            recording.info("   Benign duplicates (tier B, title-match drift):  \(breakdown.benignDupTierB)")
            let tierCMarker = breakdown.tierCCollisionCount == 0 ? "✓" : "✗"
            recording.info("   Tier-C collisions (must be 0 for DoD):          \(breakdown.tierCCollisionCount) \(tierCMarker)")
            recording.info("   Rejected — HTTP error template (#284):          \(breakdown.rejectedHTTPErrorTemplate)")
            recording.info("   Rejected — JS-disabled fallback (#284):         \(breakdown.rejectedJSFallback)")
            recording.info("   Rejected — placeholder title (#588):            \(breakdown.rejectedPlaceholderTitle)")
            if let logPath = importLogPath {
                recording.info("   Per-doc audit log:                              \(logPath.path)")
            }
            if breakdown.tierCCollisionCount > 0 {
                recording.info("")
                recording.info("⚠️  Tier-C collisions present — see [search] logs above for the offending URIs.")
                recording.info("   docs/PRINCIPLES.md principle 3: work is not done while tier-C > 0.")
            }
        }

        recording.info(
            "\n💡 Tip: Start the MCP server with '\(Shared.Constants.App.commandName) serve' to enable search"
        )
    }

    // MARK: - #597 path resolution helpers

    //
    // Pure, side-effect-free static functions that compose the
    // per-DB output path under a given base directory. Pulling
    // them out so the resolution can be unit-tested against an
    // arbitrary base (e.g. a temp dir from `--base-dir`) without
    // having to invoke the save command end-to-end. The regression
    // these guard against: every callsite must compose its DB
    // path under `effectiveBase`, NEVER under
    // `Shared.Paths.live().baseDirectory` (which always returns
    // ~/.cupertino regardless of --base-dir, the BUG 4 cause).

    /// Resolve the samples.db output path. Pre-#597 this used
    /// `Shared.Paths.live().baseDirectory` and silently rewrote
    /// `~/.cupertino/samples.db` even when `--base-dir` was set.
    static func resolveSamplesDBPath(effectiveBase: URL, override: String?) -> URL {
        if let override {
            return URL(fileURLWithPath: override).expandingTildeInPath
        }
        return Sample.Index.databasePath(baseDirectory: effectiveBase)
    }

    /// Resolve the packages.db output path. Same isolation gap as
    /// `resolveSamplesDBPath` pre-#597.
    static func resolvePackagesDBPath(effectiveBase: URL, override: String?) -> URL {
        if let override {
            return URL(fileURLWithPath: override).expandingTildeInPath
        }
        return effectiveBase.appendingPathComponent(Shared.Constants.FileName.packagesIndexDatabase)
    }

    /// Resolve the search.db output path. Already correct pre-#597
    /// (uses `effectiveBase`); kept here as a sibling so the three
    /// resolvers share one shape and one place for future tests.
    static func resolveSearchDBPath(effectiveBase: URL, override: String?) -> URL {
        if let override {
            return URL(fileURLWithPath: override).expandingTildeInPath
        }
        return effectiveBase.appendingPathComponent(Shared.Constants.FileName.searchDatabase)
    }

    // MARK: - Packages

    func runPackagesIndexerSafely(effectiveBase: URL) async throws {
        let packagesRoot = packagesDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.packages)
        guard FileManager.default.fileExists(atPath: packagesRoot.path) else {
            Cupertino.Context.composition.logging.recording.info(
                "ℹ️  packages directory not found at \(packagesRoot.path) — skipping packages step. "
                    + "Run `cupertino fetch --source packages` first."
            )
            return
        }
        try await runPackagesIndexer(packagesRoot: packagesRoot, effectiveBase: effectiveBase)
    }

    func runPackagesIndexer(packagesRoot: URL, effectiveBase: URL) async throws {
        let packagesDB = Self.resolvePackagesDBPath(effectiveBase: effectiveBase, override: nil)
        let request = Indexer.PackagesService.Request(
            packagesRoot: packagesRoot,
            packagesDB: packagesDB,
            clear: clear
        )

        _ = try await Indexer.PackagesService.run(
            request,
            packageIndexingRunner: LivePackageIndexingRunner(),
            events: PackagesEventObserver()
        )
    }

    /// Closure-free GoF Observer for `Indexer.PackagesService` lifecycle
    /// events. No held state; routes each event into the existing
    /// `handlePackagesEvent` static dispatcher.
    private struct PackagesEventObserver: Indexer.PackagesService.EventObserving {
        func observe(event: Indexer.PackagesService.Event) {
            CLIImpl.Command.Save.handlePackagesEvent(event)
        }
    }

    /// Concrete `Search.PackageIndexingRunner` (GoF Strategy) used by
    /// `Indexer.PackagesService`. Wraps `Search.PackageIndex` +
    /// `Search.PackageIndexer`. Lives at the CLI composition root so
    /// the Indexer SPM target doesn't import `Search` for these types.
    struct LivePackageIndexingRunner: Search.PackageIndexingRunner {
        func run(
            packagesRoot: URL,
            packagesDB: URL,
            progress: any Search.PackageIndexingProgressReporting
        ) async throws -> Search.PackageIndexingOutcome {
            let startedAt = Date()
            let index = try await Search.PackageIndex(dbPath: packagesDB, logger: Cupertino.Context.composition.logging.recording)
            let indexer = Search.PackageIndexer(rootDirectory: packagesRoot, index: index)
            // `Search.PackageIndexer.indexAll` takes the same
            // `Search.PackageIndexingProgressReporting` Observer protocol
            // this method already receives; pass it straight through.
            let stats = try await indexer.indexAll(progress: progress)

            // #837 — postprocessor pipeline for packages.db. Loads
            // the same AppleConstraintsKit table that the docs flow
            // uses (sibling JSON at `<base-dir>/apple-constraints.json`)
            // and runs the two packages-target passes against the
            // freshly indexed DB. If the file is absent the passes
            // become no-ops; the unenriched bundle is still valid.
            let constraintsPath = packagesDB.deletingLastPathComponent()
                .appendingPathComponent("apple-constraints.json")
            let lookup: (any Search.StaticConstraintsLookup)? = {
                guard FileManager.default.fileExists(atPath: constraintsPath.path) else { return nil }
                do {
                    return try AppleConstraintsKit.Table.from(fileURL: constraintsPath)
                } catch {
                    Cupertino.Context.composition.logging.recording.warning(
                        "Packages enrichment skipped, failed to load \(constraintsPath.lastPathComponent): \(error)",
                        category: .search
                    )
                    return nil
                }
            }()
            let runner = Enrichment.LiveRunner(passes: [
                Enrichment.PackagesAppleConstraintsPass(packages: index, lookup: lookup),
                Enrichment.PackagesAppleImportsPass(packages: index, lookup: lookup),
            ])
            let results = try await runner.run(target: .packages)
            for result in results {
                Cupertino.Context.composition.logging.recording.info(
                    "   [enrichment/\(result.passIdentifier)] affected=\(result.rowsAffected) skipped=\(result.rowsSkipped) (\(result.durationMs)ms)",
                    category: .search
                )
            }

            let summary = try await index.summary()
            await index.disconnect()
            return Search.PackageIndexingOutcome(
                packagesIndexed: stats.packagesIndexed,
                packagesFailed: stats.packagesFailed,
                totalFiles: stats.totalFiles,
                totalBytes: stats.totalBytes,
                durationSeconds: Date().timeIntervalSince(startedAt),
                totalPackagesInDB: summary.packageCount,
                totalFilesInDB: summary.fileCount,
                totalBytesInDB: summary.bytesIndexed
            )
        }
    }

    static func handlePackagesEvent(_ event: Indexer.PackagesService.Event) {
        switch event {
        case .starting(let root, let db):
            Cupertino.Context.composition.logging.recording.info("🔨 Indexing packages from \(root.path) into \(db.path)")
        case .removingExistingDB(let url):
            Cupertino.Context.composition.logging.recording.info("🗑️  --clear: removing existing \(url.lastPathComponent)")
        case .progress(let name, let done, let total):
            if done == 1 || done % 10 == 0 || done == total {
                Cupertino.Context.composition.logging.recording.output(String(format: "📊 %d/%d — %@", done, total, name as NSString))
            }
        case .finished(let outcome):
            Self.printPackagesSummary(outcome: outcome)
        }
    }

    static func printPackagesSummary(outcome: Indexer.PackagesService.Outcome) {
        Cupertino.Context.composition.logging.recording.output("")
        Cupertino.Context.composition.logging.recording.info("✅ Package indexing completed")
        Cupertino.Context.composition.logging.recording.info("   Packages indexed this run: \(outcome.packagesIndexed)")
        Cupertino.Context.composition.logging.recording.info("   Packages failed: \(outcome.packagesFailed)")
        Cupertino.Context.composition.logging.recording.info("   Files this run: \(outcome.totalFiles)")
        Cupertino.Context.composition.logging.recording.info("   Bytes this run: \(outcome.totalBytes / 1024) KB")
        Cupertino.Context.composition.logging.recording.info("   Duration: \(Int(outcome.durationSeconds))s")
        Cupertino.Context.composition.logging.recording.info("")
        Cupertino.Context.composition.logging.recording.info("   Total packages in DB: \(outcome.totalPackagesInDB)")
        Cupertino.Context.composition.logging.recording.info("   Total files in DB: \(outcome.totalFilesInDB)")
        Cupertino.Context.composition.logging.recording.info("   Total bytes in DB: \(outcome.totalBytesInDB / 1024) KB")
    }

    // MARK: - Samples

    func runSamplesIndexerSafely(effectiveBase: URL) async throws {
        // #597: derive sample-code + DB paths from the caller's
        // resolved base (i.e. honour --base-dir). Pre-fix this used
        // `Shared.Paths.live().baseDirectory` unconditionally, which
        // hardcodes ~/.cupertino regardless of --base-dir and SILENTLY
        // wrote into live data when users ran isolated-test saves
        // (cupertino-full-coverage-2026-05-15.md BUG 4).
        let sampleCodeURL = samplesDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Sample.Index.sampleCodeDirectory(baseDirectory: effectiveBase)
        guard FileManager.default.fileExists(atPath: sampleCodeURL.path) else {
            Cupertino.Context.composition.logging.recording.info(
                "ℹ️  sample-code directory not found at \(sampleCodeURL.path) — skipping samples step. "
                    + "Run `cupertino fetch --source samples` first."
            )
            return
        }
        try await runSamplesIndexer(sampleCodeURL: sampleCodeURL, effectiveBase: effectiveBase)
    }

    func runSamplesIndexer(sampleCodeURL: URL, effectiveBase: URL) async throws {
        let dbURL = Self.resolveSamplesDBPath(effectiveBase: effectiveBase, override: samplesDB)

        let request = Indexer.SamplesService.Request(
            sampleCodeDir: sampleCodeURL,
            samplesDB: dbURL,
            clear: clear,
            force: force
        )

        let tracker = ProgressTracker()
        _ = try await Indexer.SamplesService.run(
            request,
            samplesIndexingRunner: LiveSamplesIndexingRunner(),
            events: SamplesEventObserver(tracker: tracker)
        )
    }

    /// Closure-free GoF Observer for `Indexer.SamplesService` lifecycle
    /// events. Holds the shared `ProgressTracker` reference and routes
    /// each event into the existing `handleSamplesEvent` static
    /// dispatcher.
    private struct SamplesEventObserver: Indexer.SamplesService.EventObserving {
        let tracker: ProgressTracker

        func observe(event: Indexer.SamplesService.Event) {
            CLIImpl.Command.Save.handleSamplesEvent(event, tracker: tracker)
        }
    }

    /// Concrete `Sample.Index.SamplesIndexingRunner` (GoF Strategy)
    /// used by `Indexer.SamplesService`. Wraps `Sample.Index.Database` +
    /// `Sample.Index.Builder` + `Sample.Core.Catalog`. Lives at the
    /// CLI composition root so the Indexer SPM target doesn't import
    /// SampleIndex or CoreSampleCode for these types.
    ///
    /// Post-Observer-protocol cleanup: this runner receives a typed
    /// `phaseObserver: any Sample.Index.SamplesIndexingPhaseObserving`
    /// from `Indexer.SamplesService`. Lifecycle phase events flow
    /// through `phaseObserver.observe(phase:)`. The progress reporter
    /// for `Sample.Index.Builder.indexAll(progress:)` is an internal
    /// adapter (`PhaseObserverToProgressReporter`) that translates
    /// per-project `IndexProgress` into a `.projectProgress` phase event
    /// and forwards.
    private struct PhaseObserverToProgressReporter: Sample.Index.ProgressReporting {
        let phaseObserver: any Sample.Index.SamplesIndexingPhaseObserving

        func report(progress: Sample.Index.IndexProgress) {
            let phase: Sample.Index.SamplesIndexingPhase.ProgressPhase
            switch progress.status {
            case .extracting: phase = .extracting
            case .indexingFiles: phase = .indexingFiles
            case .completed: phase = .completed
            case .failed: phase = .failed
            }
            phaseObserver.observe(phase: .projectProgress(
                name: progress.currentProject,
                percent: progress.percentComplete,
                phase: phase
            ))
        }
    }

    struct LiveSamplesIndexingRunner: Sample.Index.SamplesIndexingRunner {
        func run(
            input: Sample.Index.SamplesIndexingInput,
            phaseObserver: any Sample.Index.SamplesIndexingPhaseObserving
        ) async throws -> Sample.Index.SamplesIndexingOutcome {
            let database = try await Sample.Index.Database(dbPath: input.samplesDB, logger: Cupertino.Context.composition.logging.recording)
            if input.clear {
                phaseObserver.observe(phase: .clearingExistingIndex)
                try await database.clearAll()
            }

            let existingProjects = try await database.projectCount()
            let existingFiles = try await database.fileCount()
            if existingProjects > 0, !input.force, !input.clear {
                phaseObserver.observe(phase: .existingIndexNotice(projects: existingProjects, files: existingFiles))
            }

            phaseObserver.observe(phase: .loadingCatalog)
            // Path-DI (#535): construct catalog actor with the input's
            // sample-code directory rather than reaching for the singleton.
            let catalog = Sample.Core.Catalog(sampleCodeDirectory: input.sampleCodeDir)
            let catalogEntries = await catalog.allEntries
            phaseObserver.observe(phase: .catalogLoaded(entryCount: catalogEntries.count))

            let entries = catalogEntries.map { entry in
                Sample.Index.SampleCodeEntryInfo(
                    title: entry.title,
                    description: entry.description,
                    frameworks: [entry.framework],
                    webURL: entry.webURL,
                    zipFilename: entry.zipFilename
                )
            }

            phaseObserver.observe(phase: .indexingStart)
            let builder = Sample.Index.Builder(
                database: database,
                sampleCodeDirectory: input.sampleCodeDir
            )

            let startTime = Date()
            let reporter = PhaseObserverToProgressReporter(phaseObserver: phaseObserver)
            let indexed = try await builder.indexAll(
                entries: entries,
                forceReindex: input.force,
                progress: reporter
            )

            // #837 — postprocessor pipeline for samples.db. Same
            // AppleConstraintsKit table the docs + packages flows use.
            let samplesConstraintsPath = input.samplesDB.deletingLastPathComponent()
                .appendingPathComponent("apple-constraints.json")
            let samplesLookup: (any Search.StaticConstraintsLookup)? = {
                guard FileManager.default.fileExists(atPath: samplesConstraintsPath.path) else { return nil }
                do {
                    return try AppleConstraintsKit.Table.from(fileURL: samplesConstraintsPath)
                } catch {
                    Cupertino.Context.composition.logging.recording.warning(
                        "Samples enrichment skipped, failed to load \(samplesConstraintsPath.lastPathComponent): \(error)",
                        category: .search
                    )
                    return nil
                }
            }()
            let samplesRunner = Enrichment.LiveRunner(passes: [
                Enrichment.SamplesAppleConstraintsPass(samples: database, lookup: samplesLookup),
            ])
            let samplesResults = try await samplesRunner.run(target: .samples)
            for result in samplesResults {
                Cupertino.Context.composition.logging.recording.info(
                    "   [enrichment/\(result.passIdentifier)] affected=\(result.rowsAffected) skipped=\(result.rowsSkipped) (\(result.durationMs)ms)",
                    category: .search
                )
            }

            let duration = Date().timeIntervalSince(startTime)

            let finalProjects = try await database.projectCount()
            let finalFiles = try await database.fileCount()
            let finalSymbols = try await database.symbolCount()
            let finalImports = try await database.importCount()

            return Sample.Index.SamplesIndexingOutcome(
                projectsIndexedThisRun: indexed,
                projectsTotal: finalProjects,
                filesTotal: finalFiles,
                symbolsTotal: finalSymbols,
                importsTotal: finalImports,
                durationSeconds: duration
            )
        }
    }

    static func handleSamplesEvent(
        _ event: Indexer.SamplesService.Event,
        tracker: ProgressTracker
    ) {
        switch event {
        case .starting(let dir, let db):
            Cupertino.Context.composition.logging.recording.output("📦 Cupertino - Sample Code Indexer\n")
            Cupertino.Context.composition.logging.recording.output("   Sample code: \(dir.path)")
            Cupertino.Context.composition.logging.recording.output("   Database: \(db.path)")
            Cupertino.Context.composition.logging.recording.output("")
        case .removingExistingDB:
            Cupertino.Context.composition.logging.recording.output("🗑️  Removing existing database for fresh index...")
        case .clearingExistingIndex:
            Cupertino.Context.composition.logging.recording.output("🗑️  Clearing existing index...")
        case .existingIndexNotice(let projects, let files):
            Cupertino.Context.composition.logging.recording.output("ℹ️  Found existing index with \(projects) projects, \(files) files")
            Cupertino.Context.composition.logging.recording.output("   Use --force to reindex all, or --clear to start fresh")
            Cupertino.Context.composition.logging.recording.output("")
        case .loadingCatalog:
            Cupertino.Context.composition.logging.recording.output("📖 Loading sample code catalog...")
        case .catalogLoaded(let count):
            Cupertino.Context.composition.logging.recording.output("   Found \(count) entries in catalog")
        case .indexingStart:
            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.output("📇 Indexing sample code...")
            Cupertino.Context.composition.logging.recording.output("")
        case .projectProgress(let name, let percent, let phase):
            if percent - tracker.lastPercent >= 5.0 || phase == .completed {
                let icon = phaseIcon(phase)
                Cupertino.Context.composition.logging.recording.output("   [\(String(format: "%3.0f%%", percent))] \(icon) \(name)")
                tracker.lastPercent = percent
            }
        case .finished(let outcome):
            Self.printSamplesSummary(outcome: outcome)
        }
    }

    private static func phaseIcon(_ phase: Indexer.SamplesService.Event.Phase) -> String {
        switch phase {
        case .extracting: return "📦"
        case .indexingFiles: return "📝"
        case .completed: return "✅"
        case .failed: return "❌"
        }
    }

    static func printSamplesSummary(outcome: Indexer.SamplesService.Outcome) {
        Cupertino.Context.composition.logging.recording.output("")
        Cupertino.Context.composition.logging.recording.output("✅ Indexing complete!")
        Cupertino.Context.composition.logging.recording.output("")
        Cupertino.Context.composition.logging.recording.output("   Projects indexed: \(outcome.projectsIndexedThisRun)")
        Cupertino.Context.composition.logging.recording.output("   Total projects: \(outcome.projectsTotal)")
        Cupertino.Context.composition.logging.recording.output("   Total files: \(outcome.filesTotal)")
        Cupertino.Context.composition.logging.recording.output("   Symbols extracted: \(outcome.symbolsTotal)")
        Cupertino.Context.composition.logging.recording.output("   Imports captured: \(outcome.importsTotal)")
        Cupertino.Context.composition.logging.recording.output("   Duration: \(Int(outcome.durationSeconds))s")
        Cupertino.Context.composition.logging.recording.output("   Database: \(CLIImpl.Command.Save.formatFileSize(outcome.samplesDBPath))")
    }

    /// Class wrapper so `@Sendable` callbacks can mutate `lastPercent`.
    /// Single-actor concurrency makes this safe in practice.
    final class ProgressTracker: @unchecked Sendable {
        var lastPercent = 0.0
    }

    // MARK: - #673 Phase G — sidecar helpers

    /// Remove an orphan sidecar from a prior crashed save. The
    /// `.in-flight` extension should never persist between runs (a clean
    /// shutdown either renames it over the actual DB or — on failure —
    /// leaves it intentionally for inspection until the next save).
    /// Logging the find + removing it is the right behaviour at the
    /// start of every `--clear` save so the new save isn't surprised
    /// by stale state at the target path.
    ///
    /// Companion sidecar files (SQLite `-wal`, `-shm`, `-journal`) are
    /// also removed so a partially-written sidecar can't leave SQLite
    /// confused when the next save opens its own fresh sidecar.
    static func cleanUpOrphanSidecar(at sidecar: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sidecar.path) else { return }
        let size = (try? fm.attributesOfItem(atPath: sidecar.path)[.size] as? Int64) ?? -1
        let sizeStr = size >= 0
            ? ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            : "unknown size"
        Cupertino.Context.composition.logging.recording.info(
            "🧹 Orphan sidecar detected at \(sidecar.path) (\(sizeStr)) — cleaning up before new save. "
                + "Likely a crashed prior `cupertino save`; original DB at "
                + "\(sidecar.deletingPathExtension().path) is unaffected."
        )
        try? fm.removeItem(at: sidecar)
        // Also remove SQLite companion files if they exist.
        for suffix in ["-wal", "-shm", "-journal"] {
            let companion = URL(fileURLWithPath: sidecar.path + suffix)
            try? fm.removeItem(at: companion)
        }
    }

    /// Atomically replace the actual DB at `actual` with the sidecar at
    /// `sidecar`. Wraps `FileManager.replaceItem(at:withItemAt:...)`
    /// which on Darwin maps to `renameat(2)` when both items are on the
    /// same volume (always true for cupertino's sidecar pattern, since
    /// the sidecar is `<actual>.in-flight` in the same directory).
    ///
    /// Companion SQLite files (`-wal`, `-shm`, `-journal`) are handled
    /// by SQLite itself: the writer disconnected before this method is
    /// called, so the WAL has been checkpointed back into the main DB
    /// file and the companion files are either empty or absent. Any
    /// stale companion files at the actual path get removed before the
    /// replace so SQLite doesn't see mismatched WAL/SHM for the new DB.
    static func atomicReplaceWithSidecar(actual: URL, sidecar: URL) throws {
        let fm = FileManager.default
        // Defensive cleanup of stale companions at the target — a
        // prior in-place save may have left a WAL even after disconnect.
        for suffix in ["-wal", "-shm", "-journal"] {
            let companion = URL(fileURLWithPath: actual.path + suffix)
            try? fm.removeItem(at: companion)
        }
        if fm.fileExists(atPath: actual.path) {
            // `replaceItem` requires the destination to exist OR uses
            // the `withItemAt` flavour; we want unconditional replace.
            _ = try fm.replaceItemAt(actual, withItemAt: sidecar)
        } else {
            // No existing DB to replace — just move the sidecar into place.
            try fm.moveItem(at: sidecar, to: actual)
        }
        // Post-rename cleanup: SQLite's WAL/SHM files were created next
        // to the sidecar (e.g. `search.db.in-flight-wal`); they aren't
        // renamed by `replaceItemAt` because the sidecar is moved by
        // path-not-by-directory. Leaving them in place is harmless
        // (SQLite won't see them under the new `search.db` name) but
        // ugly; remove them so the directory ends up clean.
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecarCompanion = URL(fileURLWithPath: sidecar.path + suffix)
            try? fm.removeItem(at: sidecarCompanion)
        }
    }
}
