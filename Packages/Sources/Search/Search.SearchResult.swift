import Foundation
import SearchModels
import SharedConstants

// MARK: - Framework Availability (Search Module)

/// Minimum platform versions for a framework (used for availability filtering)
extension Search {
    public struct FrameworkAvailability: Sendable {
        public let minIOS: String?
        public let minMacOS: String?
        public let minTvOS: String?
        public let minWatchOS: String?
        public let minVisionOS: String?

        public init(
            minIOS: String? = nil,
            minMacOS: String? = nil,
            minTvOS: String? = nil,
            minWatchOS: String? = nil,
            minVisionOS: String? = nil
        ) {
            self.minIOS = minIOS
            self.minMacOS = minMacOS
            self.minTvOS = minTvOS
            self.minWatchOS = minWatchOS
            self.minVisionOS = minVisionOS
        }

        /// Empty availability (no platform data)
        public static let empty = FrameworkAvailability()
    }
}

// MARK: - Sample Code Search Result

/// A sample code search result with metadata and local file information
extension Search {
    public struct SampleCodeResult: Codable, Sendable, Identifiable {
        public let id: UUID
        public let url: String
        public let framework: String
        public let title: String
        public let description: String
        public let zipFilename: String
        public let webURL: String
        public let localPath: String?
        public let hasLocalFile: Bool
        public let rank: Double // BM25 score (negative, closer to 0 = better match)

        public init(
            id: UUID = UUID(),
            url: String,
            framework: String,
            title: String,
            description: String,
            zipFilename: String,
            webURL: String,
            localPath: String? = nil,
            hasLocalFile: Bool = false,
            rank: Double
        ) {
            self.id = id
            self.url = url
            self.framework = framework
            self.title = title
            self.description = description
            self.zipFilename = zipFilename
            self.webURL = webURL
            self.localPath = localPath
            self.hasLocalFile = hasLocalFile
            self.rank = rank
        }

        /// Inverted score (higher = better match, for easier interpretation)
        public var score: Double {
            -rank
        }

        /// Get the download URL - prefers local file:// if available, otherwise web URL
        public var downloadURL: String {
            if let localPath {
                return "file://\(localPath)"
            }
            return webURL
        }
    }
}

// MARK: - Package Search Result

/// A Swift package search result with metadata
extension Search {
    public struct PackageResult: Codable, Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let owner: String
        public let repositoryURL: String
        public let documentationURL: String?
        public let stars: Int
        public let isAppleOfficial: Bool
        public let description: String?

        public init(
            id: Int,
            name: String,
            owner: String,
            repositoryURL: String,
            documentationURL: String? = nil,
            stars: Int,
            isAppleOfficial: Bool,
            description: String? = nil
        ) {
            self.id = id
            self.name = name
            self.owner = owner
            self.repositoryURL = repositoryURL
            self.documentationURL = documentationURL
            self.stars = stars
            self.isAppleOfficial = isAppleOfficial
            self.description = description
        }
    }
}

// MARK: - Search Errors

extension Search {
    public enum Error: Swift.Error, LocalizedError {
        case databaseNotInitialized
        case sqliteError(String)
        case prepareFailed(String)
        case insertFailed(String)
        case searchFailed(String)
        case invalidQuery(String)
        /// #673 Phase E — typed schema-mismatch error replacing the
        /// generic `.sqliteError("Database schema version X; binary
        /// expects version Y. …")` cases that previously bubbled out
        /// of `Search.Index.Migrations.runMigrations`. Carrying the
        /// raw version numbers + DB path lets the CLI top-level
        /// (`Cupertino.main`) print a user-friendly remediation hint
        /// AND exit with `EX_DATAERR` (65) so scripts can detect the
        /// class without parsing a string.
        ///
        /// Direction matters:
        ///   - `currentDBVersion > expectedBinaryVersion` → binary is
        ///     stale; suggest `brew upgrade cupertino` (or rebuild
        ///     the binary in a dev setup).
        ///   - `currentDBVersion < expectedBinaryVersion` → DB is
        ///     stale; suggest `cupertino setup` to download a matching
        ///     pre-built bundle.
        ///
        /// The errorDescription wires both branches into a single
        /// user-visible sentence; the CLI's catch path adds the exit
        /// code + suppresses the Swift stack trace.
        case schemaVersionMismatch(currentDBVersion: Int, expectedBinaryVersion: Int, dbPath: String)

        public var errorDescription: String? {
            switch self {
            case .databaseNotInitialized:
                return "Search database has not been initialized. Run 'cupertino build-index' first."
            case .sqliteError(let msg):
                return "SQLite error: \(msg)"
            case .prepareFailed(let msg):
                return "Failed to prepare SQL statement: \(msg)"
            case .insertFailed(let msg):
                return "Failed to insert document: \(msg)"
            case .searchFailed(let msg):
                return "Search query failed: \(msg)"
            case .invalidQuery(let msg):
                return "Invalid search query: \(msg)"
            case .schemaVersionMismatch(let dbVersion, let binaryVersion, let dbPath):
                if dbVersion > binaryVersion {
                    // DB is newer than binary — installed cupertino can't read it.
                    return """
                    Database schema mismatch: search.db at \(dbPath) is at schema version \(dbVersion), \
                    but this cupertino binary only understands up to version \(binaryVersion).

                    Remediation:
                      • If you installed via Homebrew: `brew upgrade cupertino`
                      • If you build cupertino from source: rebuild your binary so it matches the bundle's schema
                      • To force-reset to the binary's current schema: `rm '\(dbPath)' && cupertino setup`
                    """
                } else {
                    // DB is older than binary — common after `brew upgrade cupertino` without a bundle refresh.
                    return """
                    Database schema mismatch: search.db at \(dbPath) is at schema version \(dbVersion), \
                    but this cupertino binary expects version \(binaryVersion).

                    Remediation:
                      • Download the matching pre-built bundle: `cupertino setup`
                      • Or rebuild from a local crawl: `rm '\(dbPath)' && cupertino save`
                    """
                }
            }
        }
    }
}
