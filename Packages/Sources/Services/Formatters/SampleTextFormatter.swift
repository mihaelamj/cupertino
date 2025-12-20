import Foundation
import SampleIndex
import Shared

// MARK: - Sample Search Text Formatter

/// Formats sample search results as plain text for CLI output
public struct SampleSearchTextFormatter: ResultFormatter {
    private let query: String
    private let framework: String?
    private let teasers: TeaserResults?

    public init(query: String, framework: String? = nil, teasers: TeaserResults? = nil) {
        self.query = query
        self.framework = framework
        self.teasers = teasers
    }

    public func format(_ result: SampleSearchResult) -> String {
        if result.isEmpty {
            return "No results found for '\(query)'"
        }

        var output = "Search Results for '\(query)'\n"

        if let framework {
            output += "Filtered by: \(framework)\n"
        }

        output += "\n"

        // Projects
        if !result.projects.isEmpty {
            output += "Projects (\(result.projects.count) found):\n\n"

            for (index, project) in result.projects.enumerated() {
                output += "[\(index + 1)] \(project.title)\n"
                output += "    ID: \(project.id)\n"
                output += "    Frameworks: \(project.frameworks.joined(separator: ", "))\n"
                output += "    Files: \(project.fileCount)\n"

                if !project.description.isEmpty {
                    let maxLen = Shared.Constants.Limit.summaryTruncationLength
                    output += "    \(project.description.truncated(to: maxLen))\n"
                }

                output += "\n"
            }
        }

        // Files
        if !result.files.isEmpty {
            output += "Matching Files (\(result.files.count) found):\n\n"

            for (index, file) in result.files.prefix(10).enumerated() {
                output += "[\(index + 1)] \(file.filename)\n"
                output += "    Project: \(file.projectId)\n"
                output += "    Path: \(file.path)\n"
                output += "    > \(file.snippet)\n"
                output += "\n"
            }
        }

        // Footer: teasers, tips, and guidance
        let footer = SearchFooter.singleSource(Shared.Constants.SourcePrefix.samples, teasers: teasers)
        output += footer.formatText()

        return output
    }
}

// MARK: - Sample List Text Formatter

/// Formats sample project list as plain text for CLI output
public struct SampleListTextFormatter: ResultFormatter {
    private let totalCount: Int

    public init(totalCount: Int) {
        self.totalCount = totalCount
    }

    public func format(_ projects: [SampleIndex.Project]) -> String {
        if projects.isEmpty {
            return "No sample projects found. Run 'cupertino index' to build the sample index."
        }

        var output = "Sample Projects (\(projects.count) of \(totalCount) total):\n\n"

        for (index, project) in projects.enumerated() {
            output += "[\(index + 1)] \(project.title)\n"
            output += "    ID: \(project.id)\n"
            output += "    Frameworks: \(project.frameworks.joined(separator: ", "))\n"
            output += "    Files: \(project.fileCount)\n\n"
        }

        // Footer: tips and guidance
        let footer = SearchFooter.singleSource(Shared.Constants.SourcePrefix.samples)
        output += footer.formatText()

        return output
    }
}

// MARK: - Sample Project Text Formatter

/// Formats a single sample project as plain text
public struct SampleProjectTextFormatter: ResultFormatter {
    public init() {}

    public func format(_ project: SampleIndex.Project) -> String {
        var output = "Project: \(project.title)\n"
        output += "ID: \(project.id)\n"
        output += "Frameworks: \(project.frameworks.joined(separator: ", "))\n"
        output += "Files: \(project.fileCount)\n\n"

        if !project.description.isEmpty {
            output += "Description:\n\(project.description)\n"
        }

        // Footer: tips and guidance
        let footer = SearchFooter.singleSource(Shared.Constants.SourcePrefix.samples)
        output += footer.formatText()

        return output
    }
}
