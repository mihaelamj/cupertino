import Foundation

extension Distribution {
    /// Typed errors emitted by `SetupService`, `ArtifactDownloader`, and
    /// `ArtifactExtractor`. Mirrors the `SetupError` that lived in
    /// `CLI.SetupCommand` pre-#246. Pure value enum; foundation-only.
    public enum SetupError: Error, CustomStringConvertible, Equatable {
        case invalidURL(String)
        case invalidResponse
        case notFound(URL)
        case httpError(Int)
        case extractionFailed
        case missingFile(String)
        /// #673 Phase B — `unzip` ran past the configured deadline and
        /// was force-terminated. Distinguishes "unzip exited non-zero
        /// because the zip was malformed" (`.extractionFailed`) from
        /// "unzip hung past our patience and we killed it"
        /// (`.extractionTimeout`). Carries the deadline that fired.
        case extractionTimeout(seconds: Int)

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
            case .extractionTimeout(let seconds):
                return "unzip did not complete within \(seconds)s and was terminated. " +
                    "The archive may be corrupted, or extraction is unusually slow on this disk. " +
                    "Rerun `cupertino setup` to retry, or download manually from " +
                    "https://github.com/mihaelamj/cupertino-docs/releases."
            }
        }
    }
}
