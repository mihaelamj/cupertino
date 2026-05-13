import Foundation
import SampleIndex
import SearchModels
import SharedConstants
import SharedCore

// MARK: - Unified read service

/// Cross-source document reader. Dispatches by either an explicit `--source`
/// (when the caller knows which DB to hit) or by inferring from the
/// identifier shape (URI vs. slugified ID vs. owner/repo path).
///
/// All three backends are DB-backed (search.db / samples.db / packages.db)
/// — no file-system reads. That keeps `cupertino setup`-only installs
/// working: the user never has to run `cupertino fetch` if they're happy
/// with the bundled corpus.
///
/// Lives in `Services` because it composes existing per-source readers
/// (`Services.DocsSearchService.read`, `Sample.Search.Service.getProject` /
/// `getFile`, `Search.PackageQuery.fileContent`). Both `cupertino read`
/// (CLI) and the MCP layer call into this one entry point so behaviour
/// stays identical across transports.
extension Services {
    public enum ReadService {
        public enum Source: String, Sendable, Equatable {
            case docs
            case samples
            case packages
        }

        public enum ReadError: Error {
            case docsNotFound(identifier: String)
            case samplesNotFound(identifier: String)
            case packagesNotFound(identifier: String)
            case packagesIdentifierInvalid(identifier: String)
            /// Auto-source mode tried every backend and none returned a hit.
            case notFoundAnywhere(identifier: String)
            case unknownSource(String)
            case backendFailed(String)
        }

        public struct Result: Sendable, Equatable {
            public let content: String
            public let resolvedSource: Source
            public init(content: String, resolvedSource: Source) {
                self.content = content
                self.resolvedSource = resolvedSource
            }
        }

        /// Map a CLI `--source <name>` value to a backend, or nil for "infer".
        /// Throws `.unknownSource` for values that don't match a known source.
        public static func resolveSource(_ raw: String?) throws -> Source? {
            guard let raw else { return nil }
            switch raw {
            case Shared.Constants.SourcePrefix.appleDocs,
                 Shared.Constants.SourcePrefix.appleArchive,
                 Shared.Constants.SourcePrefix.hig,
                 Shared.Constants.SourcePrefix.swiftEvolution,
                 Shared.Constants.SourcePrefix.swiftOrg,
                 Shared.Constants.SourcePrefix.swiftBook:
                return .docs
            case Shared.Constants.SourcePrefix.samples,
                 Shared.Constants.SourcePrefix.appleSampleCode:
                return .samples
            case Shared.Constants.SourcePrefix.packages:
                return .packages
            default:
                throw ReadError.unknownSource(raw)
            }
        }

        /// Closure that resolves a file inside `packages.db` to its raw
        /// content. Production composition root (CLI) wires this as a
        /// thin wrapper around `Search.PackageQuery(dbPath:).fileContent(...)`,
        /// then `disconnect()`. ReadService doesn't import the Search
        /// target, so the actor stays opaque behind this seam.
        public typealias PackageFileLookup = @Sendable (_ dbURL: URL, _ owner: String, _ repo: String, _ relpath: String) async throws -> String?

        /// Read a document by identifier. When `explicit` is provided the
        /// matching backend is used; otherwise we infer:
        /// 1. URI scheme present → docs.
        /// 2. Else: try samples first; fall through to packages on miss.
        public static func read(
            identifier: String,
            explicit: Source?,
            format: Search.DocumentFormat,
            searchDB: URL?,
            samplesDB: URL?,
            packagesDB: URL?,
            packageFileLookup: PackageFileLookup,
        ) async throws -> Result {
            if let explicit {
                return try await readFrom(
                    source: explicit,
                    identifier: identifier,
                    format: format,
                    searchDB: searchDB,
                    samplesDB: samplesDB,
                    packagesDB: packagesDB,
                    allowFallback: false,
                    packageFileLookup: packageFileLookup,
                )
            }

            if identifier.contains("://") {
                return try await readFrom(
                    source: .docs,
                    identifier: identifier,
                    format: format,
                    searchDB: searchDB,
                    samplesDB: samplesDB,
                    packagesDB: packagesDB,
                    allowFallback: false,
                    packageFileLookup: packageFileLookup,
                )
            }

            do {
                return try await readFrom(
                    source: .samples,
                    identifier: identifier,
                    format: format,
                    searchDB: searchDB,
                    samplesDB: samplesDB,
                    packagesDB: packagesDB,
                    allowFallback: true,
                    packageFileLookup: packageFileLookup,
                )
            } catch ReadError.samplesNotFound, ReadError.packagesNotFound,
                ReadError.packagesIdentifierInvalid {
                // Auto-source: try packages explicitly as a last resort.
            }
            return try await readFrom(
                source: .packages,
                identifier: identifier,
                format: format,
                searchDB: searchDB,
                samplesDB: samplesDB,
                packagesDB: packagesDB,
                allowFallback: false,
                packageFileLookup: packageFileLookup,
            )
        }

