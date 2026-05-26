import Foundation
import SampleIndexModels
import SearchModels
import ServicesModels
import SharedConstants

// MARK: - Services.LiveSampleLookupStrategy

extension Services {
    /// 2026-05-26 audit #1055: production `Search.SampleLookupStrategy`
    /// conformer that wraps `Services.ServiceContainer.withSampleService`
    /// — the live SampleIndex-backed reader. CLI / MCP composition
    /// root wires this into `Search.ReadEnvironment.sampleLookup`.
    public struct LiveSampleLookupStrategy: Search.SampleLookupStrategy {
        public let sampleDatabaseFactory: any Sample.Index.DatabaseFactory

        public init(sampleDatabaseFactory: any Sample.Index.DatabaseFactory) {
            self.sampleDatabaseFactory = sampleDatabaseFactory
        }

        public func readProject(id: String, samplesDB: URL) async throws -> Search.SampleProjectContent? {
            try await Services.ServiceContainer.withSampleService(
                samplesDB: samplesDB,
                sampleDatabaseFactory: sampleDatabaseFactory
            ) { service in
                guard let project = try await service.getProject(id: id) else { return nil }
                // Lift the project's readable surface into the seam-tier
                // value type so per-source read strategies in SearchModels
                // don't need to depend on `SampleIndexModels`.
                return Search.SampleProjectContent(
                    readmeOrDescription: project.readme ?? project.description
                )
            }
        }

        public func readFile(projectId: String, path: String, samplesDB: URL) async throws -> String? {
            try await Services.ServiceContainer.withSampleService(
                samplesDB: samplesDB,
                sampleDatabaseFactory: sampleDatabaseFactory
            ) { service in
                try await service.getFile(projectId: projectId, path: path)?.content
            }
        }
    }
}
