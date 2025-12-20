import Foundation
import SampleIndex
import Search
import Shared

// MARK: - Teaser Results

/// Container for teaser results from alternate sources.
/// Used by both MCP and CLI to show hints about other sources.
public struct TeaserResults: Sendable {
    public var appleDocs: [Search.Result]
    public var samples: [SampleIndex.Project]
    public var archive: [Search.Result]
    public var hig: [Search.Result]
    public var swiftEvolution: [Search.Result]
    public var swiftOrg: [Search.Result]
    public var swiftBook: [Search.Result]
    public var packages: [Search.Result]

    public init(
        appleDocs: [Search.Result] = [],
        samples: [SampleIndex.Project] = [],
        archive: [Search.Result] = [],
        hig: [Search.Result] = [],
        swiftEvolution: [Search.Result] = [],
        swiftOrg: [Search.Result] = [],
        swiftBook: [Search.Result] = [],
        packages: [Search.Result] = []
    ) {
        self.appleDocs = appleDocs
        self.samples = samples
        self.archive = archive
        self.hig = hig
        self.swiftEvolution = swiftEvolution
        self.swiftOrg = swiftOrg
        self.swiftBook = swiftBook
        self.packages = packages
    }

    /// Whether there are any teaser results
    public var isEmpty: Bool {
        appleDocs.isEmpty && samples.isEmpty && archive.isEmpty && hig.isEmpty &&
            swiftEvolution.isEmpty && swiftOrg.isEmpty &&
            swiftBook.isEmpty && packages.isEmpty
    }

    /// Represents a teaser source with its metadata
    public struct SourceTeaser: Sendable {
        public let displayName: String
        public let sourcePrefix: String
        public let emoji: String
        public let titles: [String]

        public var isEmpty: Bool { titles.isEmpty }
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

        return sources
    }
}
