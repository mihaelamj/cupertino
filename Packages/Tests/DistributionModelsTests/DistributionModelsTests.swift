import DistributionModels
import Foundation
import SharedConstants
import Testing

// MARK: - DistributionModels public surface smoke tests
//
// DistributionModels is the foundation-only seam target for the
// `cupertino setup` pipeline (extracted in PR #563 during the
// closures-to-Observer epic). It owns:
// - the `Distribution` namespace anchor
// - per-helper value types (Request / Outcome / Event / Progress /
//   Status / SetupError)
// - three GoF Observer protocols (`SetupService.EventObserving`,
//   `ArtifactDownloader.ProgressObserving`,
//   `ArtifactExtractor.TickObserving`)
//
// These tests pin the public surface so a rename or accidental
// deletion fails CI before downstream consumers (Distribution
// producer, CLI) discover it.

// MARK: - Namespace anchors

@Suite("Distribution namespace anchors")
struct DistributionNamespaceTests {
    @Test("Distribution namespace is reachable")
    func distributionNamespaceExists() {
        let _: Distribution.Type = Distribution.self
    }

    @Test("Distribution.SetupService namespace is reachable")
    func setupServiceNamespaceExists() {
        let _: Distribution.SetupService.Type = Distribution.SetupService.self
    }

    @Test("Distribution.ArtifactDownloader namespace is reachable")
    func artifactDownloaderNamespaceExists() {
        let _: Distribution.ArtifactDownloader.Type = Distribution.ArtifactDownloader.self
    }

    @Test("Distribution.ArtifactExtractor namespace is reachable")
    func artifactExtractorNamespaceExists() {
        let _: Distribution.ArtifactExtractor.Type = Distribution.ArtifactExtractor.self
    }

    @Test("Distribution.InstalledVersion namespace is reachable")
    func installedVersionNamespaceExists() {
        let _: Distribution.InstalledVersion.Type = Distribution.InstalledVersion.self
    }
}

// MARK: - SetupService value types

@Suite("Distribution.SetupService value types")
struct SetupServiceModelTests {
    @Test("Request stores every public field via init")
    func requestRoundTrip() {
        let baseDir = URL(fileURLWithPath: "/tmp/cupertino-setup-test")
        let request = Distribution.SetupService.Request(
            baseDir: baseDir,
            currentDocsVersion: "1.2.3",
            docsReleaseBaseURL: "https://example.com/releases",
            keepExisting: true
        )
        #expect(request.baseDir == baseDir)
        #expect(request.currentDocsVersion == "1.2.3")
        #expect(request.docsReleaseBaseURL == "https://example.com/releases")
        #expect(request.keepExisting == true)
    }

    @Test("Request defaults pick up SharedConstants App values")
    func requestDefaults() {
        let baseDir = URL(fileURLWithPath: "/tmp/cupertino-setup-defaults")
        let request = Distribution.SetupService.Request(baseDir: baseDir)
        // Default values come from `Shared.Constants.App.*`; we don't
        // hard-code them here because they roll with each cupertino
        // release. Pinning that they're non-empty is enough.
        #expect(!request.currentDocsVersion.isEmpty)
        #expect(!request.docsReleaseBaseURL.isEmpty)
        #expect(request.keepExisting == false)
    }

    @Test("Outcome stores every public field via init")
    func outcomeRoundTrip() {
        let outcome = Distribution.SetupService.Outcome(
            searchDBPath: URL(fileURLWithPath: "/tmp/search.db"),
            samplesDBPath: URL(fileURLWithPath: "/tmp/samples.db"),
            packagesDBPath: URL(fileURLWithPath: "/tmp/packages.db"),
            docsVersionWritten: "1.0.0",
            skippedDownload: false,
            priorStatus: .missing
        )
        #expect(outcome.searchDBPath.lastPathComponent == "search.db")
        #expect(outcome.samplesDBPath.lastPathComponent == "samples.db")
        #expect(outcome.packagesDBPath.lastPathComponent == "packages.db")
        #expect(outcome.docsVersionWritten == "1.0.0")
        #expect(outcome.skippedDownload == false)
        #expect(outcome.priorStatus == .missing)
    }

    @Test("Outcome is Equatable")
    func outcomeEquatable() {
        let a = Distribution.SetupService.Outcome(
            searchDBPath: URL(fileURLWithPath: "/tmp/x.db"),
            samplesDBPath: URL(fileURLWithPath: "/tmp/y.db"),
            packagesDBPath: URL(fileURLWithPath: "/tmp/z.db"),
            docsVersionWritten: "1.0",
            skippedDownload: true,
            priorStatus: .current(version: "1.0")
        )
        let b = a
        #expect(a == b)
    }

