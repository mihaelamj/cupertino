import Foundation
import SampleIndexModels
import SearchModels
import SharedConstants

// MARK: - Teaser Results

/// Container for teaser results from alternate sources.
/// Used by both MCP and CLI to show hints about other sources.
extension Services.Formatter {
    public struct TeaserResults: Sendable {
        public var appleDocs: [Search.Result]
        public var samples: [Sample.Index.Project]
        public var archive: [Search.Result]
        public var hig: [Search.Result]
        public var swiftEvolution: [Search.Result]
        public var swiftOrg: [Search.Result]
        public var swiftBook: [Search.Result]
        public var packages: [Search.Result]

        /// #1042 Cluster 6 sub-1: open-ended bucket for sources beyond
        /// the 8 typed properties above. A new source (e.g. WWDC
        /// transcripts) stores its teaser results here keyed by
        /// `definition.id`; `allSources` enumerates these alongside
        /// the typed properties. Each entry carries the displayName +
        /// emoji the new source declared in its `Search.SourceDefinition`,
        /// avoiding the parallel `Prefix.emojiX` lookup the typed
        /// properties still use.
        public var extras: [String: ExtraSource]

        public struct ExtraSource: Sendable {
            public let sourceID: String
            public let displayName: String
            public let emoji: String
            public let results: [Search.Result]

            public init(sourceID: String, displayName: String, emoji: String, results: [Search.Result]) {
                self.sourceID = sourceID
                self.displayName = displayName
                self.emoji = emoji
                self.results = results
            }

            public var isEmpty: Bool { results.isEmpty }
        }

        public init(
            appleDocs: [Search.Result] = [],
            samples: [Sample.Index.Project] = [],
            archive: [Search.Result] = [],
            hig: [Search.Result] = [],
            swiftEvolution: [Search.Result] = [],
            swiftOrg: [Search.Result] = [],
            swiftBook: [Search.Result] = [],
            packages: [Search.Result] = [],
            extras: [String: ExtraSource] = [:]
        ) {
            self.appleDocs = appleDocs
            self.samples = samples
            self.archive = archive
            self.hig = hig
            self.swiftEvolution = swiftEvolution
            self.swiftOrg = swiftOrg
            self.swiftBook = swiftBook
            self.packages = packages
            self.extras = extras
        }

        /// Whether there are any teaser results
        public var isEmpty: Bool {
            appleDocs.isEmpty && samples.isEmpty && archive.isEmpty && hig.isEmpty &&
                swiftEvolution.isEmpty && swiftOrg.isEmpty &&
                swiftBook.isEmpty && packages.isEmpty &&
                extras.allSatisfy(\.value.isEmpty)
        }

        /// Represents a teaser source with its metadata
        public struct SourceTeaser: Sendable {
            public let displayName: String
            public let sourcePrefix: String
            public let emoji: String
            public let titles: [String]

            public var isEmpty: Bool {
                titles.isEmpty
            }
        }

        /// Returns all non-empty sources as an iterable collection
        public var allSources: [SourceTeaser] {
            typealias Prefix = Shared.Constants.SourcePrefix
            var sources: [SourceTeaser] = []

            if !appleDocs.isEmpty {
                sources.append(SourceTeaser(
                    displayName: "Apple Documentation",
                    sourcePrefix: Prefix.appleDocs,
                    emoji: Prefix.emojiAppleDocs,
                    titles: appleDocs.map(\.title)
                ))
            }
            if !samples.isEmpty {
                sources.append(SourceTeaser(
                    displayName: "Sample Code",
                    sourcePrefix: Prefix.samples,
                    emoji: Prefix.emojiSamples,
                    titles: samples.map(\.title)
                ))
            }
            if !archive.isEmpty {
                sources.append(SourceTeaser(
                    displayName: "Apple Archive",
                    sourcePrefix: Prefix.appleArchive,
                    emoji: Prefix.emojiArchive,
                    titles: archive.map(\.title)
                ))
            }
            if !hig.isEmpty {
                sources.append(SourceTeaser(
                    displayName: "Human Interface Guidelines",
                    sourcePrefix: Prefix.hig,
                    emoji: Prefix.emojiHIG,
                    titles: hig.map(\.title)
                ))
            }
            if !swiftEvolution.isEmpty {
                sources.append(SourceTeaser(
                    displayName: "Swift Evolution",
                    sourcePrefix: Prefix.swiftEvolution,
                    emoji: Prefix.emojiSwiftEvolution,
                    titles: swiftEvolution.map(\.title)
                ))
            }
            if !swiftOrg.isEmpty {
                sources.append(SourceTeaser(
                    displayName: "Swift.org",
                    sourcePrefix: Prefix.swiftOrg,
                    emoji: Prefix.emojiSwiftOrg,
                    titles: swiftOrg.map(\.title)
                ))
            }
            if !swiftBook.isEmpty {
                sources.append(SourceTeaser(
                    displayName: "Swift Book",
                    sourcePrefix: Prefix.swiftBook,
                    emoji: Prefix.emojiSwiftBook,
                    titles: swiftBook.map(\.title)
                ))
            }
            if !packages.isEmpty {
                sources.append(SourceTeaser(
                    displayName: "Swift Packages",
                    sourcePrefix: Prefix.packages,
                    emoji: Prefix.emojiPackages,
                    titles: packages.map(\.title)
                ))
            }
            // #1042 Cluster 6 sub-1: extras for sources beyond the
            // 8 typed properties. Keys are SourceProvider.definition.id
            // values; each entry carries its own displayName + emoji.
            for (_, extra) in extras where !extra.isEmpty {
                sources.append(SourceTeaser(
                    displayName: extra.displayName,
                    sourcePrefix: extra.sourceID,
                    emoji: extra.emoji,
                    titles: extra.results.map(\.title)
                ))
            }

            return sources
        }
    }
}
