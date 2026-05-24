import EnrichmentModels
import Foundation
import LoggingModels
import SearchModels
import SharedConstants

// MARK: - Search Index Builder

extension Search {
    /// Orchestrates a full search index build by iterating an array of ``SourceIndexingStrategy``
    /// implementations, one per documentation source.
    ///
    /// `IndexBuilder` is responsible only for coordination:
    /// - Optionally clearing the existing index before the run.
    /// - Iterating the active strategy array in order.
    /// - Registering framework synonyms after all sources have been indexed.
    /// - Logging the final document count.
    ///
    /// Per-source logic (directory scanning, file parsing, URI construction, availability
    /// look-up) lives entirely in the concrete strategy types (``AppleDocsStrategy``,
    /// ``SwiftEvolutionStrategy``, ``SwiftOrgStrategy``, ``AppleArchiveStrategy``,
    /// ``HIGStrategy``, ``SampleCodeStrategy``). The previous
    /// `SwiftPackagesStrategy` was removed in #789 (single backticks
    /// because the symbol no longer exists; DocC cannot resolve a
    /// double-backtick reference).
    ///
    /// ## Building with the default strategy set
    ///
    /// ```swift
    /// import SearchAPI
    /// import SearchSQLite
    ///
    /// // #933: composition root assembles strategies inline; the
    /// // pre-#933 `Search.makeDefaultStrategies(...)` factory was
    /// // deleted as a Service Locator violation. The 6 strategy
    /// // concretes are appended directly to the array; adding a new
    /// // source = one `strategies.append(...)` here.
    /// let strategies: [any Search.SourceIndexingStrategy] = [
    ///     Search.AppleDocsStrategy(docsDirectory: docsDir, markdownStrategy: markdownStrategy, logger: logger),
    ///     // ... other strategies as needed
    /// ]
    /// let builder = Search.IndexBuilder(
    ///     searchIndex: index,
    ///     strategies: strategies,
    ///     logger: logger
    /// )
    /// try await builder.buildIndex()
    /// ```
    ///
    /// ## Building with a custom strategy array
    ///
    /// ```swift
    /// let builder = Search.IndexBuilder(
    ///     searchIndex: index,
    ///     strategies: [
    ///         Search.AppleDocsStrategy(docsDirectory: docsDir),
    ///         Search.SwiftEvolutionStrategy(evolutionDirectory: evolutionDir),
    ///     ]
    /// )
    /// try await builder.buildIndex()
    /// ```
    public actor IndexBuilder {
        private let searchIndex: any Search.Database & Search.IndexWriter
        private let strategies: [any Search.SourceIndexingStrategy]
        /// GoF Strategy seam for log emission (1994 p. 315).
        private let logger: any LoggingModels.Logging.Recording
        /// #759 iter 3 — authoritative Apple-type generic-constraints
        /// table. nil means the composition root didn't wire one in;
        /// pass 3 becomes a no-op and the build relies on iter 1 +
        /// iter 2 alone.
        private let staticConstraintsLookup: (any Search.StaticConstraintsLookup)?
        /// #837 phase 1B-2 — optional postprocessor pipeline. When non-nil,
        /// `buildIndex` runs `enrichmentRunner.run(target: .search)` after
        /// the strategy loop instead of the three inline pass calls
        /// (registerFrameworkSynonyms, applyAppleStaticConstraints,
        /// propagateConstraintsFromParents). When nil, the inline calls run
        /// as before — keeps existing callers (tests, smoke harnesses)
        /// working without changes. Composition root constructs an
        /// `Enrichment.LiveRunner` and passes it here once #837 lands the
        /// full pipeline.
        private let enrichmentRunner: (any EnrichmentRunner)?

        // MARK: - Designated Initialiser

        /// Create an ``IndexBuilder`` with an explicit strategy array.
        ///
        /// Use this initialiser when you need full control over which sources are indexed
        /// and in what order. For the standard six-source build, call
        /// `Search.makeDefaultStrategies(...)` from the `SearchStrategies` target and
        /// pass its result here.
        ///
        /// - Parameters:
        ///   - searchIndex: An object conforming to both
        ///     ``SearchModels/Search/Database`` and
        ///     ``SearchModels/Search/IndexWriter`` (the production
        ///     conformer is the ``SearchSQLite/Search/Index`` actor, which the
        ///     CLI composition root passes through implicit conformance).
        ///   - strategies: The ordered list of strategies to execute.
        ///   - logger: GoF Strategy seam for log emission.
        ///   - staticConstraintsLookup: Optional authoritative
        ///     constraints table (#759 iter 3). When non-nil, the
        ///     build's pass 3 overrides `generic_constraints` for
        ///     every URI the table covers. Pass nil to fall back to
        ///     iter 1 + iter 2 alone.
        public init(
            searchIndex: any Search.Database & Search.IndexWriter,
            strategies: [any Search.SourceIndexingStrategy],
            logger: any LoggingModels.Logging.Recording,
            staticConstraintsLookup: (any Search.StaticConstraintsLookup)? = nil,
            enrichmentRunner: (any EnrichmentRunner)? = nil
        ) {
            self.searchIndex = searchIndex
            self.strategies = strategies
            self.logger = logger
            self.staticConstraintsLookup = staticConstraintsLookup
            self.enrichmentRunner = enrichmentRunner
        }

        // MARK: - Build

        //
        // The pre-#899 convenience initialiser (`init(searchIndex:metadata:docsDirectory:...)`)
        // that took the source-directory tuple and built strategies inline
        // was removed when the strategies moved to the sibling
        // `SearchStrategies` SPM target. Composition roots now call
        // `Search.makeDefaultStrategies(...)` (from `SearchStrategies`) and
        // pass the resulting array to the primary init above.

        /// Build the search index by running all active strategies in sequence.
        ///
        /// Each strategy receives the same shared composed-protocol value
        /// (``SearchModels/Search/Database`` & ``SearchModels/Search/IndexWriter``)
        /// that was passed to this `IndexBuilder` instance.  Per-item errors
        /// are caught inside each strategy; only unrecoverable failures propagate here.
        ///
        /// After all strategies complete, framework synonyms are registered so that common
        /// alternate names (e.g., `"bluetooth"` → `"corebluetooth"`) resolve correctly.
        ///
        /// - Parameters:
        ///   - clearExisting: When `true` (the default), the index is cleared before any
        ///     strategies run.
        ///   - onProgress: Optional progress callback forwarded to each strategy.
        public func buildIndex(
            clearExisting: Bool = true,
            onProgress: (any Search.IndexingProgressReporting)? = nil
        ) async throws {
            logger.info("🔨 Building search index...", category: .search)

            if clearExisting {
                try await searchIndex.clearIndex()
                logger.info("   Cleared existing index", category: .search)
            }

            var allStats: [Search.IndexStats] = []
            for strategy in strategies {
                // #779 defense-in-depth: per-strategy do/catch so one
                // strategy throwing cannot strand the post-loop enrichment
                // passes (registerFrameworkSynonyms, applyAppleStaticConstraints,
                // propagateConstraintsFromParents). The original #779
                // production crash burned ~11h of apple-docs work because
                // SwiftEvolution threw NSCocoa 256 and the loop aborted
                // before enrichment ran. Even with the optionalDir
                // resolvingSymlinksInPath() composition-root fix, the next
                // undiscovered strategy-level bug should not have the same
                // blast radius.
                do {
                    let stats = try await strategy.indexItems(into: searchIndex, progress: onProgress)
                    allStats.append(stats)
                } catch {
                    logger.error(
                        "❌ Strategy threw: \(error.localizedDescription); skipping this source, enrichment passes will still run",
                        category: .search
                    )
                    allStats.append(IndexStats(
                        source: "<unknown>", // strategy type erased post-throw; best-effort placeholder
                        indexed: 0,
                        skipped: 0,
                        wasSkipped: true,
                        skipReason: "strategy threw: \(error.localizedDescription)"
                    ))
                }
            }

            // #837 phase 1B-2 — postprocessor pipeline. If the composition
            // root injected an `enrichmentRunner`, defer to it for the three
            // enrichment passes (synonyms, constraints, hierarchy). The
            // runner topologically sorts the registered passes and logs
            // per-pass timing/affected counts. If no runner was injected,
            // fall back to the historical inline calls so existing callers
            // (tests, smoke harnesses, downstream binaries that haven't
            // adopted the pipeline yet) keep working unchanged.
            if let enrichmentRunner {
                let results = try await enrichmentRunner.run(target: .search)
                for result in results {
                    logger.info(
                        "   [enrichment/\(result.passIdentifier)] affected=\(result.rowsAffected) skipped=\(result.rowsSkipped) (\(result.durationMs)ms)",
                        category: .search
                    )
                }
            } else {
                try await registerFrameworkSynonyms()

                // #759 iteration 3 — apply the authoritative Apple-type
                // constraints table BEFORE iter 2's hierarchy walk runs,
                // so the walk's parent map reads from the authoritative
                // post-iter-3 state. When `staticConstraintsLookup` is
                // nil (no table wired in at the composition root) the
                // call is a no-op and the build falls back to iter 1 +
                // iter 2 alone.
                if staticConstraintsLookup != nil {
                    let affected = try await searchIndex.applyAppleStaticConstraints(lookup: staticConstraintsLookup)
                    logger.info("   Applied authoritative Apple constraints table (#759 iteration 3): \(affected) rows", category: .search)
                }

                // #755 / #759 iteration 2 — hierarchy walk. Iteration 1's
                // AST extractor captures the constraints declared on each
                // page's own declaration (`<T: View>` inline form +
                // `where T: View` clauses). Iteration 3 (above) overrides
                // those with the authoritative symbolgraph values where
                // available. Iteration 2 here propagates the now-richer
                // parent constraints down to the bare-generic methods
                // (NavigationLink's init whose signature carries
                // `Destination` but no constraint clause inherits the
                // struct's `Destination: View`). Sub-second on the full
                // 351k-row corpus.
                let inherited = try await searchIndex.propagateConstraintsFromParents()
                logger.info("   Inherited generic constraints from parents (#759 iteration 2): \(inherited) rows", category: .search)
            }

            // Log per-source breakdown so operators can diagnose index-build issues
            // without having to re-run with verbose logging.
            //
            // #671 — distinguish "ran and indexed N items" from "skipped because
            // the source's input wasn't available". 99.9% of users don't have a
            // local docs/ directory and see the bundled DB through `cupertino
            // setup`; printing "indexed: 0, skipped: 0" against those sources
            // implies a failed indexing attempt when nothing was attempted.
            for stats in allStats {
                let line: String
                if stats.wasSkipped {
                    let reason = stats.skipReason ?? "no input"
                    line = "   [\(stats.source)] skipped (\(reason))"
                } else {
                    line = "   [\(stats.source)] indexed: \(stats.indexed), skipped: \(stats.skipped)"
                }
                logger.info(line, category: .search)
            }
            // #588: preserve aggregated breakdown so the CLI / runner can
            // surface door + garbage-filter counters in the final report
            // without having to plumb a new return type through buildIndex
            // (which would break every existing caller).
            lastBuildStats = allStats
            let count = try await searchIndex.documentCount()
            logger.info("✅ Search index built: \(count) documents", category: .search)
        }

        /// Per-strategy `IndexStats` from the most recent `buildIndex` call.
        /// Used by the CLI runner to read the #588 door + garbage-filter
        /// breakdown after `buildIndex` returns. Nil until a build completes.
        public private(set) var lastBuildStats: [Search.IndexStats] = []

        // `makeDefaultStrategies` lifted to `SearchStrategies/Search.Strategies.Factory.swift`
        // by #899 alongside the 6 strategy concretes. Composition roots
        // construct strategies through that factory and pass the resulting
        // array to this target's primary init.

        // MARK: - Framework Synonyms

        /// Register well-known framework synonyms so that common alternate names resolve
        /// to the correct framework in search results.
        ///
        /// For example, searching `"bluetooth"` will return `CoreBluetooth` results.
        private func registerFrameworkSynonyms() async throws {
            let synonyms: [(identifier: String, synonyms: String)] = [
                ("corenfc", "nfc"),
                ("journalingsuggestions", "journaling"),
                ("corebluetooth", "bluetooth"),
                ("corelocation", "location"),
                ("coredata", "data"),
                ("coremotion", "motion"),
                ("coregraphics", "graphics"),
                ("coreimage", "imageprocessing"),
                ("coremedia", "media"),
                ("coreaudio", "audio"),
                ("coreml", "ml,machinelearning"),
                ("corespotlight", "spotlight"),
                ("coretext", "text"),
                ("corevideo", "video"),
                ("corehaptics", "haptics"),
                ("corewlan", "wifi,wlan"),
                ("coretelephony", "telephony"),
                ("metalperformanceshadersgraph", "mpsgraph"),
                ("avfoundation", "av"),
                ("scenekit", "scene"),
                ("spritekit", "sprite"),
                ("groupactivities", "shareplay"),
            ]
            for entry in synonyms {
                try await searchIndex.updateFrameworkSynonyms(
                    identifier: entry.identifier,
                    synonyms: entry.synonyms
                )
            }
        }
    }
}
