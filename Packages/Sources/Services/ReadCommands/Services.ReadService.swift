import Foundation
import LoggingModels
import SampleIndexModels
import SearchModels
import ServicesModels
import SharedConstants

// MARK: - Unified read service

/// Cross-source document reader. Dispatches by either an explicit `--source`
/// (when the caller knows which DB to hit) or by inferring from the
/// identifier shape (URI vs. slugified ID vs. owner/repo path).
///
/// All three backends are DB-backed (search.db / samples.db / packages.db)
/// -- no file-system reads. That keeps `cupertino setup`-only installs
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
        /// Backend bucket the read dispatcher historically routed to.
        /// Three buckets (docs / samples / packages) aligned with the
        /// three monolithic DBs of the pre-per-source-split world.
        ///
        /// **2026-05-26 audit #1055**: this enum is no longer
        /// load-bearing for dispatch. `Services.ReadService.read` now
        /// iterates the registry and asks each provider's
        /// `Search.SourceReadStrategy` directly; the bucket-arm
        /// `if source == .docs/.samples/.packages` dispatch in the
        /// old `readFrom` was deleted. The struct + its `.docs /
        /// .samples / .packages` static lets stay for back-compat
        /// with callers (CLI's `cupertino read --source <id>` flag
        /// resolution + 2 test files) that pass it to identify the
        /// preferred provider family. New code should pass a
        /// source-id string directly via `explicitSourceID` instead.
        public struct Source: RawRepresentable, Sendable, Equatable, Hashable {
            public let rawValue: String
            public init(rawValue: String) {
                self.rawValue = rawValue
            }

            public static let docs = Source(rawValue: "docs")
            public static let samples = Source(rawValue: "samples")
            public static let packages = Source(rawValue: "packages")

            public static let allKnownCases: [Source] = [.docs, .samples, .packages]
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
        ///
        /// Post-2026-05-26 audit Finding 14.3: the classifier is now
        /// driven by a registry-supplied `[String: DatabaseDescriptor]`
        /// dict (source-id → destinationDB). Pre-fix this method had a
        /// hardcoded 9-arm switch enumerating every shipped source-id
        /// — adding a new source required editing this file. Now the
        /// CLI composition root builds the dict from the production
        /// source registry; the dispatcher classifies on the
        /// destinationDB (3 stable bucket cases: `.packages`,
        /// `.appleSampleCode`, default → docs).
        ///
        /// `apple-sample-code` is accepted as a legacy alias for
        /// `samples` because both clients pass the canonical id AND
        /// the descriptor id depending on the call path.
        public static func resolveSource(
            _ raw: String?,
            destinationsByID: [String: Shared.Models.DatabaseDescriptor]
        ) throws -> Source? {
            guard let raw else { return nil }
            // Legacy alias: `apple-sample-code` rolls into `samples`.
            let canonical = raw == Shared.Constants.SourcePrefix.appleSampleCode
                ? Shared.Constants.SourcePrefix.samples
                : raw
            guard let destination = destinationsByID[canonical] else {
                throw ReadError.unknownSource(raw)
            }
            // 3 stable bucket arms aligned with the 3 backend handlers
            // (docs reader / samples reader / packages reader). Adding
            // a new source within an existing DB family flows through
            // automatically; only a brand-new DB family would require
            // a new bucket case (and a corresponding new backend
            // handler — that's a fundamental architecture change, not
            // a routine source addition).
            switch destination {
            case .packages:
                return .packages
            case .appleSampleCode:
                return .samples
            default:
                return .docs
            }
        }

        /// 2026-05-26 audit #1055: the Services-side
        /// `PackageFileLookupStrategy` protocol moved to
        /// `Search.PackageFileLookupStrategy` (in SearchModels) so
        /// per-source read strategies in source targets can reference
        /// it without depending on Services. CLI's
        /// `LivePackageFileLookupStrategy` was updated to conform to
        /// the SearchModels protocol.
        public typealias PackageFileLookupStrategy = Search.PackageFileLookupStrategy

        /// Read a document by identifier. When `explicit` is provided the
        /// matching backend is used; otherwise we infer:
        /// 1. URI scheme present → docs.
        /// 2. Else: try samples first; fall through to packages on miss.
        ///
        /// `dbURL`, `samplesDB`, `packagesDB` are all required: callers
        /// must resolve the URLs at their composition root and supply them
        /// here. Pre-#535 these were `URL?` with internal fallbacks to
        /// `Shared.Constants.default*` / `Sample.Index.defaultDatabasePath`
        /// (a Service Locator shape per Seemann 2011 ch. 5); strict DI gives
        /// the caller responsibility for path resolution.
        ///
        /// `dbURLs` (post-#1039) is the per-source docs DB map:
        /// `[sourceID: URL]` keyed by `SourceProvider.definition.id`
        /// (e.g. `apple-docs` -> `apple-documentation.db`, `hig` ->
        /// `hig.db`). When non-nil AND the URI's scheme matches a key,
        /// the docs read routes to the matching per-source DB. When
        /// nil OR the URI's scheme isn't in the map, falls back to
        /// `dbURL` (the legacy monolithic search.db path; required
        /// for the pre-#1037 migration window + tests that pin the
        /// old shape). Defaulted nil so existing callers keep working
        /// without changes.
        public static func read(
            identifier rawIdentifier: String,
            explicit: Source?,
            format: Search.DocumentFormat,
            dbURL: URL,
            samplesDB: URL,
            packagesDB: URL,
            searchDatabaseFactory: any Search.DatabaseFactory,
            sampleDatabaseFactory: any Sample.Index.DatabaseFactory,
            packageFileLookup: any PackageFileLookupStrategy,
            dbURLs: [String: URL]? = nil,
            explicitDocsSourceID: String? = nil,
            providers: [any Search.SourceProvider]
        ) async throws -> Result {
            // #587: accept canonical Apple Developer web URLs by
            // converting them to the lossless `apple-docs://...` URI
            // before the regular dispatch.
            let identifier = Self.normalizeIdentifier(rawIdentifier)

            // #1039: resolve the docs DB URL once. Per-source routing
            // happens via the URI scheme or the `explicitDocsSourceID`.
            let resolvedDocsDB = resolveDBURL(
                identifier: identifier,
                explicitSourceID: explicitDocsSourceID,
                fallback: dbURL,
                dbURLs: dbURLs
            )

            // 2026-05-26 audit #1055: build the read env once and
            // hand it to per-source `Search.SourceReadStrategy`
            // concretes via the registry. Pre-fix this dispatched
            // through 3 hardcoded `if source == .docs/.samples/.packages`
            // arms; post-fix `runProviderStrategy` walks one provider
            // at a time and lets each strategy decide whether the
            // identifier is its concern.
            let docsLookup = LiveDocsLookupStrategy(searchDatabaseFactory: searchDatabaseFactory)
            let sampleLookup = LiveSampleLookupStrategy(sampleDatabaseFactory: sampleDatabaseFactory)

            // The legacy `dbURLs` map flows through to the env
            // so `Search.DocsReadStrategy` resolves per-source DBs.
            // When the caller didn't supply one (pre-#1037 tests),
            // the fallback `dbURL` URL is used for every docs id.
            let env = Search.ReadEnvironment(
                identifier: identifier,
                format: format,
                dbURLs: dbURLs ?? [:],
                fallbackSearchDB: resolvedDocsDB,
                samplesDB: samplesDB,
                packagesDB: packagesDB,
                docsLookup: docsLookup,
                sampleLookup: sampleLookup,
                packageFileLookup: packageFileLookup,
                allowFallback: explicit == nil,
                logger: LoggingModels.Logging.NoopRecording()
            )

            // Pick the candidate providers based on explicit hints.
            let candidates: [any Search.SourceProvider]
            if let explicitDocsSourceID, let specific = providers.first(where: { $0.definition.id == explicitDocsSourceID }) {
                // Single-source override (--source <id>); only that
                // provider runs.
                candidates = [specific]
            } else if let explicit {
                // Legacy bucket-narrowed (--source explicit value
                // resolved through legacyBucket).
                candidates = providers.filter { Self.legacyBucket(for: $0) == explicit }
            } else if identifier.contains("://") {
                // URI form: route to docs-tier providers.
                candidates = providers.filter { Self.legacyBucket(for: $0) == .docs }
            } else {
                // Auto-source: try samples → packages → docs.
                candidates = Self.autoSourceOrder(providers: providers)
            }

            // Walk each candidate. The first non-nil strategy result
            // wins; nil means "not my concern, try the next".
            for provider in candidates {
                do {
                    if let result = try await runProviderStrategy(provider: provider, env: env) {
                        return result
                    }
                } catch {
                    // For explicit-source reads the caller wants the
                    // error surfaced (no fallback). For auto-source
                    // / URI reads, swallow and try the next strategy.
                    if explicit != nil || explicitDocsSourceID != nil {
                        throw error
                    }
                }
            }

            // No provider claimed the identifier.
            if let explicit {
                switch explicit {
                case .samples: throw ReadError.samplesNotFound(identifier: identifier)
                case .packages: throw ReadError.packagesNotFound(identifier: identifier)
                default: throw ReadError.docsNotFound(identifier: identifier)
                }
            }
            throw ReadError.notFoundAnywhere(identifier: identifier)
        }

        /// #1039: resolve the docs DB URL for a read. Per-source DB
        /// lookup happens in two ways:
        ///
        /// 1. **Explicit source disambiguator** (`--source <id>` on the
        ///    CLI): when `explicitSourceID` matches a key in the map,
        ///    return that URL. Covers the `cupertino read swiftui-foo
        ///    --source hig` shape where the identifier has no URI
        ///    scheme.
        ///
        /// 2. **URI scheme extraction**: when the identifier carries
        ///    a `<scheme>://...` shape, extract the scheme and look it
        ///    up in the map. Covers `cupertino read hig://...`.
        ///
        /// Falls back to `fallback` (the legacy `dbURL` URL) when
        /// neither path resolves. Made `public static` so tests can
        /// pin the resolution logic without standing up the full read
        /// pipeline. Round-14/16 critic + this commit's round-17
        /// findings #1 and #3 closed by this signature.
        public static func resolveDBURL(
            identifier: String,
            explicitSourceID: String? = nil,
            fallback: URL,
            dbURLs: [String: URL]?
        ) -> URL {
            guard let dbURLs, !dbURLs.isEmpty else { return fallback }
            if let explicitSourceID, let url = dbURLs[explicitSourceID] {
                return url
            }
            guard let schemeEnd = identifier.range(of: "://") else { return fallback }
            let scheme = String(identifier[..<schemeEnd.lowerBound])
            return dbURLs[scheme] ?? fallback
        }

        // MARK: - Identifier normalisation (#587)

        /// Convert a canonical Apple Developer web URL into the lossless
        /// `apple-docs://...` URI shape; pass anything else through
        /// untouched.
        ///
        /// Examples:
        ///
        ///     "https://developer.apple.com/documentation/swiftui/view"
        ///       → "apple-docs://swiftui/view"
        ///
        ///     "apple-docs://swiftui/view"   →  pass-through
        ///     "owner/repo/file.swift"        →  pass-through (package id)
        ///     "swiftui-landmarks-sample"     →  pass-through (sample id)
        ///
        /// Non-Apple web URLs (Hacker News, GitHub, anything else)
        /// also pass through; the existing dispatch will reject them
        /// later via the per-source backends as it always has.
        static func normalizeIdentifier(_ raw: String) -> String {
            guard raw.hasPrefix("https://") || raw.hasPrefix("http://") else {
                return raw
            }
            guard let url = URL(string: raw),
                  let uri = Shared.Models.URLUtilities.appleDocsURI(from: url)
            else {
                return raw
            }
            return uri
        }

        // MARK: - Registry-driven dispatch

        /// 2026-05-26 audit #1055: dispatch a single provider's read
        /// strategy. Replaces the pre-fix 3-arm bucket dispatch in
        /// the old `readFrom(source:)`. Returns nil when the
        /// provider's strategy says "not my concern"; throws when
        /// the strategy itself fails.
        private static func runProviderStrategy(
            provider: any Search.SourceProvider,
            env: Search.ReadEnvironment
        ) async throws -> Result? {
            guard let strategy = provider.makeReadStrategy() else { return nil }
            guard let result = try await strategy.read(env: env) else { return nil }
            // Map the per-source strategy result to the legacy
            // `Source` bucket for back-compat with callers that key
            // off the resolvedSource value. The provider's
            // destinationDB drives the mapping (docs.search-tier
            // sources resolve to `.docs`; samples/packages to their
            // own bucket).
            let bucket = Self.legacyBucket(for: provider)
            return Result(content: result.content, resolvedSource: bucket)
        }

        /// Map a registered provider to the legacy `Source` bucket
        /// the result type still carries for back-compat. Drives
        /// `Result.resolvedSource` for callers that switch on the
        /// 3 historical buckets. New consumers should read the
        /// `definition.id` from the provider directly.
        private static func legacyBucket(for provider: any Search.SourceProvider) -> Source {
            switch provider.destinationDB {
            case .packages: return .packages
            case .appleSampleCode: return .samples
            default: return .docs
            }
        }

        /// Build the canonical try-order for the auto-source flow.
        /// Pre-fix: try samples → packages → docs. Post-fix: same
        /// order, but each "bucket" expands to every registered
        /// provider in that family (so 6 docs-tier sources get
        /// tried). The order is preserved because the legacy
        /// auto-source semantics matched samples-shaped identifiers
        /// first, then packages-shaped, then docs URIs.
        private static func autoSourceOrder(
            providers: [any Search.SourceProvider]
        ) -> [any Search.SourceProvider] {
            let samples = providers.filter { Self.legacyBucket(for: $0) == .samples }
            let packages = providers.filter { Self.legacyBucket(for: $0) == .packages }
            let docs = providers.filter { Self.legacyBucket(for: $0) == .docs }
            return samples + packages + docs
        }
    }
}
