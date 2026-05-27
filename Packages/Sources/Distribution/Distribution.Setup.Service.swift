import Foundation
import SharedConstants

// MARK: - Distribution.SetupService — concrete run static func

//
// The `Distribution.SetupService` namespace + `Request` + `Outcome` +
// `Event` value types + `EventObserving` Observer protocol live in the
// foundation-only `DistributionModels` seam target. This file extends
// the same enum with the actual `run(...)` orchestrator.

extension Distribution.SetupService {
    public static func run(
        _ request: Request,
        events: any Distribution.SetupService.EventObserving
    ) async throws -> Outcome {
        events.observe(event: .starting(request))

        try FileManager.default.createDirectory(
            at: request.baseDir,
            withIntermediateDirectories: true
        )

        let installedVersion = Distribution.InstalledVersion.read(in: request.baseDir)

        // Database placement list, ordered by the printable sequence
        // declared at the composition root via `request.required`. The
        // CLI's success-summary printer iterates this list rather than
        // addressing fixed fields, so a 4th DB drops in by appending
        // its descriptor at the composition root.
        let placements: [DatabasePlacement] = request.required.map { descriptor in
            DatabasePlacement(
                descriptor: descriptor,
                path: request.baseDir.appendingPathComponent(descriptor.filename)
            )
        }

        let required: Set<Shared.Models.DatabaseDescriptor> = Set(request.required)
        let present: Set<Shared.Models.DatabaseDescriptor> = Set(
            placements.compactMap { placement in
                FileManager.default.fileExists(atPath: placement.path.path) ? placement.descriptor : nil
            }
        )
        let status = Distribution.InstalledVersion.classify(
            present: present,
            required: required,
            installedVersion: installedVersion,
            currentVersion: request.currentDocsVersion
        )
        events.observe(event: .statusResolved(status))

        // Honour --keep-existing only when every DB is already on disk.
        if request.keepExisting,
           case .current = status {
            let outcome = Outcome(
                databases: placements,
                docsVersionWritten: installedVersion ?? request.currentDocsVersion,
                skippedDownload: true,
                priorStatus: status
            )
            events.observe(event: .finished(outcome))
            return outcome
        }

        // 0. Back up any pre-existing DBs before the extractor would
        // overwrite them (#249). Each required DB is backed up only
        // when present on disk; the helper skips whichever doesn't
        // exist (e.g. legacy installs where packages.db wasn't yet
        // part of the bundle).
        try backupExistingDBs(
            in: request.baseDir,
            dbURLs: placements.map(\.path),
            installedVersion: installedVersion,
            events: events
        )

        // 1. Single bundle download — search.db + samples.db + packages.db
        //    all ship together from `mihaelamj/cupertino-docs` as of
        //    v1.0.0. The packages DB used to live in a separate companion
        //    repo (`mihaelamj/cupertino-packages`) but was folded into
        //    the main bundle to keep `cupertino setup` to one download.
        let zipFilename = "cupertino-databases-v\(request.currentDocsVersion).zip"
        let zipURL = request.baseDir.appendingPathComponent(zipFilename)
        let urlString = "\(request.docsReleaseBaseURL)/v\(request.currentDocsVersion)/\(zipFilename)"

        try await downloadAndExtract(
            label: "Documentation databases",
            from: urlString,
            zipURL: zipURL,
            destination: request.baseDir,
            events: events
        )

        // 1b. Apple-constraints sidecar download (#759 iter 3 enrichment input).
        //
        // `apple-constraints.json` is the authoritative Apple SDK
        // constraints table produced by `cupertino-constraints-gen`
        // from the cupertino-symbolgraphs corpus. The cupertino
        // indexer reads it during `save` and runs
        // `Search.Index.applyAppleStaticConstraints` which lifts
        // `doc_symbols.generic_constraints` coverage from ~16% (iter
        // 1+2 only) to ~38% (with iter 3). Without it the indexer
        // silently degrades.
        //
        // The file ships in the cupertino-docs git tree at
        // `apple-constraints.json` (committed 2026-05-27 commit
        // 0860213a). Setup fetches it via the GitHub raw URL since
        // it's not in the v1.2.0 release zip.
        //
        // Optional + non-fatal: a setup that fails to fetch the
        // sidecar still ends in a usable state (saves degrade to iter
        // 1+2 silently as they always have). Surfaced via the
        // `Event.constraintsDownloadSkipped(reason:)` event.
        //
        // 2026-05-27: fetched BEFORE the placement hard-fail check
        // below so the sidecar lands even when the main DB extract
        // is mismatched (e.g. v1.2.0 zip ships pre-#1036 `search.db`
        // but the binary expects post-split `apple-documentation.db`).
        // Order matters: users hitting the placement throw would
        // never have the constraints file, perpetuating the
        // iter-1+2-only enrichment gap that the file is meant to
        // close.
        let constraintsURLString = "https://raw.githubusercontent.com/mihaelamj/cupertino-docs/main/apple-constraints.json"
        let constraintsLocalURL = request.baseDir.appendingPathComponent("apple-constraints.json")
        do {
            try await downloadConstraintsSidecar(
                from: constraintsURLString,
                to: constraintsLocalURL,
                events: events
            )
        } catch {
            // Don't throw. Save still works without it.
            events.observe(event: .constraintsDownloadSkipped(reason: "\(error)"))
        }

        // Hard-fail if any expected DB didn't appear post-extract.
        // Iteration is driven by `placements` (composition-root list),
        // so adding a 4th DB requires no edit here.
        for placement in placements where !FileManager.default.fileExists(atPath: placement.path.path) {
            throw Distribution.SetupError.missingFile(placement.descriptor.filename)
        }

        // Stamp version on success. Non-fatal; the file is an
        // optimization, not correctness — but #673 Phase B surfaces the
        // failure on stderr so a broken stamp (which makes
        // `cupertino doctor` later report "no setup ever happened")
        // doesn't disappear silently. Pre-fix every stamp failure was
        // dropped on the floor.
        do {
            try Distribution.InstalledVersion.write(request.currentDocsVersion, in: request.baseDir)
        } catch {
            let message = "⚠️  Failed to write installed-version stamp at " +
                "\(request.baseDir.path)/.setup-version: \(error). " +
                "Setup succeeded but `cupertino doctor` may not report the " +
                "current version. Re-running `cupertino setup` will retry.\n"
            FileHandle.standardError.write(Data(message.utf8))
        }

        let outcome = Outcome(
            databases: placements,
            docsVersionWritten: request.currentDocsVersion,
            skippedDownload: false,
            priorStatus: status
        )
        events.observe(event: .finished(outcome))
        return outcome
    }

