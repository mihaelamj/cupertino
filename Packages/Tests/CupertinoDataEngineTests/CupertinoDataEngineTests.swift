@_spi(CupertinoInternal) import CupertinoDataEngine
import Foundation
import LoggingModels
import SampleIndexModels
import SampleIndexSQLite
import SearchModels
import SearchSQLite
import SQLite3
import Testing

@Suite("#1261 CupertinoDataEngine")
struct CupertinoDataEngineTests {
    @Test("opens a source reader read-only from a read-only corpus directory")
    func opensSourceReaderReadOnlyFromReadOnlyCorpusDirectory() async throws {
        let tempDir = try Self.makeTempDir()
        let searchURL = tempDir.appendingPathComponent("search.db")
        defer { Self.restoreWritablePermissions(tempDir); try? FileManager.default.removeItem(at: tempDir) }

        try await Self.seedSourceResource(at: searchURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: searchURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempDir.path)

        let engine = try await Self.makeEngine(
            configuration: .init(sourceCorpusResources: [
                .init(id: "docs", url: searchURL, displayName: "Docs", expectedSchemaVersion: Search.Index.schemaVersion),
            ])
        )
        let reader = try await engine.sourceReader(id: "docs")
        #expect(try await reader.documentCount() == 1)
        let content = try await reader.getDocumentContent(uri: "apple-docs://swiftui/view", format: .markdown)
        #expect(content?.contains("SwiftUI View documentation") == true)
        await reader.disconnect()
        #expect(try await reader.documentCount() == 1)
        await engine.disconnect()
    }

    @Test("returns document-browser refinement through backend interface")
    func returnsDocumentBrowserInterface() async throws {
        let tempDir = try Self.makeTempDir()
        let searchURL = tempDir.appendingPathComponent("search.db")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await Self.seedSourceResource(at: searchURL)
        let engine = try await Self.makeEngine(
            configuration: .init(sourceCorpusResources: [
                .init(id: "docs", url: searchURL, displayName: "Docs", expectedSchemaVersion: Search.Index.schemaVersion),
            ])
        )
        let browser = try await engine.documentBrowser(id: "docs")
        let page = try await browser.listDocuments(source: "apple-docs", framework: "swiftui", offset: 0, limit: 10)
        #expect(page.total == 1)
        #expect(page.documents.first?.title == "View")
        await engine.disconnect()
    }

    @Test("missing configured corpus resource fails before opening a reader")
    func missingCorpusResourceFailsBeforeOpen() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let missingURL = tempDir.appendingPathComponent("missing.db")

