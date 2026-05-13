import Foundation
import SampleIndex
import SharedConstants
import SharedCore

// MARK: - Sample Search Text Formatter

/// Formats sample search results as plain text for CLI output
extension Sample.Format.Text {
    public struct Search: Services.Formatter.Result {
        private let query: String
        private let framework: String?
        private let teasers: Services.Formatter.TeaserResults?

        public init(query: String, framework: String? = nil, teasers: Services.Formatter.TeaserResults? = nil) {
            self.query = query
            self.framework = framework
            self.teasers = teasers
        }

        public func format(_ result: Sample.Search.Result) -> String {
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
            let footer = Services.Formatter.Footer.Search.singleSource(Shared.Constants.SourcePrefix.samples, teasers: teasers)
            output += footer.formatText()

            return output
        }
    }
}

// MARK: - Sample List Text Formatter

/// Formats sample project list as plain text for CLI output
extension Sample.Format.Text {
    public struct List: Services.Formatter.Result {
        private let totalCount: Int

        public init(totalCount: Int) {
            self.totalCount = totalCount
        }

        public func format(_ projects: [Sample.Index.Project]) -> String {
            if projects.isEmpty {
                return "No sample projects found. Run 'cupertino save --samples' to build the sample index."
            }

            var output = "Sample Projects (\(projects.count) of \(totalCount) total):\n\n"

            for (index, project) in projects.enumerated() {
                output += "[\(index + 1)] \(project.title)\n"
                output += "    ID: \(project.id)\n"
                output += "    Frameworks: \(project.frameworks.joined(separator: ", "))\n"
                output += "    Files: \(project.fileCount)\n\n"
            }

            // Footer: tips and guidance
            let footer = Services.Formatter.Footer.Search.singleSource(Shared.Constants.SourcePrefix.samples)
            output += footer.formatText()

            return output
        }
    }
}

// MARK: - Sample Project Text Formatter

/// Formats a single sample project as plain text
extension Sample.Format.Text {
    public struct Project: Services.Formatter.Result {
        public init() {}

        public func format(_ project: Sample.Index.Project) -> String {
            var output = "Project: \(project.title)\n"
            output += "ID: \(project.id)\n"
            output += "Frameworks: \(project.frameworks.joined(separator: ", "))\n"
            output += "Files: \(project.fileCount)\n\n"

            if !project.description.isEmpty {
                output += "Description:\n\(project.description)\n"
            }

            // Footer: tips and guidance
            let footer = Services.Formatter.Footer.Search.singleSource(Shared.Constants.SourcePrefix.samples)
            output += footer.formatText()

            return output
        }
    }
}
