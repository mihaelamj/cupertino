import Foundation
import IndexerModels
import Testing

// MARK: - IndexerModels public surface smoke tests
//
// IndexerModels is the foundation-only seam target for the three
// `Indexer.<Service>` orchestrators (extracted in PR #558 during the
// closures-to-Observer epic). It owns the namespace anchor, the
// per-service Request / Outcome / Event value types, and the three
// `EventObserving` GoF Observer protocols.
//
// These tests pin the public surface so a rename or accidental
// deletion fails CI before downstream consumers (Indexer producer,
// CLI) discover it.

// MARK: - Namespace anchors

@Suite("Indexer namespace anchors")
struct IndexerNamespaceTests {
    @Test("Indexer namespace is reachable")
    func indexerNamespaceExists() {
        let _: Indexer.Type = Indexer.self
    }

    @Test("Indexer.DocsService namespace is reachable")
    func docsServiceNamespaceExists() {
        let _: Indexer.DocsService.Type = Indexer.DocsService.self
    }

    @Test("Indexer.PackagesService namespace is reachable")
    func packagesServiceNamespaceExists() {
        let _: Indexer.PackagesService.Type = Indexer.PackagesService.self
    }

    @Test("Indexer.SamplesService namespace is reachable")
    func samplesServiceNamespaceExists() {
        let _: Indexer.SamplesService.Type = Indexer.SamplesService.self
    }
}

// MARK: - DocsService value types

@Suite("Indexer.DocsService value types")
struct DocsServiceModelTests {
    @Test("Request stores every public field via init")
    func requestRoundTrip() {
        let baseDir = URL(fileURLWithPath: "/tmp/cupertino-test-docs")
        let request = Indexer.DocsService.Request(
            baseDir: baseDir,
            clear: true
        )
        #expect(request.baseDir == baseDir)
        #expect(request.clear == true)
        #expect(request.docsDir == nil)
        #expect(request.evolutionDir == nil)
        #expect(request.swiftOrgDir == nil)
        #expect(request.archiveDir == nil)
        #expect(request.higDir == nil)
        #expect(request.searchDB == nil)
    }

    @Test("Outcome stores every public field via init")
    func outcomeRoundTrip() {
        let path = URL(fileURLWithPath: "/tmp/search.db")
        let outcome = Indexer.DocsService.Outcome(
            searchDBPath: path,
            documentCount: 42,
            frameworkCount: 7
        )
        #expect(outcome.searchDBPath == path)
        #expect(outcome.documentCount == 42)
        #expect(outcome.frameworkCount == 7)
    }

    @Test("Event exposes the documented case list")
    func eventCaseList() {
        // Pin the case list so a rename or deletion breaks compilation.
        let events: [Indexer.DocsService.Event] = [
            .removingExistingDB(URL(fileURLWithPath: "/tmp/x.db")),
            .initializingIndex,
            .missingOptionalSource(label: "Swift Evolution", url: URL(fileURLWithPath: "/tmp/evolution")),
            .availabilityMissing,
            .progress(processed: 1, total: 10, percent: 10.0),
            .finished(Indexer.DocsService.Outcome(
                searchDBPath: URL(fileURLWithPath: "/tmp/x.db"),
                documentCount: 1,
                frameworkCount: 1
            )),
        ]
        #expect(events.count == 6)
    }
}

// MARK: - PackagesService value types

@Suite("Indexer.PackagesService value types")
struct PackagesServiceModelTests {
    @Test("Request stores every public field via init")
    func requestRoundTrip() {
        let root = URL(fileURLWithPath: "/tmp/packages-root")
        let db = URL(fileURLWithPath: "/tmp/packages.db")
        let request = Indexer.PackagesService.Request(
            packagesRoot: root,
            packagesDB: db,
            clear: true
        )
        #expect(request.packagesRoot == root)
        #expect(request.packagesDB == db)
        #expect(request.clear == true)
    }

    @Test("Outcome stores every public field via init")
    func outcomeRoundTrip() {
        let outcome = Indexer.PackagesService.Outcome(
            packagesIndexed: 100,
            packagesFailed: 2,
            totalFiles: 1234,
            totalBytes: 56789,
            durationSeconds: 12.5,
            totalPackagesInDB: 500,
            totalFilesInDB: 9999,
            totalBytesInDB: 123_456_789
        )
        #expect(outcome.packagesIndexed == 100)
        #expect(outcome.packagesFailed == 2)
        #expect(outcome.totalFiles == 1234)
        #expect(outcome.totalBytes == 56789)
        #expect(outcome.durationSeconds == 12.5)
        #expect(outcome.totalPackagesInDB == 500)
        #expect(outcome.totalFilesInDB == 9999)
        #expect(outcome.totalBytesInDB == 123_456_789)
    }
}

// MARK: - SamplesService value types

@Suite("Indexer.SamplesService value types")
struct SamplesServiceModelTests {
    @Test("Event.Phase exposes the documented four cases")
    func phaseCases() {
        let phases: [Indexer.SamplesService.Event.Phase] = [
            .extracting, .indexingFiles, .completed, .failed,
        ]
        #expect(phases.count == 4)
        // String raw value is pinned so any external log/observer reads
        // the same wire-shape over time.
        #expect(Indexer.SamplesService.Event.Phase.extracting.rawValue == "extracting")
        #expect(Indexer.SamplesService.Event.Phase.indexingFiles.rawValue == "indexingFiles")
        #expect(Indexer.SamplesService.Event.Phase.completed.rawValue == "completed")
        #expect(Indexer.SamplesService.Event.Phase.failed.rawValue == "failed")
    }

    @Test("ServiceError carries the directory it couldn't find")
    func serviceErrorPayload() {
        let dir = URL(fileURLWithPath: "/tmp/missing")
        let error = Indexer.SamplesService.ServiceError.sampleCodeDirectoryNotFound(dir)
        #expect(error.description.contains(dir.path))
    }
}

// MARK: - EventObserving protocol witnesses

@Suite("EventObserving protocol witnesses")
struct EventObservingWitnessTests {
    @Test("DocsService.EventObserving accepts a concrete conformer")
    func docsObserver() {
        struct NoopDocsObserver: Indexer.DocsService.EventObserving {
            func observe(event: Indexer.DocsService.Event) {}
        }
        let observer: any Indexer.DocsService.EventObserving = NoopDocsObserver()
        observer.observe(event: .initializingIndex)
    }

    @Test("PackagesService.EventObserving accepts a concrete conformer")
    func packagesObserver() {
        struct NoopPackagesObserver: Indexer.PackagesService.EventObserving {
            func observe(event: Indexer.PackagesService.Event) {}
        }
        let observer: any Indexer.PackagesService.EventObserving = NoopPackagesObserver()
        observer.observe(event: .starting(
            packagesRoot: URL(fileURLWithPath: "/tmp/r"),
            packagesDB: URL(fileURLWithPath: "/tmp/p.db")
        ))
    }

    @Test("SamplesService.EventObserving accepts a concrete conformer")
    func samplesObserver() {
        struct NoopSamplesObserver: Indexer.SamplesService.EventObserving {
            func observe(event: Indexer.SamplesService.Event) {}
        }
        let observer: any Indexer.SamplesService.EventObserving = NoopSamplesObserver()
        observer.observe(event: .indexingStart)
    }
}
