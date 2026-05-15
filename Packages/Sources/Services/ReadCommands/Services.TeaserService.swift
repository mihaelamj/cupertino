import Foundation
import SampleIndexModels
import SearchModels
import ServicesModels
import SharedConstants
// MARK: - Teaser Service

/// Service for fetching teaser results from sources the user didn't search.
/// Consolidates teaser logic previously duplicated between CLI and MCP.
extension Services {
    public actor TeaserService {
        private let searchIndex: (any Search.Database)?
        private let sampleDatabase: (any Sample.Index.Reader)?

        /// Initialize with existing database connections. The concrete
        /// `Search.Index?` form continues to compile because `Search.Index`
        /// conforms to `Search.Database`; same for `Sample.Index.Database`
        /// conforming to `Sample.Index.Reader`.
        public init(searchIndex: (any Search.Database)?, sampleDatabase: (any Sample.Index.Reader)?) {
            self.searchIndex = searchIndex
            self.sampleDatabase = sampleDatabase
        }

        // MARK: - Fetch All Teasers

        /// Fetch teaser results from all sources except the one being searched
        public func fetchAllTeasers(
            query: String,
            framework: String?,
            currentSource: String?,
            includeArchive: Bool
        ) async -> Services.Formatter.TeaserResults {
            var teasers = Services.Formatter.TeaserResults()
            let source = currentSource ?? Shared.Constants.SourcePrefix.appleDocs

            // Apple Documentation teaser (unless searching apple-docs)
            if source != Shared.Constants.SourcePrefix.appleDocs {
                teasers.appleDocs = await fetchTeaserFromSource(
                    query: query,
                    sourceType: Shared.Constants.SourcePrefix.appleDocs
                )
            }

            // Samples teaser (unless searching samples)
            if source != Shared.Constants.SourcePrefix.samples,
               source != Shared.Constants.SourcePrefix.appleSampleCode {
                teasers.samples = await fetchTeaserSamples(query: query, framework: framework)
            }

            // Archive teaser (unless searching archive or include_archive is set)
            if !includeArchive, source != Shared.Constants.SourcePrefix.appleArchive {
                teasers.archive = await fetchTeaserFromSource(
                    query: query,
                    sourceType: Shared.Constants.SourcePrefix.appleArchive
                )
            }

            // HIG teaser (unless searching HIG)
            if source != Shared.Constants.SourcePrefix.hig {
                teasers.hig = await fetchTeaserFromSource(
                    query: query,
                    sourceType: Shared.Constants.SourcePrefix.hig
                )
            }

            // Swift Evolution teaser (unless searching swift-evolution)
            if source != Shared.Constants.SourcePrefix.swiftEvolution {
                teasers.swiftEvolution = await fetchTeaserFromSource(
                    query: query,
                    sourceType: Shared.Constants.SourcePrefix.swiftEvolution
                )
            }

            // Swift.org teaser (unless searching swift-org)
            if source != Shared.Constants.SourcePrefix.swiftOrg {
                teasers.swiftOrg = await fetchTeaserFromSource(
                    query: query,
                    sourceType: Shared.Constants.SourcePrefix.swiftOrg
                )
            }

            // Swift Book teaser (unless searching swift-book)
            if source != Shared.Constants.SourcePrefix.swiftBook {
                teasers.swiftBook = await fetchTeaserFromSource(
                    query: query,
                    sourceType: Shared.Constants.SourcePrefix.swiftBook
                )
            }

            // Packages teaser (unless searching packages)
            if source != Shared.Constants.SourcePrefix.packages {
                teasers.packages = await fetchTeaserFromSource(
                    query: query,
                    sourceType: Shared.Constants.SourcePrefix.packages
                )
            }

            return teasers
        }

        // MARK: - Individual Teaser Fetchers

        /// Fetch a few sample projects as teaser
        public func fetchTeaserSamples(query: String, framework: String?) async -> [Sample.Index.Project] {
            guard let sampleDatabase else { return [] }

            do {
                return try await sampleDatabase.searchProjects(
                    query: query,
                    framework: framework,
                    limit: Shared.Constants.Limit.teaserLimit
                )
            } catch {
                return []
            }
        }

        /// Fetch teaser results from a specific source
        public func fetchTeaserFromSource(query: String, sourceType: String) async -> [Search.Result] {
            guard let searchIndex else { return [] }

            do {
                return try await searchIndex.search(
                    query: query,
                    source: sourceType,
                    framework: nil,
                    language: nil,
                    limit: Shared.Constants.Limit.teaserLimit,
                    includeArchive: sourceType == Shared.Constants.SourcePrefix.appleArchive
                )
            } catch {
                return []
            }
        }

        // MARK: - Lifecycle

        /// Disconnect database connections
        public func disconnect() async {
            // Note: In actor-based design, connections are cleaned up on deallocation
        }
    }
}

// The `withTeaserService` factory used to live here, but it needed to
// construct a `Search.Index` (which lives in the Search target) and so
// dragged `import Search` into this file. The factory now lives in
// `Services.ServiceContainer.swift`, alongside the other
// `with*Service` factories — that file keeps its `import Search` for
// the same Search.Index-instantiation responsibility, but this file no
// longer needs it.
