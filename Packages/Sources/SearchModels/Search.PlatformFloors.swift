import Foundation

// MARK: - Search.PlatformFloors (#962 / #226)

extension Search {
    /// The five `min_<platform>` version floors shared by the unified `search`
    /// tool and the AST search tools, across BOTH the MCP and CLI surfaces.
    /// Values are validated to a numeric semver-prefix at construction so a
    /// malformed floor cannot silently no-op past `Search.PlatformFilter.passes`.
    public struct PlatformFloors: Sendable, Equatable {
        public let minIOS: String?
        public let minMacOS: String?
        public let minTvOS: String?
        public let minWatchOS: String?
        public let minVisionOS: String?

        public var isAnySet: Bool {
            minIOS != nil || minMacOS != nil || minTvOS != nil || minWatchOS != nil || minVisionOS != nil
        }

        /// - Throws: `Search.Error.invalidQuery` when any value is present but
        ///   is not a numeric semver-prefix (e.g. `"v18"`, `"18.0a"`, `""`).
        public init(
            minIOS: String? = nil,
            minMacOS: String? = nil,
            minTvOS: String? = nil,
            minWatchOS: String? = nil,
            minVisionOS: String? = nil
        ) throws {
            self.minIOS = try Self.validatedValue(minIOS, name: "min_ios")
            self.minMacOS = try Self.validatedValue(minMacOS, name: "min_macos")
            self.minTvOS = try Self.validatedValue(minTvOS, name: "min_tvos")
            self.minWatchOS = try Self.validatedValue(minWatchOS, name: "min_watchos")
            self.minVisionOS = try Self.validatedValue(minVisionOS, name: "min_visionos")
        }

        /// Reject empty / malformed `min_<platform>` values up-front so they
        /// cannot silently no-op past the filter. A value is acceptable when
        /// its trimmed form is a numeric semver-prefix: `<digits>(.<digits>)*`
        /// (major, major.minor, or major.minor.patch). Returns the trimmed
        /// value (or nil). The MCP provider delegates to this and re-wraps the
        /// failure in its own `ToolError` frame; the CLI surfaces it directly.
        public static func validatedValue(_ raw: String?, name: String) throws -> String? {
            guard let raw else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw Search.Error.invalidQuery(
                    "Platform version filter \(name) must not be empty or whitespace-only; omit it or pass a numeric version like \"18.0\"."
                )
            }
            let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isWholeNumber) }) else {
                throw Search.Error.invalidQuery(
                    "Platform version filter \(name) must be a numeric semver-prefix (e.g. \"18\", \"18.0\", \"18.0.1\"); got \"\(raw)\"."
                )
            }
            return trimmed
        }
    }
}

// MARK: - Search.Database platform-floor application

extension Search.Database {
    /// Filter a `[SymbolSearchResult]` by platform floors. Short-circuits when
    /// no floor is set (the common case). When set, batch-fetches `min_*` per
    /// result URI in one query, then keeps rows that pass
    /// `Search.PlatformFilter.passes`. Shared by the MCP AST tool handlers and
    /// the AST CLI subcommands so both surfaces filter identically.
    public func applyingPlatformFloors(
        to results: [Search.SymbolSearchResult],
        floors: Search.PlatformFloors
    ) async throws -> [Search.SymbolSearchResult] {
        guard floors.isAnySet, !results.isEmpty else { return results }
        let minima = try await fetchPlatformMinima(uris: results.map(\.docUri))
        return results.filter { row in
            Search.PlatformFilter.passes(
                minima: minima[row.docUri],
                minIOS: floors.minIOS,
                minMacOS: floors.minMacOS,
                minTvOS: floors.minTvOS,
                minWatchOS: floors.minWatchOS,
                minVisionOS: floors.minVisionOS
            )
        }
    }
}
