import Foundation
import SampleIndex
import SampleIndexModels
import SearchModels
import SharedConstants
import SharedCore

// MARK: - Unified Search Input

extension Services.Formatter.Unified {
    /// Input data for unified search formatting - includes ALL sources
    public struct Input: Sendable {
        public let docResults: [Search.Result]
        public let archiveResults: [Search.Result]
        public let sampleResults: [Sample.Index.Project]
        public let higResults: [Search.Result]
        public let swiftEvolutionResults: [Search.Result]
        public let swiftOrgResults: [Search.Result]
        public let swiftBookResults: [Search.Result]
        public let packagesResults: [Search.Result]
        public let limit: Int // The limit used per source, for teaser calculation

        public init(
            docResults: [Search.Result] = [],
            archiveResults: [Search.Result] = [],
            sampleResults: [Sample.Index.Project] = [],
            higResults: [Search.Result] = [],
            swiftEvolutionResults: [Search.Result] = [],
            swiftOrgResults: [Search.Result] = [],
            swiftBookResults: [Search.Result] = [],
            packagesResults: [Search.Result] = [],
            limit: Int = 10
        ) {
            self.docResults = docResults
            self.archiveResults = archiveResults
            self.sampleResults = sampleResults
            self.higResults = higResults
            self.swiftEvolutionResults = swiftEvolutionResults
            self.swiftOrgResults = swiftOrgResults
            self.swiftBookResults = swiftBookResults
            self.packagesResults = packagesResults
            self.limit = limit
        }

        /// Total number of results across all sources
        public var totalCount: Int {
            docResults.count + archiveResults.count + sampleResults.count +
                higResults.count + swiftEvolutionResults.count + swiftOrgResults.count +
                swiftBookResults.count + packagesResults.count
        }

        /// Number of sources that returned results
        public var nonEmptySourceCount: Int {
            allSources.count
        }

        /// Represents a source section for iteration
        public struct SourceSection: Sendable {
            public let info: Shared.Constants.SourcePrefix.SourceInfo
            public let docResults: [Search.Result]
            public let sampleResults: [Sample.Index.Project]

            public var isEmpty: Bool {
                docResults.isEmpty && sampleResults.isEmpty
            }

            public var count: Int {
                docResults.count + sampleResults.count
            }

            public var isSampleSource: Bool {
                !sampleResults.isEmpty
            }

            /// Create from doc results if not empty, nil otherwise
            public static func fromDocs(
                _ info: Shared.Constants.SourcePrefix.SourceInfo,
                _ results: [Search.Result]
            ) -> SourceSection? {
                guard !results.isEmpty else { return nil }
                return SourceSection(info: info, docResults: results, sampleResults: [])
            }

            /// Create from sample results if not empty, nil otherwise
            public static func fromSamples(
                _ info: Shared.Constants.SourcePrefix.SourceInfo,
                _ results: [Sample.Index.Project]
            ) -> SourceSection? {
                guard !results.isEmpty else { return nil }
                return SourceSection(info: info, docResults: [], sampleResults: results)
            }
        }

        /// Returns all non-empty sources in display order
        public var allSources: [SourceSection] {
            typealias Info = Shared.Constants.SourcePrefix
            typealias Section = SourceSection

            // Order: Apple Docs, Archive, Samples, HIG, Swift Evolution, Swift.org, Swift Book, Packages
            return [
                Section.fromDocs(Info.infoAppleDocs, docResults),
                Section.fromDocs(Info.infoArchive, archiveResults),
                Section.fromSamples(Info.infoSamples, sampleResults),
                Section.fromDocs(Info.infoHIG, higResults),
                Section.fromDocs(Info.infoSwiftEvolution, swiftEvolutionResults),
                Section.fromDocs(Info.infoSwiftOrg, swiftOrgResults),
                Section.fromDocs(Info.infoSwiftBook, swiftBookResults),
                Section.fromDocs(Info.infoPackages, packagesResults),
            ].compactMap { $0 }
        }

        /// Teaser info for sources that hit the limit (likely have more results)
        public struct SourceTeaserInfo: Sendable {
            public let info: Shared.Constants.SourcePrefix.SourceInfo
            public let shownCount: Int
            public let hasMore: Bool // True if count == limit (likely more available)

            /// Convenience accessors
            public var displayName: String {
                info.name
            }

            public var sourcePrefix: String {
                info.key
            }

            public var emoji: String {
                info.emoji
            }
        }

        /// Returns teaser info for all sources that hit the limit (nil if none)
        public var sourceTeasers: [SourceTeaserInfo]? {
            typealias Info = Shared.Constants.SourcePrefix

            // Check each source in display order
            let sourcesWithCounts: [(info: Info.SourceInfo, count: Int)] = [
                (Info.infoAppleDocs, docResults.count),
                (Info.infoArchive, archiveResults.count),
                (Info.infoSamples, sampleResults.count),
                (Info.infoHIG, higResults.count),
                (Info.infoSwiftEvolution, swiftEvolutionResults.count),
                (Info.infoSwiftOrg, swiftOrgResults.count),
                (Info.infoSwiftBook, swiftBookResults.count),
                (Info.infoPackages, packagesResults.count),
            ]

            let teasers = sourcesWithCounts.compactMap { info, count -> SourceTeaserInfo? in
                guard count == limit else { return nil }
                return SourceTeaserInfo(info: info, shownCount: count, hasMore: true)
            }

            return teasers.isEmpty ? nil : teasers
        }
    }
}