    // MARK: - Helpers

    private static func downloadAndExtract(
        label: String,
        from urlString: String,
        zipURL: URL,
        destination: URL,
        events: any Distribution.SetupService.EventObserving
    ) async throws {
        events.observe(event: .downloadStart(label: label))
        try await Distribution.ArtifactDownloader.download(
            from: urlString,
            to: zipURL,
            progress: DownloadProgressForwarder(label: label, events: events)
        )
        let bytes = (try? FileManager.default.attributesOfItem(atPath: zipURL.path)[.size] as? Int64) ?? 0
        events.observe(event: .downloadComplete(label: label, sizeBytes: bytes))

        events.observe(event: .extractStart(label: label))
        try await Distribution.ArtifactExtractor.extract(
            zipAt: zipURL,
            to: destination,
            tickObserver: ExtractTickForwarder(label: label, events: events)
        )
        // #682 — intentional silent removal failure. The zip has been
        // fully extracted at this point; leaving it on disk is clutter,
        // not corruption. A user can `rm ~/.cupertino/*.zip` manually
        // if they want the space back. A warn here would surface a
        // benign cleanup miss with no actionable next step (the
        // extracted DBs are already in place + the setup completed).
        try? FileManager.default.removeItem(at: zipURL)
        events.observe(event: .extractComplete(label: label))
    }

