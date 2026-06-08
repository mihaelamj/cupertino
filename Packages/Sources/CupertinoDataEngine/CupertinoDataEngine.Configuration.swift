import Foundation
import SharedConstants

// MARK: - CupertinoDataEngine.Configuration

extension CupertinoDataEngine {
    @_spi(CupertinoInternal)
    public struct Configuration: Sendable {
        public let sourceCorpusResources: [SourceCorpusResource]
        public let sampleResource: SampleResource?
        public let packagesResource: PackageResource?

        public init(
            sourceCorpusResources: [SourceCorpusResource],
            sampleResource: SampleResource? = nil,
            packagesResource: PackageResource? = nil
        ) {
            self.sourceCorpusResources = sourceCorpusResources
            self.sampleResource = sampleResource
            self.packagesResource = packagesResource
        }

        /// Current per-source corpus layout used by `cupertino setup`.
        public static func perSourceBundle(
            baseDirectory: URL,
            searchSchemaVersion: Int32,
            sampleSchemaVersion: Int32,
            packagesSchemaVersion: Int32
        ) -> Configuration {
            let sourceDescriptors: [Shared.Models.DatabaseDescriptor] = [
                .appleDocumentation,
                .hig,
                .appleArchive,
                .swiftEvolution,
                .swiftOrg,
                .swiftBook,
                .appleSampleCode,
            ]
            return Configuration(
                sourceCorpusResources: sourceDescriptors.map { descriptor in
                    SourceCorpusResource(
                        id: descriptor.id,
                        url: baseDirectory.appendingPathComponent(descriptor.filename),
                        displayName: descriptor.displayName,
                        expectedSchemaVersion: searchSchemaVersion
                    )
                },
                sampleResource: SampleResource(
                    url: baseDirectory.appendingPathComponent(Shared.Models.DatabaseDescriptor.appleSampleCode.filename),
                    displayName: Shared.Models.DatabaseDescriptor.appleSampleCode.displayName,
                    expectedSchemaVersion: sampleSchemaVersion
                ),
                packagesResource: PackageResource(
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
                sourceCorpusResources: [
                    SourceCorpusResource(
                        id: Shared.Models.DatabaseDescriptor.search.id,
                        url: baseDirectory.appendingPathComponent(Shared.Models.DatabaseDescriptor.search.filename),
                        displayName: Shared.Models.DatabaseDescriptor.search.displayName,
                        expectedSchemaVersion: searchSchemaVersion
                    ),
                ],
                sampleResource: SampleResource(
                    url: baseDirectory.appendingPathComponent(Shared.Models.DatabaseDescriptor.samples.filename),
                    displayName: Shared.Models.DatabaseDescriptor.samples.displayName,
                    expectedSchemaVersion: sampleSchemaVersion
                ),
                packagesResource: PackageResource(
                    url: baseDirectory.appendingPathComponent(Shared.Models.DatabaseDescriptor.packages.filename),
                    displayName: Shared.Models.DatabaseDescriptor.packages.displayName,
                    expectedSchemaVersion: packagesSchemaVersion
                )
            )
        }
    }

    @_spi(CupertinoInternal)
    public struct SourceCorpusResource: Sendable {
        public let id: String
        public let url: URL
        public let displayName: String
        public let expectedSchemaVersion: Int32

        var role: String {
            "source corpus resource \(displayName) (\(id))"
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

    @_spi(CupertinoInternal)
    public struct SampleResource: Sendable {
        public let url: URL
        public let displayName: String
        public let expectedSchemaVersion: Int32

        var role: String {
            "sample corpus resource \(displayName)"
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

    @_spi(CupertinoInternal)
    public struct PackageResource: Sendable {
        public let url: URL
        public let displayName: String
        public let expectedSchemaVersion: Int32

        var role: String {
            "packages corpus resource \(displayName)"
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
