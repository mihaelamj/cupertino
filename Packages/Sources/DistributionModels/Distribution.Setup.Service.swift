import Foundation
import SharedConstants

// MARK: - Distribution.Setup.Service: value types + Observer protocol

/// Sub-namespace grouping for setup-related types (Service + Error).
/// Post-#1042 type-name deepening: previously `Distribution.SetupService`
/// + `Distribution.SetupError` sat at the same nesting level; now
/// grouped under `Distribution.Setup.*`. Back-compat typealiases at
/// the bottom keep pre-rename call-sites compiling
/// (`Distribution.SetupService` -> `Distribution.Setup.Service`).
extension Distribution {
    public enum Setup {}
}

extension Distribution.Setup {
    /// `cupertino setup` orchestrator namespace. The concrete
    /// `run(...)` static function lives in the `Distribution` producer
    /// target as an extension on this enum. The value types
    /// (`Request`, `Outcome`, `Event`) plus the GoF Observer protocol
    /// (`EventObserving`) stay here in `DistributionModels` so any
    /// conformer can implement the protocol without `import Distribution`.
    public enum Service {
        /// What the caller asked for. Mirrors the `cupertino setup`
        /// flag shape so the CLI maps argv to this struct directly.
        public struct Request: Sendable {
            public let baseDir: URL
            public let currentDocsVersion: String
            public let docsReleaseBaseURL: String
            public let keepExisting: Bool
            /// Descriptors for every database the CLI must classify, download,
            /// and place. Ordered by the printable sequence the success-summary
            /// printer iterates. Composition-root injected (the CLI's
            /// `CLIImpl.Command.Setup.run` assembles the list and passes it
            /// in) so adding a 4th DB no longer touches `Distribution.Setup.Service.run`.
            ///
            /// **Required at construction; no default.** The other init
            /// parameters carry defaults (`currentDocsVersion`,
            /// `docsReleaseBaseURL`) that read from `Shared.Constants.App`
            /// immutable `static let` literal constants; those are
            /// version-roll metadata with a single source of truth, not
            /// the mutable process-wide config holders Rule 1 forbids, so
            /// an informational default is fine. `required` is different:
            /// it encodes which databases the CLI is currently shipping,
            /// an architectural decision the composition root must own.
            /// Hiding it inside the init as a default would make "add a
            /// 4th DB" appear at a hidden site instead of at the
            /// composition root. Test fixtures pass
            /// `[.search, .samples, .packages]` when exercising the
            /// production 3-DB shape.
            ///
            /// **Bundle-coupling assumption.** Setup downloads a single
            /// `cupertino-databases-vX.Y.Z.zip` shipped from
            /// `mihaelamj/cupertino-docs` releases. A descriptor passed here
            /// is assumed to arrive inside that bundle; per-descriptor
            /// download URLs are out-of-scope for this seam (future #248
            /// scope per the original proposal's `downloadURL` field).
            public let required: [Shared.Models.DatabaseDescriptor]

            public init(
                baseDir: URL,
                currentDocsVersion: String = Shared.Constants.App.databaseVersion,
                docsReleaseBaseURL: String = Shared.Constants.App.docsReleaseBaseURL,
                keepExisting: Bool = false,
                required: [Shared.Models.DatabaseDescriptor]
            ) {
                // Reject empty: a meaningless invocation. `classify`'s own
                // non-empty precondition would catch this later in the
                // pipeline (after `createDirectory` + `InstalledVersion.read`
                // already ran), but rejecting at the door gives a
                // Request-specific error before any side effects.
                precondition(
                    !required.isEmpty,
                    "Distribution.Setup.Service.Request.required must list at least one database"
                )
                // Reject duplicate-by-`id` (the routing key everywhere downstream:
                // `Outcome.path(forDatabaseId:)`, status classification). Full
                // struct equality (id + filename + displayName) is not enough
                // because a future code path could fork a descriptor with the
                // same id but a typo'd filename; the first id-match wins and
                // the second is silently shadowed.
                precondition(
                    Set(required.map(\.id)).count == required.count,
                    "Distribution.Setup.Service.Request.required carries duplicate descriptor ids: \(required.map(\.id))"
                )
                self.baseDir = baseDir
                self.currentDocsVersion = currentDocsVersion
                self.docsReleaseBaseURL = docsReleaseBaseURL
                self.keepExisting = keepExisting
                self.required = required
            }
        }

