import Foundation

// MARK: - Release Publishing Error

extension Release.Publishing {
    enum Error: Swift.Error, CustomStringConvertible {
        case missingDatabase(String, String)
        case zipFailed
        case sha256Failed
        case missingToken
        case versionNotFound
        case apiError(String)

        var description: String {
            switch self {
            case let .missingDatabase(filename, dir):
                "Database not found: \(filename) in \(dir)"
            case .zipFailed:
                "Failed to create zip file"
            case .sha256Failed:
                "Failed to calculate SHA256"
            case .missingToken:
                """
                No GitHub token found.

                Set CUPERTINO_DOCS_TOKEN (preferred) or GITHUB_TOKEN:
                Create a token at: https://github.com/settings/tokens
                Then: export CUPERTINO_DOCS_TOKEN=your_token
                """
            case .versionNotFound:
                "Could not find databaseVersion in Constants.swift"
            case let .apiError(message):
                "GitHub API error: \(message)"
            }
        }
    }
}
