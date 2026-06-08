import Foundation
import SharedConstants

// MARK: - CupertinoDataEngine.Configuration

extension CupertinoDataEngine {
    public struct Configuration: Sendable {
        public let searchDatabases: [SearchDatabase]
        public let sampleDatabase: SampleDatabase?
        public let packagesDatabase: PackageDatabase?

        public init(
            searchDatabases: [SearchDatabase],
            sampleDatabase: SampleDatabase? = nil,
            packagesDatabase: PackageDatabase? = nil
        ) {
            self.searchDatabases = searchDatabases
            self.sampleDatabase = sampleDatabase
            self.packagesDatabase = packagesDatabase
        }

        /// Current per-source bundle layout used by `cupertino setup`.
        public static func perSourceBundle(
            baseDirectory: URL,
            searchSchemaVersion: Int32,
            sampleSchemaVersion: Int32,
            packagesSchemaVersion: Int32
        ) -> Configuration {
            let searchDescriptors: [Shared.Models.DatabaseDescriptor] = [
                .appleDocumentation,
                .hig,
                .appleArchive,
                .swiftEvolution,
                .swiftOrg,
                .swiftBook,
                .appleSampleCode,
            ]
            return Configuration(
                searchDatabases: searchDescriptors.map { descriptor in
                    SearchDatabase(
                        id: descriptor.id,
                        url: baseDirectory.appendingPathComponent(descriptor.filename),
                        displayName: descriptor.displayName,
                        expectedSchemaVersion: searchSchemaVersion
                    )
                },
                sampleDatabase: SampleDatabase(
                    url: baseDirectory.appendingPathComponent(Shared.Models.DatabaseDescriptor.appleSampleCode.filename),
                    displayName: Shared.Models.DatabaseDescriptor.appleSampleCode.displayName,
                    expectedSchemaVersion: sampleSchemaVersion
                ),
                packagesDatabase: PackageDatabase(
                    url: baseDirectory.appendingPathComponent(Shared.Models.DatabaseDescriptor.swiftPackages.filename),
                    displayName: Shared.Models.DatabaseDescriptor.swiftPackages.displayName,
                    expectedSchemaVersion: packagesSchemaVersion
                )
            )
        }

        /// Legacy three-file layout retained for local/dev bundles.
        public static func legacyBundle(
            baseDirectory: URL,
            searchSchemaVersion: Int32,
            sampleSchemaVersion: Int32,
            packagesSchemaVersion: Int32
        ) -> Configuration {
            Configuration(
                searchDatabases: [
                    SearchDatabase(
                        id: Shared.Models.DatabaseDescriptor.search.id,
                        url: baseDirectory.appendingPathComponent(Shared.Models.DatabaseDescriptor.search.filename),
                        displayName: Shared.Models.DatabaseDescriptor.search.displayName,
                        expectedSchemaVersion: searchSchemaVersion
                    ),
                ],
                sampleDatabase: SampleDatabase(
                    url: baseDirectory.appendingPathComponent(Shared.Models.DatabaseDescriptor.samples.filename),
                    displayName: Shared.Models.DatabaseDescriptor.samples.displayName,
                    expectedSchemaVersion: sampleSchemaVersion
                ),
                packagesDatabase: PackageDatabase(
                    url: baseDirectory.appendingPathComponent(Shared.Models.DatabaseDescriptor.packages.filename),
                    displayName: Shared.Models.DatabaseDescriptor.packages.displayName,
                    expectedSchemaVersion: packagesSchemaVersion
                )
            )
        }
    }

    public struct SearchDatabase: Sendable {
        public let id: String
        public let url: URL
        public let displayName: String
        public let expectedSchemaVersion: Int32

        var role: String {
            "search database \(displayName) (\(id))"
        }

        public init(
            id: String,
            url: URL,
            displayName: String,
            expectedSchemaVersion: Int32
        ) {
            self.id = id
            self.url = url
            self.displayName = displayName
            self.expectedSchemaVersion = expectedSchemaVersion
        }
    }

    public struct SampleDatabase: Sendable {
        public let url: URL
        public let displayName: String
        public let expectedSchemaVersion: Int32

        var role: String {
            "sample database \(displayName)"
        }

        public init(
            url: URL,
            displayName: String = "Sample code",
            expectedSchemaVersion: Int32
        ) {
            self.url = url
            self.displayName = displayName
            self.expectedSchemaVersion = expectedSchemaVersion
        }
    }

    public struct PackageDatabase: Sendable {
        public let url: URL
        public let displayName: String
        public let expectedSchemaVersion: Int32

        var role: String {
            "packages database \(displayName)"
        }

        public init(
            url: URL,
            displayName: String = "Packages",
            expectedSchemaVersion: Int32
        ) {
            self.url = url
            self.displayName = displayName
            self.expectedSchemaVersion = expectedSchemaVersion
        }
    }
}