        /// One database entry in the Outcome's `databases` list. Carries
        /// the descriptor that identifies the database plus the on-disk
        /// URL where it landed.
        public struct DatabasePlacement: Sendable, Equatable {
            public let descriptor: Shared.Models.DatabaseDescriptor
            public let path: URL

            public init(descriptor: Shared.Models.DatabaseDescriptor, path: URL) {
                self.descriptor = descriptor
                self.path = path
            }
        }

        /// Outcome of a single `run` invocation. The CLI uses this to
        /// render the success summary and decide what hint to print.
        /// `databases` is ordered by the construction sequence in
        /// `Setup.Service.run`; the CLI's success-summary printer
        /// iterates the list rather than addressing 3 fixed fields, so
        /// adding a 4th DB never touches this struct (#248 second cut).
        ///
        /// **Equatable semantics:** `Outcome` derives `==` from the
        /// `databases` array, which is order-sensitive. Two Outcomes
        /// covering the same descriptors in a different order are
        /// NOT equal. Production code constructs the list in a single
        /// place (`Setup.Service.run`'s `placements` literal); call
        /// sites that compare Outcomes from heterogeneous constructions
        /// must align their construction order.
        public struct Outcome: Sendable, Equatable {
            public let databases: [DatabasePlacement]
            public let docsVersionWritten: String
            /// Hits when `keepExisting: true` and every DB was already
            /// present. The CLI uses this to skip the "downloaded" log.
            public let skippedDownload: Bool
            public let priorStatus: Distribution.InstalledVersion.Status

            public init(
                databases: [DatabasePlacement],
                docsVersionWritten: String,
                skippedDownload: Bool,
                priorStatus: Distribution.InstalledVersion.Status
            ) {
                self.databases = databases
                self.docsVersionWritten = docsVersionWritten
                self.skippedDownload = skippedDownload
                self.priorStatus = priorStatus
            }

            /// Look up the on-disk path for a database by descriptor `id`.
            /// Returns nil when no entry matches. Used by tests and
            /// downstream consumers that need to address a specific
            /// database without iterating the full list.
            public func path(forDatabaseId id: String) -> URL? {
                databases.first(where: { $0.descriptor.id == id })?.path
            }
        }

        /// Progress events emitted while the pipeline runs. CLI
        /// subscribes via an `EventObserving` conformer; tests can
        /// collect them.
        public enum Event: Sendable {
            case starting(Request)
            case statusResolved(Distribution.InstalledVersion.Status)
            /// A pre-existing DB was renamed to a
            /// `.backup-<version>-<iso8601>` sibling before extraction
            /// would overwrite it (#249).
            case dbBackedUp(filename: String, from: URL, to: URL)
            case downloadStart(label: String)
            case downloadProgress(label: String, Distribution.Artifact.Downloader.Progress)
            case downloadComplete(label: String, sizeBytes: Int64)
            case extractStart(label: String)
            case extractTick(label: String)
            case extractComplete(label: String)
            /// 2026-05-27: emitted when the optional
            /// `apple-constraints.json` sidecar download fails (network
            /// error, 404, etc.). Non-fatal — save will still work,
            /// just at the iter-1+2 enrichment coverage (~16% of
            /// doc_symbols rows) instead of iter-3 (~38%). The CLI
            /// observer surfaces this as a warning so users know to
            /// expect degraded constraint enrichment.
            case constraintsDownloadSkipped(reason: String)
            case finished(Outcome)
        }

        /// GoF Observer (1994 p. 293) for `Setup.Service.run` lifecycle
        /// events. Replaces the previous
        /// `handler: @escaping @Sendable (Event) -> Void` closure
        /// parameter. Per the standing cupertino rule "no closures,
        /// they ate magic."
        public protocol EventObserving: Sendable {
            /// Called once per lifecycle transition. Implementations
            /// should be non-blocking; the service waits for return
            /// before continuing.
            func observe(event: Event)
        }
    }
}

/// Back-compat alias for pre-#1042 consumers.
extension Distribution {
    public typealias SetupService = Setup.Service
}