        // MARK: - Per-source reads

        private static func readFrom(
            source: Source,
            identifier: String,
            format: Search.DocumentFormat,
            searchDB: URL?,
            samplesDB: URL?,
            packagesDB: URL?,
            allowFallback: Bool,
            packageFileLookup: PackageFileLookup,
        ) async throws -> Result {
            switch source {
            case .docs:
                return try await readFromDocs(
                    identifier: identifier,
                    format: format,
                    searchDB: searchDB
                )
            case .samples:
                return try await readFromSamples(
                    identifier: identifier,
                    samplesDB: samplesDB,
                    allowFallback: allowFallback,
                    packagesDB: packagesDB,
                    packageFileLookup: packageFileLookup,
                )
            case .packages:
                return try await readFromPackages(
                    identifier: identifier,
                    packagesDB: packagesDB,
                    packageFileLookup: packageFileLookup,
                )
            }
        }

        private static func readFromDocs(
            identifier: String,
            format: Search.DocumentFormat,
            searchDB: URL?
        ) async throws -> Result {
            let content = try await Services.ServiceContainer.withDocsService(
                dbPath: searchDB?.path
            ) { service in
                try await service.read(uri: identifier, format: format)
            }
            guard let content else {
                throw ReadError.docsNotFound(identifier: identifier)
            }
            return Result(content: content, resolvedSource: .docs)
        }

        private static func readFromSamples(
            identifier: String,
            samplesDB: URL?,
            allowFallback: Bool,
            packagesDB: URL?,
            packageFileLookup: PackageFileLookup,
        ) async throws -> Result {
            let dbURL = samplesDB ?? Sample.Index.defaultDatabasePath
            guard FileManager.default.fileExists(atPath: dbURL.path) else {
                if allowFallback {
                    return try await readFromPackages(
                        identifier: identifier,
                        packagesDB: packagesDB,
                        packageFileLookup: packageFileLookup,
                    )
                }
                throw ReadError.samplesNotFound(identifier: identifier)
            }

            if let slashIdx = identifier.firstIndex(of: "/") {
                let projectId = String(identifier[..<slashIdx])
                let path = String(identifier[identifier.index(after: slashIdx)...])
                let file = try await Services.ServiceContainer.withSampleService(dbPath: dbURL) { service in
                    try await service.getFile(projectId: projectId, path: path)
                }
                if let file {
                    return Result(content: file.content, resolvedSource: .samples)
                }
            } else {
                let project = try await Services.ServiceContainer.withSampleService(dbPath: dbURL) { service in
                    try await service.getProject(id: identifier)
                }
                if let project {
                    return Result(
                        content: project.readme ?? project.description,
                        resolvedSource: .samples
                    )
                }
            }

            if allowFallback {
                return try await readFromPackages(
                    identifier: identifier,
                    packagesDB: packagesDB,
                    packageFileLookup: packageFileLookup,
                )
            }
            throw ReadError.samplesNotFound(identifier: identifier)
        }

        private static func readFromPackages(
            identifier: String,
            packagesDB: URL?,
            packageFileLookup: PackageFileLookup,
        ) async throws -> Result {
            // Identifier shape: `<owner>/<repo>/<relpath>`. Anything else is
            // not a valid package identifier — auto-source mode bails here.
            let parts = identifier.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3 else {
                throw ReadError.packagesIdentifierInvalid(identifier: identifier)
            }
            let owner = String(parts[0])
            let repo = String(parts[1])
            let relpath = String(parts[2])

            let dbURL = packagesDB ?? Shared.Constants.defaultPackagesDatabase
            guard FileManager.default.fileExists(atPath: dbURL.path) else {
                throw ReadError.packagesNotFound(identifier: identifier)
            }

            let content: String?
            do {
                content = try await packageFileLookup(dbURL, owner, repo, relpath)
            } catch {
                throw ReadError.backendFailed("packages.db query failed: \(error.localizedDescription)")
            }

            guard let content else {
                throw ReadError.packagesNotFound(identifier: identifier)
            }
            return Result(content: content, resolvedSource: .packages)
        }
    }
}
