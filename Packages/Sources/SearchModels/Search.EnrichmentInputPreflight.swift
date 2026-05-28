import Foundation

// MARK: - Search.EnrichmentInputPreflight

extension Search {
    /// Generic, pure preflight for per-source enrichment inputs
    /// (`Search.SourceDefinition.requiredEnrichmentInputs`). Given the selected
    /// sources' definitions plus the resolved directories, it returns the list
    /// of missing/incomplete inputs. The caller (CLI save) decides whether to
    /// throw (default) or warn (`--allow-degraded-enrichment`).
    ///
    /// The ONLY dispatch is over `EnrichmentInput.Scope` (a closed set of
    /// location kinds that every source reuses), so adding a source or a new
    /// input is a declaration on the source, never an edit here. This is the
    /// single seam that replaced the two hardcoded per-source guards (#1072
    /// `apple-constraints.json` and `assertPackageAvailabilityComplete`).
    public enum EnrichmentInputPreflight {
        /// One unmet requirement: the source that declared it, the input, and
        /// (for per-corpus-item inputs) how many items lacked the sidecar.
        public struct Missing: Sendable, Equatable {
            public let sourceID: String
            public let input: Search.EnrichmentInput
            /// Corpus items lacking the sidecar / total items found. `nil`
            /// for `.baseDirectoryFile` (a single absent file).
            public let itemsMissing: Int?
            public let itemsTotal: Int?

            public init(
                sourceID: String,
                input: Search.EnrichmentInput,
                itemsMissing: Int? = nil,
                itemsTotal: Int? = nil
            ) {
                self.sourceID = sourceID
                self.input = input
                self.itemsMissing = itemsMissing
                self.itemsTotal = itemsTotal
            }
        }

        /// Collect every missing/incomplete enrichment input across the
        /// selected sources.
        ///
        /// - Parameters:
        ///   - definitions: source definitions being indexed this run.
        ///   - baseDirectory: where `.baseDirectoryFile` inputs are expected.
        ///   - corpusDirectoryByID: resolved corpus directory per source id,
        ///     for `.perCorpusItem` inputs. A source absent here, or whose
        ///     directory does not exist, has its per-corpus-item inputs
        ///     SKIPPED: it is not being indexed from an on-disk corpus.
        ///   - fileManager: injected for testability.
        public static func missing(
            definitions: [Search.SourceDefinition],
            baseDirectory: URL,
            corpusDirectoryByID: [String: URL],
            fileManager: FileManager = .default
        ) -> [Missing] {
            var results: [Missing] = []
            for definition in definitions {
                for input in definition.requiredEnrichmentInputs {
                    switch input.scope {
                    case .baseDirectoryFile:
                        let path = baseDirectory.appendingPathComponent(input.filename).path
                        if !fileManager.fileExists(atPath: path) {
                            results.append(Missing(sourceID: definition.id, input: input))
                        }

                    case let .perCorpusItem(marker):
                        guard let corpusDir = corpusDirectoryByID[definition.id],
                              fileManager.fileExists(atPath: corpusDir.path)
                        else {
                            continue
                        }
                        let itemDirs = itemDirectories(containing: marker, under: corpusDir, fileManager: fileManager)
                        guard !itemDirs.isEmpty else { continue }
                        let missingCount = itemDirs.filter {
                            !fileManager.fileExists(atPath: $0.appendingPathComponent(input.filename).path)
                        }.count
                        if missingCount > 0 {
                            results.append(
                                Missing(
                                    sourceID: definition.id,
                                    input: input,
                                    itemsMissing: missingCount,
                                    itemsTotal: itemDirs.count
                                )
                            )
                        }
                    }
                }
            }
            return results
        }

        /// Directories that directly contain a file named `marker`, found by
        /// walking `root`. A corpus item is the SHALLOWEST directory on any
        /// root-to-leaf path that contains `marker`; its subtree belongs to
        /// that item, so descent stops once an item is found. This prevents a
        /// package's internal file that happens to share the marker name (e.g.
        /// a test fixture `manifest.json` under `<owner>/<repo>/Tests/.../`)
        /// from being mistaken for a separate item, mirroring how the packages
        /// indexer discovers packages at the `<owner>/<repo>` level rather than
        /// recursively.
        static func itemDirectories(
            containing marker: String,
            under root: URL,
            fileManager: FileManager
        ) -> [URL] {
            var items: [URL] = []
            var stack: [URL] = [root]
            while let dir = stack.popLast() {
                let children = (try? fileManager.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                if children.contains(where: { $0.lastPathComponent == marker }) {
                    items.append(dir)
                    continue // prune: an item's own subtree is part of it
                }
                for child in children
                    where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    stack.append(child)
                }
            }
            return items
        }

        /// One operator-facing line per unmet requirement: what is missing,
        /// why it matters, and the exact command to fix it. Used both for the
        /// hard-fail message and (line by line) for the degraded-mode warnings.
        public static func lines(_ missing: [Missing]) -> [String] {
            missing.map { item in
                let head: String
                if let missingCount = item.itemsMissing, let totalCount = item.itemsTotal {
                    head = "\(item.sourceID): \(missingCount) of \(totalCount) items missing \(item.input.filename)"
                } else {
                    head = "\(item.sourceID) needs \(item.input.filename)"
                }
                return "\(head) (\(item.input.purpose)). \(item.input.howToObtain)"
            }
        }

        /// Assembled hard-fail message for `Search.Error.invalidQuery`.
        public static func failureMessage(_ missing: [Missing]) -> String {
            let body = lines(missing).map { "  - \($0)" }.joined(separator: "\n")
            return "Enrichment input(s) missing or incomplete; refusing to index from partial data:\n"
                + body
                + "\nTo index anyway with degraded coverage, pass --allow-degraded-enrichment."
        }
    }
}
