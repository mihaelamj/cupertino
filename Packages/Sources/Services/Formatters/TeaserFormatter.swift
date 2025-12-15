import Foundation
import SampleIndex
import Search
import Shared

// MARK: - Teaser Results

/// Container for teaser results from alternate sources.
/// Used by both MCP and CLI to show hints about other sources.
public struct TeaserResults: Sendable {
    public var samples: [SampleIndex.Project]
    public var archive: [Search.Result]
    public var hig: [Search.Result]
    public var swiftEvolution: [Search.Result]
    public var swiftOrg: [Search.Result]
    public var swiftBook: [Search.Result]
    public var packages: [Search.Result]

    public init(
        samples: [SampleIndex.Project] = [],
        archive: [Search.Result] = [],
        hig: [Search.Result] = [],
        swiftEvolution: [Search.Result] = [],
        swiftOrg: [Search.Result] = [],
        swiftBook: [Search.Result] = [],
        packages: [Search.Result] = []
    ) {
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
        samples.isEmpty && archive.isEmpty && hig.isEmpty &&
            swiftEvolution.isEmpty && swiftOrg.isEmpty &&
            swiftBook.isEmpty && packages.isEmpty
    }
}

// MARK: - Teaser Markdown Formatter

/// Formats teaser results as markdown.
/// Shared by both MCP and CLI for consistent output.
public struct TeaserMarkdownFormatter {
    public init() {}

    /// Format teaser results as markdown sections
    public func format(_ teasers: TeaserResults) -> String {
        var output = ""

        // Sample code teaser
        if !teasers.samples.isEmpty {
            output += "\n\n---\n\n"
            output += "💡 **Also in Sample Code:**\n"
            for project in teasers.samples {
                output += "- \(project.title)\n"
            }
            output += "\n_→ Use `source: \(Shared.Constants.SourcePrefix.samples)`_"
        }

        // Archive teaser
        if !teasers.archive.isEmpty {
            output += "\n\n---\n\n"
            output += "📚 **Also in Apple Archive:**\n"
            for result in teasers.archive {
                output += "- \(result.title)\n"
            }
            output += "\n_→ Use `source: \(Shared.Constants.SourcePrefix.appleArchive)`_"
        }

        // HIG teaser
        if !teasers.hig.isEmpty {
            output += "\n\n---\n\n"
            output += "🎨 **Also in Human Interface Guidelines:**\n"
            for result in teasers.hig {
                output += "- \(result.title)\n"
            }
            output += "\n_→ Use `source: \(Shared.Constants.SourcePrefix.hig)`_"
        }

        // Swift Evolution teaser
        if !teasers.swiftEvolution.isEmpty {
            output += "\n\n---\n\n"
            output += "📝 **Also in Swift Evolution:**\n"
            for result in teasers.swiftEvolution {
                output += "- \(result.title)\n"
            }
            output += "\n_→ Use `source: \(Shared.Constants.SourcePrefix.swiftEvolution)`_"
        }

        // Swift.org teaser
        if !teasers.swiftOrg.isEmpty {
            output += "\n\n---\n\n"
            output += "🔶 **Also in Swift.org:**\n"
            for result in teasers.swiftOrg {
                output += "- \(result.title)\n"
            }
            output += "\n_→ Use `source: \(Shared.Constants.SourcePrefix.swiftOrg)`_"
        }

        // Swift Book teaser
        if !teasers.swiftBook.isEmpty {
            output += "\n\n---\n\n"
            output += "📖 **Also in Swift Book:**\n"
            for result in teasers.swiftBook {
                output += "- \(result.title)\n"
            }
            output += "\n_→ Use `source: \(Shared.Constants.SourcePrefix.swiftBook)`_"
        }

        // Packages teaser
        if !teasers.packages.isEmpty {
            output += "\n\n---\n\n"
            output += "📦 **Also in Swift Packages:**\n"
            for result in teasers.packages {
                output += "- \(result.title)\n"
            }
            output += "\n_→ Use `source: \(Shared.Constants.SourcePrefix.packages)`_"
        }

        return output
    }
}