    /// Fetch the `apple-constraints.json` sidecar from cupertino-docs's
    /// raw GitHub URL. Distinct from `downloadAndExtract` because the
    /// sidecar is a single JSON file, not a zip archive needing
    /// extraction.
    ///
    /// 2026-05-27: added after a fresh Claw mini reindex ran 9.5 hours
    /// without the constraints file present, locking in ~16% constraint
    /// coverage instead of the ~38% the v0.1.1 symbolgraph corpus would
    /// have delivered. The sidecar is now committed to
    /// cupertino-docs/main; setup pulls it as a sibling artifact so
    /// fresh installs get the full enrichment path automatically.
    private static func downloadConstraintsSidecar(
        from urlString: String,
        to localURL: URL,
        events: any Distribution.SetupService.EventObserving
    ) async throws {
        let label = "Apple constraints sidecar"
        events.observe(event: .downloadStart(label: label))
        try await Distribution.ArtifactDownloader.download(
            from: urlString,
            to: localURL,
            progress: DownloadProgressForwarder(label: label, events: events)
        )
        let bytes = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
        events.observe(event: .downloadComplete(label: label, sizeBytes: bytes))
    }

    /// Rename pre-existing DBs to `.backup-<version>-<iso8601>` siblings
    /// before extraction overwrites them (#249). Pure file moves; on
    /// success the user has a clear rollback path.
    ///
    /// Each DB in `dbURLs` is backed up only when present on disk —
    /// callers pass all three (search.db / samples.db / packages.db)
    /// and the helper skips whichever doesn't exist. Handles both the
    /// v0.10.x → v1.0 case (no packages.db on disk) and the v0.11+
    /// → v1.0.x case (all three present).
    ///
    /// `installedVersion` comes from `InstalledVersion.read(...)`; nil
    /// → "unknown" suffix (legacy install with no version stamp).
    private static func backupExistingDBs(
        in baseDir: URL,
        dbURLs: [URL],
        installedVersion: String?,
        events: any Distribution.SetupService.EventObserving
    ) throws {
        let suffix = backupSuffix(for: installedVersion)
        let fm = FileManager.default
        for url in dbURLs {
            guard fm.fileExists(atPath: url.path) else { continue }
            let backupURL = url.appendingPathExtension(suffix)
            // Move via remove-then-move so a stale identically-named
            // backup from a previous failed run doesn't block.
            if fm.fileExists(atPath: backupURL.path) {
                try fm.removeItem(at: backupURL)
            }
            try fm.moveItem(at: url, to: backupURL)
            events.observe(event: .dbBackedUp(
                filename: url.lastPathComponent,
                from: url,
                to: backupURL
            ))
        }
    }

    /// `backup-<version>-<iso8601-utc>` suffix appended via
    /// `appendingPathExtension`. Result on disk:
    /// `search.db.backup-0.10.0-2026-05-04T05:30:12Z`.
    ///
    /// Constructs a fresh `ISO8601DateFormatter` per call (formatter is
    /// not Sendable in Swift 6 strict-concurrency, so it can't be cached
    /// as a `static let`). Called once per `setup` run, so the cost is
    /// negligible.
    static func backupSuffix(
        for installedVersion: String?,
        now: Date = Date()
    ) -> String {
        let version = installedVersion ?? "unknown"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let timestamp = formatter.string(from: now)
        return "backup-\(version)-\(timestamp)"
    }

    // MARK: - Inner adapters bridging downloader/extractor Observer

    // protocols to SetupService.EventObserving. Closure-free.

    private struct DownloadProgressForwarder: Distribution.ArtifactDownloader.ProgressObserving {
        let label: String
        let events: any Distribution.SetupService.EventObserving

        func observe(progress: Distribution.ArtifactDownloader.Progress) {
            events.observe(event: .downloadProgress(label: label, progress))
        }
    }

    private struct ExtractTickForwarder: Distribution.ArtifactExtractor.TickObserving {
        let label: String
        let events: any Distribution.SetupService.EventObserving

        func observeTick() {
            events.observe(event: .extractTick(label: label))
        }
    }
}
