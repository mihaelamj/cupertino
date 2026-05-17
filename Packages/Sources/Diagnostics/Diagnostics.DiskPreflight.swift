import Foundation

// MARK: - #673 Phase F — disk-space preflight

extension Diagnostics {
    /// Disk-space preflight for cupertino commands that write large
    /// payloads (`cupertino save`, `cupertino fetch`, `cupertino setup`).
    /// Refuses to start when free disk is less than `(estimated write
    /// size + safety margin)`; warns when free fraction drops below a
    /// configurable threshold.
    ///
    /// Filed off the 2026-05-16 corruption incident: a `cupertino save`
    /// started on a 95 %-full disk, partial-wrote a 2.48 GB → 429 MB
    /// search.db, and only stopped when SQLite hit `disk I/O error`
    /// mid-FTS insert. Per #673 Phase F's spec: "save must refuse to
    /// start when free disk < (estimate + 10 % margin)". The Carmack
    /// class-of-bug here is "cupertino save can corrupt a 2.7 GB DB
    /// because we don't precheck 50 GB headroom" — and the cure is to
    /// make the precheck mandatory at every write-initiating command.
    public enum DiskPreflight {
        /// Result of a single disk-space check.
        public enum Result: Sendable, Equatable {
            /// Plenty of room. `freeBytes` / `totalBytes` reported for
            /// downstream logging.
            case ok(freeBytes: Int64, totalBytes: Int64)
            /// Free disk would cover the operation but the overall
            /// volume is low (default <20 % free). Caller should warn
            /// the user but still proceed.
            case warningLow(freeBytes: Int64, totalBytes: Int64, freeFraction: Double)
            /// Free disk is below `estimate × (1 + margin)`. Refuse —
            /// the operation would have run out of space mid-write.
            /// Caller maps this to the typed `InsufficientDiskSpaceError`
            /// and exits with `EX_IOERR`.
            case refuseInsufficient(neededBytes: Int64, freeBytes: Int64, path: String)
        }

        /// Run a disk-space check against `targetDirectory` for an
        /// operation that will write approximately `estimatedBytes`.
        ///
        /// - Parameters:
        ///   - targetDirectory: where the write will land. Resolved up
        ///     to the nearest existing ancestor (handles `~/.cupertino-dev/`
        ///     before first creation).
        ///   - estimatedBytes: caller's best estimate of the operation's
        ///     peak write size. Should include transient artifacts
        ///     (WAL files, audit JSONLs, in-flight downloads, extract
        ///     working trees). Conservative is better than tight.
        ///   - marginFraction: required headroom above the estimate as a
        ///     fraction (default 0.10 = 10 %). Set higher for operations
        ///     with unbounded outputs (full crawl).
        ///   - warningFraction: free fraction below which the result is
        ///     `.warningLow` even when the estimate fits (default 0.20).
        ///   - diskUsageProvider: test seam. Production callers omit it
        ///     and get the live `Diagnostics.Probes.diskUsage` reading.
        /// - Returns: `.ok`, `.warningLow`, or `.refuseInsufficient`. If
        ///   the probe itself can't read the volume (returns nil), this
        ///   function falls back to `.ok` with zero counts — "can't
        ///   check, defer to user's judgement". Refusing a write because
        ///   we couldn't read /var/db/statfs is worse than the failure
        ///   mode #673 Phase F targets.
        public static func check(
            targetDirectory: URL,
            estimatedBytes: Int64,
            marginFraction: Double = 0.10,
            warningFraction: Double = 0.20,
            diskUsageProvider: (URL) -> Probes.DiskUsage? = { Probes.diskUsage(at: $0) }
        ) -> Result {
            guard let usage = diskUsageProvider(targetDirectory) else {
                // Probe failed (path bad / permission denied). Don't
                // refuse the write — we can't tell if there's space.
                return .ok(freeBytes: 0, totalBytes: 0)
            }

            let needed = Int64((Double(estimatedBytes) * (1.0 + marginFraction)).rounded(.up))

            if usage.freeBytes < needed {
                return .refuseInsufficient(
                    neededBytes: needed,
                    freeBytes: usage.freeBytes,
                    path: targetDirectory.path
                )
            }

            if usage.freeFraction < warningFraction {
                return .warningLow(
                    freeBytes: usage.freeBytes,
                    totalBytes: usage.totalBytes,
                    freeFraction: usage.freeFraction
                )
            }

            return .ok(freeBytes: usage.freeBytes, totalBytes: usage.totalBytes)
        }
    }

    /// Typed error raised when `DiskPreflight.check(...)` returns
    /// `.refuseInsufficient`. CLI's `Cupertino.main` catches this and
    /// exits with `EX_IOERR` (74 — sysexits(3) "an error occurred while
    /// doing I/O on some file"). Distinct from the schema-mismatch path
    /// so scripts can branch on the class without parsing the message
    /// text.
    public struct InsufficientDiskSpaceError: Error, LocalizedError, Equatable {
        public let neededBytes: Int64
        public let freeBytes: Int64
        public let path: String

        public init(neededBytes: Int64, freeBytes: Int64, path: String) {
            self.neededBytes = neededBytes
            self.freeBytes = freeBytes
            self.path = path
        }

        public var errorDescription: String? {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB, .useMB]
            formatter.countStyle = .file
            let needed = formatter.string(fromByteCount: neededBytes)
            let free = formatter.string(fromByteCount: freeBytes)
            let short = max(0, neededBytes - freeBytes)
            let shortStr = formatter.string(fromByteCount: short)
            return """
            Insufficient disk space to safely complete this operation.

              Target: \(path)
              Needed: ≥ \(needed) (estimate + 10 % safety margin)
              Free:   \(free)
              Short:  \(shortStr)

            Free at least \(shortStr) on the volume backing \(path) and retry. A partial \
            write here can corrupt the existing database — refusing up-front avoids the \
            2.48 GB → 429 MB truncation that produced this safeguard (see #673 Phase F).
            """
        }
    }
}