        do {
            _ = try await Self.makeEngine(
                configuration: .init(sourceCorpusResources: [
                    .init(id: "missing", url: missingURL, displayName: "Missing", expectedSchemaVersion: Search.Index.schemaVersion),
                ])
            )
            Issue.record("expected missing corpus resource error")
        } catch let error as CupertinoDataEngine.Error {
            guard case let .missingCorpusResource(role, path) = error else {
                Issue.record("expected missingCorpusResource, got \(error)")
                return
            }
            #expect(role.contains("Missing"))
            #expect(path == missingURL.path)
        }
    }

    @Test("configured source resource requires a source-reader factory")
    func configuredSourceResourceRequiresSourceReaderFactory() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let searchURL = tempDir.appendingPathComponent("search.db")

        await #expect(throws: CupertinoDataEngine.Error.sourceReaderFactoryNotConfigured) {
            _ = try await CupertinoDataEngine(
                configuration: .init(sourceCorpusResources: [
                    .init(id: "docs", url: searchURL, displayName: "Docs", expectedSchemaVersion: Search.Index.schemaVersion),
                ])
            )
        }
    }

    @Test("configured sample resource requires a sample-reader factory")
    func configuredSampleResourceRequiresSampleReaderFactory() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let sampleURL = tempDir.appendingPathComponent("samples.db")

        await #expect(throws: CupertinoDataEngine.Error.sampleReaderFactoryNotConfigured) {
            _ = try await CupertinoDataEngine(
                configuration: .init(
                    sourceCorpusResources: [],
                    sampleResource: .init(url: sampleURL, expectedSchemaVersion: Sample.Index.Database.schemaVersion)
                )
            )
        }
    }

    @Test("configured packages resource requires a packages-reader factory")
    func configuredPackagesResourceRequiresPackagesReaderFactory() async throws {
        let tempDir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let packagesURL = tempDir.appendingPathComponent("packages.db")

        await #expect(throws: CupertinoDataEngine.Error.packageReaderFactoryNotConfigured) {
            _ = try await CupertinoDataEngine(
                configuration: .init(
                    sourceCorpusResources: [],
                    packagesResource: .init(url: packagesURL, expectedSchemaVersion: Search.PackageIndex.schemaVersion)
                )
            )
        }
    }

    @Test("schema mismatch fails before reader construction")
    func schemaMismatchFailsBeforeReaderConstruction() async throws {
        let tempDir = try Self.makeTempDir()
        let searchURL = tempDir.appendingPathComponent("search.db")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try Self.createSQLiteDatabase(at: searchURL, userVersion: Search.Index.schemaVersion - 1)

        do {
            _ = try await Self.makeEngine(
                configuration: .init(sourceCorpusResources: [
                    .init(id: "docs", url: searchURL, displayName: "Docs", expectedSchemaVersion: Search.Index.schemaVersion),
                ])
            )
            Issue.record("expected schema mismatch")
        } catch let error as CupertinoDataEngine.Error {
            guard case let .schemaVersionMismatch(role, path, expected, actual) = error else {
                Issue.record("expected schemaVersionMismatch, got \(error)")
                return
            }
            #expect(role.contains("Docs"))
            #expect(path == searchURL.path)
            #expect(expected == Search.Index.schemaVersion)
            #expect(actual == Search.Index.schemaVersion - 1)
        }
    }

    @Test("opens sample reader through backend interface")
    func opensSampleReader() async throws {
        let tempDir = try Self.makeTempDir()
        let sampleURL = tempDir.appendingPathComponent("samples.db")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await Self.seedSampleDatabase(at: sampleURL)

        let engine = try await Self.makeEngine(
            configuration: .init(
                sourceCorpusResources: [],
                sampleResource: .init(url: sampleURL, displayName: "Samples", expectedSchemaVersion: Sample.Index.Database.schemaVersion)
            )
        )
        let samples = try await engine.samples()
        #expect(try await samples.projectCount() == 1)
        let project = try await samples.getProject(id: "sample-app")
        #expect(project?.title == "Sample App")
        await samples.disconnect()
        #expect(try await samples.projectCount() == 1)
        await engine.disconnect()
    }

    @Test("opens packages reader through backend interface")
    func opensPackagesReader() async throws {
        let tempDir = try Self.makeTempDir()
        let packagesURL = tempDir.appendingPathComponent("packages.db")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageIndex = try await Search.PackageIndex(dbPath: packagesURL, logger: Logging.NoopRecording())
        await packageIndex.disconnect()

        let engine = try await Self.makeEngine(
            configuration: .init(
                sourceCorpusResources: [],
                packagesResource: .init(url: packagesURL, displayName: "Packages", expectedSchemaVersion: Search.PackageIndex.schemaVersion)
            )
        )
        let packages = try await engine.packages()
        let results = try await packages.searchPackages(
            query: "swift",
            limit: 1,
            availability: nil,
            swiftTools: nil,
            appleImport: nil
        )
        #expect(results.isEmpty)
        await engine.disconnect()
    }

    private static func seedSourceResource(at url: URL) async throws {
        let index = try await Search.Index(
            dbPath: url,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: "apple-docs://swiftui/view",
            source: "apple-docs",
            framework: "swiftui",
            title: "View",
            content: "SwiftUI View documentation",
            filePath: "/tmp/view.json",
            contentHash: "view-hash",
            lastCrawled: Date()
        ))
        await index.disconnect()
    }

    private static func makeEngine(
        configuration: CupertinoDataEngine.Configuration,
        logger: any Logging.Recording = Logging.NoopRecording()
    ) async throws -> CupertinoDataEngine {
        try await CupertinoDataEngine(
            configuration: configuration,
            sourceReaderFactory: SearchSQLiteFactory(logger: logger),
            sampleReaderFactory: SampleSQLiteFactory(logger: logger),
            packageReaderFactory: PackageSQLiteFactory()
        )
    }

    private static func seedSampleDatabase(at url: URL) async throws {
        let database = try await Sample.Index.Database(dbPath: url, logger: Logging.NoopRecording())
        try await database.indexProject(Sample.Index.Project(
            id: "sample-app",
            title: "Sample App",
            description: "A sample app.",
            frameworks: ["SwiftUI"],
            readme: "# Sample App",
            webURL: "https://developer.apple.com/sample-app",
            zipFilename: "sample-app.zip",
            fileCount: 1,
            totalSize: 18,
            deploymentTargets: ["ios": "17.0"],
            availabilitySource: "fixture"
        ))
        try await database.indexFile(Sample.Index.File(
            projectId: "sample-app",
            path: "ContentView.swift",
            content: "import SwiftUI\nstruct ContentView {}\n"
        ))
        await database.disconnect()
    }

    private static func createSQLiteDatabase(at url: URL, userVersion: Int32) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            throw SQLiteTestError.openFailed
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, "PRAGMA user_version = \(userVersion)", nil, nil, nil) == SQLITE_OK else {
            throw SQLiteTestError.pragmaFailed
        }
    }

    private static func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-data-engine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func restoreWritablePermissions(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        let searchURL = url.appendingPathComponent("search.db")
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: searchURL.path)
    }

    private struct SearchSQLiteFactory: Search.DatabaseFactory {
        let logger: any Logging.Recording

        func openDatabase(at url: URL) async throws -> any Search.Database {
            try await Search.Index(
                dbPath: url,
                logger: logger,
                indexers: [:],
                sourceLookup: .empty,
                readOnly: true
            )
        }
    }

    private struct SampleSQLiteFactory: Sample.Index.DatabaseFactory {
        let logger: any Logging.Recording

        func openDatabase(at url: URL) async throws -> any Sample.Index.Reader {
            try await Sample.Index.Database(dbPath: url, logger: logger, readOnly: true)
        }
    }

    private struct PackageSQLiteFactory: CupertinoDataEngine.PackageReaderFactory {
        func openPackageReader(at url: URL) async throws -> any CupertinoDataEngine.PackageReader {
            let query = try await Search.PackageQuery(dbPath: url)
            return PackageReader(query: query)
        }
    }

    private struct PackageReader: CupertinoDataEngine.PackageReader {
        let query: Search.PackageQuery

        func searchPackages(
            query: String,
            limit: Int,
            availability: Search.AvailabilityFilter?,
            swiftTools: Search.SwiftToolsFilter?,
            appleImport: String?
        ) async throws -> [Search.Result] {
            try await self.query.searchPackages(
                query: query,
                limit: limit,
                availability: availability,
                swiftTools: swiftTools,
                appleImport: appleImport
            )
        }

        func searchPackageSymbolsByGenericConstraint(
            constraint: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.Result] {
            try await query.searchPackageSymbolsByGenericConstraint(
                constraint: constraint,
                framework: framework,
                limit: limit
            )
        }

        func disconnect() async {
            await query.disconnect()
        }
    }

    private enum SQLiteTestError: Error {
        case openFailed
        case pragmaFailed
    }
}
