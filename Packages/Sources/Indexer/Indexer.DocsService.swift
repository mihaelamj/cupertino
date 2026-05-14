import Foundation
import Logging
import SearchModels
import SharedConstants
import SharedCore

extension Indexer {
    /// Build `search.db` from on-disk corpus (apple-docs JSON, swift
    /// evolution markdown, swift.org, archive, HIG). Wraps an injected
    /// `Search.DocsIndexingRunner` conformer with event-emission so this
    /// target doesn't import `Search` directly — the CLI composition
    /// root supplies a closure backed by `Search.Index` +
    /// `Search.IndexBuilder`.
    public enum DocsService {
        public struct Request: Sendable {
            public let baseDir: URL
            public let docsDir: URL?
            public let evolutionDir: URL?
            public let swiftOrgDir: URL?
            public let archiveDir: URL?
            public let higDir: URL?
            public let searchDB: URL?
            public let clear: Bool

            public init(
                baseDir: URL,
                docsDir: URL? = nil,
                evolutionDir: URL? = nil,
                swiftOrgDir: URL? = nil,
                archiveDir: URL? = nil,
                higDir: URL? = nil,
                searchDB: URL? = nil,
                clear: Bool = false
            ) {
                self.baseDir = baseDir
                self.docsDir = docsDir
                self.evolutionDir = evolutionDir
                self.swiftOrgDir = swiftOrgDir
                self.archiveDir = archiveDir
                self.higDir = higDir
                self.searchDB = searchDB
                self.clear = clear
            }
        }

        public struct Outcome: Sendable {
            public let searchDBPath: URL
            public let documentCount: Int
            public let frameworkCount: Int
        }

        public enum Event: Sendable {
            case removingExistingDB(URL)
            case initializingIndex
            case missingOptionalSource(label: String, url: URL)
            case availabilityMissing
            case progress(processed: Int, total: Int, percent: Double)
            case finished(Outcome)
        }

        public static func run(
            _ request: Request,
            markdownStrategy: any Search.MarkdownToStructuredPageStrategy,
            sampleCatalogProvider: any Search.SampleCatalogProvider,
            docsIndexingRunner: any Search.DocsIndexingRunner,
            handler: @escaping @Sendable (Event) -> Void = { _ in }
        ) async throws -> Outcome {
            let docsURL = request.docsDir
                ?? request.baseDir.appendingPathComponent(Shared.Constants.Directory.docs)
            let evolutionURL = request.evolutionDir
                ?? request.baseDir.appendingPathComponent(Shared.Constants.Directory.swiftEvolution)
            let swiftOrgURL = request.swiftOrgDir
                ?? request.baseDir.appendingPathComponent(Shared.Constants.Directory.swiftOrg)
            let archiveURL = request.archiveDir
                ?? request.baseDir.appendingPathComponent(Shared.Constants.Directory.archive)
            let higURL = request.higDir
                ?? request.baseDir.appendingPathComponent(Shared.Constants.Directory.hig)
            let searchDBURL = request.searchDB
                ?? request.baseDir.appendingPathComponent(Shared.Constants.FileName.searchDatabase)

            // FTS5 doesn't tolerate INSERT OR REPLACE cleanly; fresh DB
            // every time keeps the correctness story simple.
            if FileManager.default.fileExists(atPath: searchDBURL.path) {
                handler(.removingExistingDB(searchDBURL))
                try FileManager.default.removeItem(at: searchDBURL)
            }

            handler(.initializingIndex)

            let evolutionDirToUse = optionalDir(evolutionURL, label: "Swift Evolution", handler: handler)
            let swiftOrgDirToUse = optionalDir(swiftOrgURL, label: "Swift.org", handler: handler)
            let archiveDirToUse = optionalDir(archiveURL, label: "Apple Archive", handler: handler)
            let higDirToUse = optionalDir(higURL, label: "HIG", handler: handler)

            if !Indexer.Preflight.checkDocsHaveAvailability(docsDir: docsURL) {
                handler(.availabilityMissing)
            }

            let input = Search.DocsIndexingInput(
                searchDBPath: searchDBURL,
                docsDirectory: docsURL,
                evolutionDirectory: evolutionDirToUse,
                swiftOrgDirectory: swiftOrgDirToUse,
                archiveDirectory: archiveDirToUse,
                higDirectory: higDirToUse,
                clearExisting: request.clear,
                markdownStrategy: markdownStrategy,
                sampleCatalogProvider: sampleCatalogProvider
            )

            let result = try await docsIndexingRunner.run(input: input) { processed, total in
                let percent = Double(processed) / Double(total) * 100
                handler(.progress(processed: processed, total: total, percent: percent))
            }

            let outcome = Outcome(
                searchDBPath: searchDBURL,
                documentCount: result.documentCount,
                frameworkCount: result.frameworkCount
            )
            handler(.finished(outcome))
            return outcome
        }

        private static func optionalDir(
            _ url: URL,
            label: String,
            handler: @Sendable (Event) -> Void
        ) -> URL? {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            handler(.missingOptionalSource(label: label, url: url))
            return nil
        }
    }
}
