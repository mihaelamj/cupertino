import Foundation
import Search
import Shared

// MARK: - Markdown Search Result Formatter

/// Formats search results as markdown for MCP tools and CLI --format markdown
public struct MarkdownSearchResultFormatter: ResultFormatter {
    private let query: String
    private let filters: SearchFilters?
    private let config: SearchResultFormatConfig

    public init(
        query: String,
        filters: SearchFilters? = nil,
        config: SearchResultFormatConfig = .mcpDefault
    ) {
        self.query = query
        self.filters = filters
        self.config = config
    }

    public func format(_ results: [Search.Result]) -> String {
        var md = "# Search Results for \"\(query)\"\n\n"

        // Show active filters
        if let filters, filters.hasActiveFilters {
            if let source = filters.source {
                md += "_Filtered to source: **\(source)**_\n\n"
            }
            if let framework = filters.framework {
                md += "_Filtered to framework: **\(framework)**_\n\n"
            }
            if let language = filters.language {
                md += "_Filtered to language: **\(language)**_\n\n"
            }
        }

        md += "Found **\(results.count)** result\(results.count == 1 ? "" : "s"):\n\n"

        if results.isEmpty {
            md += config.emptyMessage
            return md
        }

        for (index, result) in results.enumerated() {
            md += "## \(index + 1). \(result.title)\n\n"
            md += "- **Framework:** `\(result.framework)`\n"
            md += "- **URI:** `\(result.uri)`\n"

            if config.showScore {
                md += "- **Score:** \(String(format: "%.2f", result.score))\n"
            }
            if config.showWordCount {
                md += "- **Words:** \(result.wordCount)\n"
            }
            if config.showSource {
                md += "- **Source:** \(result.source)\n"
            }

            md += "\n\(result.summary)\n\n"

            if config.showSeparators, index < results.count - 1 {
                md += "---\n\n"
            }
        }

        md += "\n\n"
        md += Shared.Constants.MCP.tipUseResourcesRead
        md += "\n"

        return md
    }
}

// MARK: - HIG Markdown Formatter

/// Formats HIG search results as markdown
public struct HIGMarkdownFormatter: ResultFormatter {
    private let query: HIGQuery
    private let config: SearchResultFormatConfig

    public init(query: HIGQuery, config: SearchResultFormatConfig = .mcpDefault) {
        self.query = query
        self.config = config
    }

    public func format(_ results: [Search.Result]) -> String {
        var md = "# HIG Search Results for \"\(query.text)\"\n\n"

        if let platform = query.platform {
            md += "_Platform: **\(platform)**_\n\n"
        }
        if let category = query.category {
            md += "_Category: **\(category)**_\n\n"
        }

        md += "Found **\(results.count)** guideline\(results.count == 1 ? "" : "s"):\n\n"

        if results.isEmpty {
            md += "_No Human Interface Guidelines found matching your query._\n\n"
            md += "**Tips:**\n"
            md += "- Try broader design terms (e.g., 'buttons', 'typography', 'navigation')\n"
            md += "- Specify a platform: iOS, macOS, watchOS, visionOS, tvOS\n"
            md += "- Specify a category: foundations, patterns, components, technologies, inputs\n"
            return md
        }

        for (index, result) in results.enumerated() {
            md += "## \(index + 1). \(result.title)\n\n"
            md += "- **URI:** `\(result.uri)`\n"

            if config.showScore {
                md += "- **Score:** \(String(format: "%.2f", result.score))\n"
            }

            md += "\n\(result.summary)\n\n"

            if config.showSeparators, index < results.count - 1 {
                md += "---\n\n"
            }
        }

        md += "\n\n"
        md += Shared.Constants.MCP.tipUseResourcesRead
        md += "\n"

        return md
    }
}

// MARK: - Frameworks Markdown Formatter

/// Formats framework list as markdown
public struct FrameworksMarkdownFormatter: ResultFormatter {
    private let totalDocs: Int

    public init(totalDocs: Int) {
        self.totalDocs = totalDocs
    }

    public func format(_ frameworks: [String: Int]) -> String {
        var md = "# Available Frameworks\n\n"
        md += "Total documents: **\(totalDocs)**\n\n"

        if frameworks.isEmpty {
            let cmd = "\(Shared.Constants.App.commandName) \(Shared.Constants.Command.buildIndex)"
            md += Shared.Constants.MCP.messageNoFrameworks(buildIndexCommand: cmd)
            return md
        }

        md += "| Framework | Documents |\n"
        md += "|-----------|----------:|\n"

        // Sort by document count (descending)
        for (framework, count) in frameworks.sorted(by: { $0.value > $1.value }) {
            md += "| `\(framework)` | \(count) |\n"
        }

        md += "\n"
        md += Shared.Constants.MCP.tipFilterByFramework
        md += "\n"

        return md
    }
}
