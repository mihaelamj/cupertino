import Foundation

extension Distribution {
    /// Typed errors emitted by `SetupService`, `ArtifactDownloader`, and
    /// `ArtifactExtractor`. Mirrors the `SetupError` that lived in
    /// `CLI.SetupCommand` pre-#246.
    public enum SetupError: Error, CustomStringConvertible, Equatable {
        case invalidURL(String)
        case invalidResponse
        case notFound(URL)
        case httpError(Int)
        case extractionFailed
        case missingFile(String)

        public var description: String {
            switch self {
            case .invalidURL(let url):
                return "Invalid URL: \(url)"
            case .invalidResponse:
                return "Invalid response from server"
            case .notFound(let url):
                return """
                File not found: \(url)

                The release may not exist yet. Check: https://github.com/mihaelamj/cupertino-docs/releases
                """
            case .httpError(let code):
                return "HTTP error: \(code)"
            case .extractionFailed:
                return "Failed to extract zip file"
            case .missingFile(let filename):
                return "Expected file not found after extraction: \(filename)"
            }
        }
    }
}