    @Test("Event exposes the documented case list")
    func eventCaseList() {
        // Pin the case list so a rename or deletion breaks compilation.
        let req = Distribution.SetupService.Request(baseDir: URL(fileURLWithPath: "/tmp/x"))
        let outcome = Distribution.SetupService.Outcome(
            searchDBPath: URL(fileURLWithPath: "/tmp/s"),
            samplesDBPath: URL(fileURLWithPath: "/tmp/sa"),
            packagesDBPath: URL(fileURLWithPath: "/tmp/p"),
            docsVersionWritten: "1.0",
            skippedDownload: false,
            priorStatus: .missing
        )
        let events: [Distribution.SetupService.Event] = [
            .starting(req),
            .statusResolved(.missing),
            .dbBackedUp(
                filename: "x.db",
                from: URL(fileURLWithPath: "/tmp/x.db"),
                to: URL(fileURLWithPath: "/tmp/x.db.bak")
            ),
            .downloadStart(label: "Docs"),
            .downloadProgress(label: "Docs", Distribution.ArtifactDownloader.Progress(
                bytesWritten: 100,
                totalBytes: 1000
            )),
            .downloadComplete(label: "Docs", sizeBytes: 1000),
            .extractStart(label: "Docs"),
            .extractTick(label: "Docs"),
            .extractComplete(label: "Docs"),
            .finished(outcome),
        ]
        #expect(events.count == 10)
    }
}

// MARK: - ArtifactDownloader.Progress

@Suite("Distribution.ArtifactDownloader.Progress")
struct ArtifactDownloaderProgressTests {
    @Test("Stores both fields via init")
    func progressFields() {
        let progress = Distribution.ArtifactDownloader.Progress(
            bytesWritten: 1234,
            totalBytes: 5678
        )
        #expect(progress.bytesWritten == 1234)
        #expect(progress.totalBytes == 5678)
    }

    @Test("totalBytes nil when server doesn't advertise Content-Length")
    func progressNilTotal() {
        let progress = Distribution.ArtifactDownloader.Progress(
            bytesWritten: 100,
            totalBytes: nil
        )
        #expect(progress.bytesWritten == 100)
        #expect(progress.totalBytes == nil)
    }
}

// MARK: - InstalledVersion.Status

@Suite("Distribution.InstalledVersion.Status")
struct InstalledVersionStatusTests {
    @Test("Status exposes the documented four cases")
    func statusCases() {
        let cases: [Distribution.InstalledVersion.Status] = [
            .missing,
            .current(version: "1.0"),
            .stale(installed: "0.9", current: "1.0"),
            .unknown(current: "1.0"),
        ]
        #expect(cases.count == 4)
    }

    @Test("Status is Equatable")
    func statusEquatable() {
        #expect(Distribution.InstalledVersion.Status.missing == .missing)
        #expect(Distribution.InstalledVersion.Status.current(version: "1.0") == .current(version: "1.0"))
        #expect(Distribution.InstalledVersion.Status.current(version: "1.0") != .current(version: "2.0"))
    }
}

// MARK: - SetupError

@Suite("Distribution.SetupError")
struct SetupErrorTests {
    @Test("All six cases produce non-empty description")
    func descriptionPresence() {
        let cases: [Distribution.SetupError] = [
            .invalidURL("not a url"),
            .invalidResponse,
            .notFound(URL(fileURLWithPath: "/tmp/missing")),
            .httpError(503),
            .extractionFailed,
            .missingFile("search.db"),
        ]
        for error in cases {
            #expect(!error.description.isEmpty)
        }
    }

    @Test("Error conformance is satisfied")
    func conformsToError() {
        let error: Swift.Error = Distribution.SetupError.invalidResponse
        #expect(error is Distribution.SetupError)
    }

    @Test("Equatable conformance compares case + payload")
    func equatable() {
        #expect(Distribution.SetupError.invalidResponse == .invalidResponse)
        #expect(Distribution.SetupError.httpError(404) == .httpError(404))
        #expect(Distribution.SetupError.httpError(404) != .httpError(503))
    }
}

// MARK: - Observer protocol witnesses

@Suite("DistributionModels Observer protocol witnesses")
struct DistributionObservingWitnessTests {
    @Test("SetupService.EventObserving accepts a concrete conformer")
    func eventObserver() {
        struct NoopEventObserver: Distribution.SetupService.EventObserving {
            func observe(event: Distribution.SetupService.Event) {}
        }
        let observer: any Distribution.SetupService.EventObserving = NoopEventObserver()
        observer.observe(event: .extractTick(label: "test"))
    }

    @Test("ArtifactDownloader.ProgressObserving accepts a concrete conformer")
    func progressObserver() {
        struct NoopProgressObserver: Distribution.ArtifactDownloader.ProgressObserving {
            func observe(progress: Distribution.ArtifactDownloader.Progress) {}
        }
        let observer: any Distribution.ArtifactDownloader.ProgressObserving = NoopProgressObserver()
        observer.observe(progress: Distribution.ArtifactDownloader.Progress(
            bytesWritten: 1,
            totalBytes: 10
        ))
    }

    @Test("ArtifactExtractor.TickObserving accepts a concrete conformer")
    func tickObserver() {
        struct NoopTickObserver: Distribution.ArtifactExtractor.TickObserving {
            func observeTick() {}
        }
        let observer: any Distribution.ArtifactExtractor.TickObserving = NoopTickObserver()
        observer.observeTick()
    }
}
