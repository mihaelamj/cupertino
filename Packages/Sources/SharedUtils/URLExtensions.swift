import Foundation

// MARK: - URL Extension for Tilde Expansion

extension URL {
    /// Expand tilde (~) in file paths
    public var expandingTildeInPath: URL {
        if path.hasPrefix("~") {
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            let relativePath = String(path.dropFirst(2)) // Remove "~/"
            return homeDirectory.appendingPathComponent(relativePath)
        }
        return self
    }

    /// Build a `URL` from a string the caller asserts is well-formed.
    ///
    /// Use for URLs constructed from compile-time literals or from internal
    /// constants (e.g. `Shared.Constants.BaseURL.*`) interpolated with
    /// sanitized components. Equivalent to `URL(string: s)!`, but:
    ///
    /// - communicates the "known-good" contract at the call site,
    /// - crashes with a message naming the offending string and the source
    ///   location, instead of a bare "unexpectedly found nil while unwrapping
    ///   an Optional value",
    /// - localizes the force-unwrap to a single audited place.
    ///
    /// **Do not use for URLs sourced from external/runtime data** (parsed
    /// JSON, HTTP responses, indexed page metadata): a malformed string is
    /// a recoverable condition there, not a programmer error. Use plain
    /// `URL(string:)` + `guard let` in those cases.
    public static func knownGood(
        _ string: String,
        file: StaticString = #file,
        line: UInt = #line
    ) -> URL {
        guard let url = URL(string: string) else {
            fatalError("URL.knownGood: malformed URL string '\(string)'", file: file, line: line)
        }
        return url
    }
}
