import Foundation
import SampleIndex
import Shared

// MARK: - Sample Search Markdown Formatter

/// Formats sample search results as markdown
public struct SampleSearchMarkdownFormatter: ResultFormatter {
    private let query: String
    private let framework: String?
    private let teasers: TeaserResults?

    public init(query: String, framework: String? = nil, teasers: TeaserResults? = nil) {
        self.query = query
        self.framework = framework
        self.teasers = teasers
    }

    public func format(_ result: SampleSearchResult) -> String {
        var output = "# Sample Code Search: \"\(query)\"\n\n"

        // Tell the AI what source this is
        output += "_Source: **\(Shared.Constants.SourcePrefix.samples)**_\n\n"

        if let framework {
            output += "_Filtered to framework: **\(framework)**_\n\n"
        }

        // Projects
        output += "## Projects (\(result.projects.count) found)\n\n"

        if result.projects.isEmpty {
            output += "_No matching projects found._\n\n"
        } else {
            for (index, project) in result.projects.enumerated() {
                output += "### \(index + 1). \(project.title)\n\n"
                output += "- **ID:** `\(project.id)`\n"
                output += "- **Frameworks:** \(project.frameworks.joined(separator: ", "))\n"
                output += "- **Files:** \(project.fileCount)\n\n"

                if !project.description.isEmpty {
                    output += "\(project.description)\n\n"
                }
            }
        }

        // Files
        if !result.files.isEmpty {
            output += "\n## Matching Files (\(result.files.count) found)\n\n"

            for (index, file) in result.files.prefix(10).enumerated() {
                output += "### \(index + 1). \(file.filename)\n\n"
                output += "- **Project:** `\(file.projectId)`\n"
                output += "- **Path:** `\(file.path)`\n\n"
                output += "> \(file.snippet)\n\n"
            }
        }

        // Footer: tips and guidance
        let footer = SearchFooter.singleSource(
            Shared.Constants.SourcePrefix.samples,
            teasers: teasers
        )
        output += footer.formatMarkdown()

        return output
    }
}

// MARK: - Sample List Markdown Formatter

/// Formats sample project list as markdown
public struct SampleListMarkdownFormatter: ResultFormatter {
    private let totalCount: Int
    private let framework: String?

    public init(totalCount: Int, framework: String? = nil) {
        self.totalCount = totalCount
        self.framework = framework
    }

    public func format(_ projects: [SampleIndex.Project]) -> String {
        var output = "# Sample Projects\n\n"

        if let framework {
            output += "_Filtered to framework: **\(framework)**_\n\n"
        }

        output += "Showing \(projects.count) of \(totalCount) total projects.\n\n"

        if projects.isEmpty {
            output += "_No sample projects found._\n"
        } else {
            for (index, project) in projects.enumerated() {
                output += "## \(index + 1). \(project.title)\n\n"
                output += "- **ID:** `\(project.id)`\n"
                output += "- **Frameworks:** \(project.frameworks.joined(separator: ", "))\n"
                output += "- **Files:** \(project.fileCount)\n\n"

                if !project.description.isEmpty {
                    output += "\(project.description.truncated(to: Shared.Constants.Limit.summaryTruncationLength))\n\n"
                }
            }
        }

        // Footer: tips and guidance
        let footer = SearchFooter.singleSource(Shared.Constants.SourcePrefix.samples)
        output += footer.formatMarkdown()

        return output
    }
}

// MARK: - Sample Project Markdown Formatter

/// Formats a single sample project as markdown
public struct SampleProjectMarkdownFormatter: ResultFormatter {
    public init() {}

    public func format(_ project: SampleIndex.Project) -> String {
        var output = "# \(project.title)\n\n"
        output += "- **ID:** `\(project.id)`\n"
        output += "- **Frameworks:** \(project.frameworks.joined(separator: ", "))\n"
        output += "- **Files:** \(project.fileCount)\n\n"

        if !project.description.isEmpty {
            output += "## Description\n\n\(project.description)\n"
        }

        // Footer: tips and guidance
        let footer = SearchFooter.singleSource(Shared.Constants.SourcePrefix.samples)
        output += footer.formatMarkdown()

        return output
    }
}

// MARK: - Sample File Markdown Formatter

/// Formats a sample file as markdown
public struct SampleFileMarkdownFormatter: ResultFormatter {
    public init() {}

    public func format(_ file: SampleIndex.File) -> String {
        // Determine language for syntax highlighting
        let language = file.filename.hasSuffix(".swift") ? "swift" :
            file.filename.hasSuffix(".m") ? "objc" :
            file.filename.hasSuffix(".h") ? "objc" :
            file.filename.hasSuffix(".json") ? "json" :
            file.filename.hasSuffix(".plist") ? "xml" : ""

        var output = "# \(file.filename)\n\n"
        output += "- **Project:** `\(file.projectId)`\n"
        output += "- **Path:** `\(file.path)`\n\n"
        output += "```\(language)\n\(file.content)\n```\n"

        // Footer: tips and guidance
        let footer = SearchFooter.singleSource(Shared.Constants.SourcePrefix.samples)
        output += footer.formatMarkdown()

        return output
    }
}
