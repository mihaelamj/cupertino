import Foundation
import SampleIndexModels
import SearchModels

// MARK: - CupertinoDataEngine

/// Read-only backend facade for embedded Cupertino clients.
///
/// UI layers should consume the protocol-typed readers this actor returns and
/// must not open database files directly. Concrete database actors are supplied
/// by a composition root through factory protocols, keeping this package free
/// of concrete SQLite producer imports.
public actor CupertinoDataEngine {
    public nonisolated let configuration: Configuration

    private let searchDatabaseFactory: (any Search.DatabaseFactory)?
    private let sampleDatabaseFactory: (any Sample.Index.DatabaseFactory)?
    private let packageDatabaseFactory: (any PackageDatabaseFactory)?
    private var searchDatabases: [String: any Search.Database] = [:]
    private var sampleDatabase: (any Sample.Index.Reader)?
    private var packageDatabase: (any PackageConnection)?

    public init(
        configuration: Configuration,
        searchDatabaseFactory: (any Search.DatabaseFactory)? = nil,
        sampleDatabaseFactory: (any Sample.Index.DatabaseFactory)? = nil,
        packageDatabaseFactory: (any PackageDatabaseFactory)? = nil
    ) async throws {
        self.configuration = configuration
        self.searchDatabaseFactory = searchDatabaseFactory
        self.sampleDatabaseFactory = sampleDatabaseFactory
        self.packageDatabaseFactory = packageDatabaseFactory

        let duplicateIDs = Dictionary(grouping: configuration.searchDatabases, by: \.id)
            .filter { $0.value.count > 1 }
            .keys
        guard duplicateIDs.isEmpty else {
            throw Error.duplicateSearchDatabaseID(duplicateIDs.sorted().joined(separator: ", "))
        }

        try await openSearchDatabases(configuration.searchDatabases)
        try await openSampleDatabase(configuration.sampleDatabase)
        try await openPackageDatabase(configuration.packagesDatabase)
    }

    /// Stable list of configured search DB identifiers in configuration order.
    public nonisolated var searchDatabaseIDs: [String] {
        configuration.searchDatabases.map(\.id)
    }

    /// Return a search/document/code-intelligence reader by configured ID.
    public func searchDatabase(id: String) throws -> any Search.Database {
        guard let database = searchDatabases[id] else {
            throw Error.searchDatabaseNotConfigured(id)
        }
        return database
    }

    /// Return the document-browser refinement for a configured search DB.
    public func documentBrowser(id: String) throws -> any Search.Database & Search.DocumentBrowsing {
        let database = try searchDatabase(id: id)
        guard let browser = database as? any Search.Database & Search.DocumentBrowsing else {
            throw Error.documentBrowserUnavailable(id)
        }
        return browser
    }

    /// Return the sample-code reader, when configured.
    public func samples() throws -> any Sample.Index.Reader {
        guard let sampleDatabase else {
            throw Error.sampleDatabaseNotConfigured
        }
        return sampleDatabase
    }

    /// Return the packages reader, when configured.
    public func packages() throws -> any Search.PackagesSearcher {
        guard let packageDatabase else {
            throw Error.packagesDatabaseNotConfigured
        }
        return packageDatabase
    }

    /// Close every opened reader. Idempotent.
    public func disconnect() async {
        for database in searchDatabases.values {
            await database.disconnect()
        }
        searchDatabases.removeAll()

        if let sampleDatabase {
            await sampleDatabase.disconnect()
            self.sampleDatabase = nil
        }

        if let packageDatabase {
            await packageDatabase.disconnect()
            self.packageDatabase = nil
        }
    }

    private func openSearchDatabases(_ configurations: [SearchDatabase]) async throws {
        guard !configurations.isEmpty else { return }
        guard let searchDatabaseFactory else {
            throw Error.searchDatabaseFactoryNotConfigured
        }
        for configuration in configurations {
            try Self.requireDatabaseFile(configuration.url, role: configuration.role)
            try SchemaProbe.assertPragmaUserVersion(
                at: configuration.url,
                expected: configuration.expectedSchemaVersion,
                role: configuration.role
            )
            searchDatabases[configuration.id] = try await searchDatabaseFactory.openDatabase(at: configuration.url)
        }
    }

    private func openSampleDatabase(_ configuration: SampleDatabase?) async throws {
        guard let configuration else { return }
        guard let sampleDatabaseFactory else {
            throw Error.sampleDatabaseFactoryNotConfigured
        }
        try Self.requireDatabaseFile(configuration.url, role: configuration.role)
        try SchemaProbe.assertSamplesSchemaVersion(
            at: configuration.url,
            expected: configuration.expectedSchemaVersion,
            role: configuration.role
        )
        sampleDatabase = try await sampleDatabaseFactory.openDatabase(at: configuration.url)
    }

    private func openPackageDatabase(_ configuration: PackageDatabase?) async throws {
        guard let configuration else { return }
        guard let packageDatabaseFactory else {
            throw Error.packageDatabaseFactoryNotConfigured
        }
        try Self.requireDatabaseFile(configuration.url, role: configuration.role)
        try SchemaProbe.assertPragmaUserVersion(
            at: configuration.url,
            expected: configuration.expectedSchemaVersion,
            role: configuration.role
        )
        packageDatabase = try await packageDatabaseFactory.openDatabase(at: configuration.url)
    }

    private static func requireDatabaseFile(
        _ url: URL,
        role: String
    ) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw Error.missingDatabase(role: role, path: url.path)
        }
    }
}
