import Foundation
import SampleIndex
import Shared

// MARK: - Shared JSON Output Types

/// Shared project output for JSON encoding
private struct ProjectJSONOutput: Encodable {
    let id: String
    let title: String
    let description: String
    let frameworks: [String]
    let fileCount: Int

    init(from project: SampleIndex.Project) {
        id = project.id
        title = project.title
        description = project.description
        frameworks = project.frameworks
        fileCount = project.fileCount
    }
}

/// File output for JSON encoding (from SampleIndex.File)
private struct FileJSONOutput: Encodable {
    let projectId: String
    let path: String
    let filename: String
    let content: String

    init(from file: SampleIndex.File) {
        projectId = file.projectId
        path = file.path
        filename = file.filename
        content = file.content
    }
}

/// File search result output for JSON encoding (from FileSearchResult)
private struct FileSearchJSONOutput: Encodable {
    let projectId: String
    let path: String
    let filename: String
    let snippet: String
    let rank: Double

    init(from result: SampleIndex.Database.FileSearchResult) {
        projectId = result.projectId
        path = result.path
        filename = result.filename
        snippet = result.snippet
        rank = result.rank
    }
}

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
            let projects: [ProjectJSONOutput]
            let files: [FileSearchJSONOutput]
        }

        let output = Output(
            query: query,
            framework: framework,
            projects: result.projects.map { ProjectJSONOutput(from: $0) },
            files: result.files.map { FileSearchJSONOutput(from: $0) }
        )

        return encodeJSON(output)
    }
}

// MARK: - Sample List JSON Formatter

/// Formats sample project list as JSON
public struct SampleListJSONFormatter: ResultFormatter {
    public init() {}

    public func format(_ projects: [SampleIndex.Project]) -> String {
        let output = projects.map { ProjectJSONOutput(from: $0) }
        return encodeJSON(output)
    }
}

// MARK: - Sample Project JSON Formatter

/// Formats a single sample project as JSON
public struct SampleProjectJSONFormatter: ResultFormatter {
    public init() {}

    public func format(_ project: SampleIndex.Project) -> String {
        encodeJSON(ProjectJSONOutput(from: project))
    }
}

// MARK: - Sample File JSON Formatter

/// Formats a sample file as JSON
public struct SampleFileJSONFormatter: ResultFormatter {
    public init() {}

    public func format(_ file: SampleIndex.File) -> String {
        encodeJSON(FileJSONOutput(from: file))
    }
}

// MARK: - JSON Encoding Helper

/// Encodes any Encodable value to pretty-printed JSON string
private func encodeJSON(_ value: some Encodable, fallback: String = "{}") -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    do {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? fallback
    } catch {
        return "{ \"error\": \"Failed to encode JSON: \(error.localizedDescription)\" }"
    }
}
