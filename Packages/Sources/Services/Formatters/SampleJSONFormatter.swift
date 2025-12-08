import Foundation
import SampleIndex
import Shared

// MARK: - Sample Search JSON Formatter

/// Formats sample search results as JSON
public struct SampleSearchJSONFormatter: ResultFormatter {
    private let query: String
    private let framework: String?

    public init(query: String, framework: String? = nil) {
        self.query = query
        self.framework = framework
    }

    public func format(_ result: SampleSearchResult) -> String {
        struct Output: Encodable {
            let query: String
            let framework: String?
            let projects: [ProjectOutput]
            let files: [FileOutput]
        }

        struct ProjectOutput: Encodable {
            let id: String
            let title: String
            let description: String
            let frameworks: [String]
            let fileCount: Int
        }

        struct FileOutput: Encodable {
            let projectId: String
            let path: String
            let filename: String
            let snippet: String
            let rank: Double
        }

        let output = Output(
            query: query,
            framework: framework,
            projects: result.projects.map {
                ProjectOutput(
                    id: $0.id,
                    title: $0.title,
                    description: $0.description,
                    frameworks: $0.frameworks,
                    fileCount: $0.fileCount
                )
            },
            files: result.files.map {
                FileOutput(
                    projectId: $0.projectId,
                    path: $0.path,
                    filename: $0.filename,
                    snippet: $0.snippet,
                    rank: $0.rank
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(output)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{ \"error\": \"Failed to encode JSON: \(error.localizedDescription)\" }"
        }
    }
}

// MARK: - Sample List JSON Formatter

/// Formats sample project list as JSON
public struct SampleListJSONFormatter: ResultFormatter {
    public init() {}

    public func format(_ projects: [SampleIndex.Project]) -> String {
        struct ProjectOutput: Encodable {
            let id: String
            let title: String
            let description: String
            let frameworks: [String]
            let fileCount: Int
        }

        let output = projects.map {
            ProjectOutput(
                id: $0.id,
                title: $0.title,
                description: $0.description,
                frameworks: $0.frameworks,
                fileCount: $0.fileCount
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(output)
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            return "{ \"error\": \"Failed to encode JSON: \(error.localizedDescription)\" }"
        }
    }
}

// MARK: - Sample Project JSON Formatter

/// Formats a single sample project as JSON
public struct SampleProjectJSONFormatter: ResultFormatter {
    public init() {}

    public func format(_ project: SampleIndex.Project) -> String {
        struct ProjectOutput: Encodable {
            let id: String
            let title: String
            let description: String
            let frameworks: [String]
            let fileCount: Int
        }

        let output = ProjectOutput(
            id: project.id,
            title: project.title,
            description: project.description,
            frameworks: project.frameworks,
            fileCount: project.fileCount
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(output)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{ \"error\": \"Failed to encode JSON: \(error.localizedDescription)\" }"
        }
    }
}

// MARK: - Sample File JSON Formatter

/// Formats a sample file as JSON
public struct SampleFileJSONFormatter: ResultFormatter {
    public init() {}

    public func format(_ file: SampleIndex.File) -> String {
        struct FileOutput: Encodable {
            let projectId: String
            let path: String
            let filename: String
            let content: String
        }

        let output = FileOutput(
            projectId: file.projectId,
            path: file.path,
            filename: file.filename,
            content: file.content
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(output)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{ \"error\": \"Failed to encode JSON: \(error.localizedDescription)\" }"
        }
    }
}
