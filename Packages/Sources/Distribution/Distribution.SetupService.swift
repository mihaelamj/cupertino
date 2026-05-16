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

        let searchDBURL = request.baseDir
            .appendingPathComponent(Shared.Constants.FileName.searchDatabase)
        let samplesDBURL = request.baseDir
            .appendingPathComponent(Shared.Constants.FileName.samplesDatabase)
        let packagesDBURL = request.baseDir
            .appendingPathComponent(Shared.Constants.FileName.packagesIndexDatabase)

        let installedVersion = Distribution.InstalledVersion.read(in: request.baseDir)
        let status = Distribution.InstalledVersion.classify(
            searchDBExists: FileManager.default.fileExists(atPath: searchDBURL.path),
            samplesDBExists: FileManager.default.fileExists(atPath: samplesDBURL.path),
            packagesDBExists: FileManager.default.fileExists(atPath: packagesDBURL.path),
            installedVersion: installedVersion,
            currentVersion: request.currentDocsVersion
        )
        events.observe(event: .statusResolved(status))

        // Honour --keep-existing only when every DB is already on disk.
        if request.keepExisting,
           case .current = status {
            let outcome = Outcome(
                searchDBPath: searchDBURL,
                samplesDBPath: samplesDBURL,
                packagesDBPath: packagesDBURL,
                docsVersionWritten: installedVersion ?? request.currentDocsVersion,
                skippedDownload: true,
                priorStatus: status
            )
            events.observe(event: .finished(outcome))
            return outcome
        }

        // 0. Back up any pre-existing DBs before the extractor would
        // overwrite them (#249). Each of the three DBs is backed up
        // only when present on disk; the helper skips whichever
        // doesn't exist (e.g. legacy installs where packages.db
        // wasn't yet part of the bundle).
        try backupExistingDBs(
            in: request.baseDir,
            dbURLs: [searchDBURL, samplesDBURL, packagesDBURL],
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

        // Hard-fail if any expected DB didn't appear post-extract.
        guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
            throw Distribution.SetupError.missingFile(Shared.Constants.FileName.searchDatabase)
        }
        guard FileManager.default.fileExists(atPath: samplesDBURL.path) else {
            throw Distribution.SetupError.missingFile(Shared.Constants.FileName.samplesDatabase)
        }
        guard FileManager.default.fileExists(atPath: packagesDBURL.path) else {
            throw Distribution.SetupError.missingFile(Shared.Constants.FileName.packagesIndexDatabase)
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
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }

        let outcome = Outcome(
            searchDBPath: searchDBURL,
            samplesDBPath: samplesDBURL,
            packagesDBPath: packagesDBURL,
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
        try? FileManager.default.removeItem(at: zipURL)
        events.observe(event: .extractComplete(label: label))
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
