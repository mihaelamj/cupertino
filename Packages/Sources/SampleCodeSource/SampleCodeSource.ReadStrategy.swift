import Foundation
import SearchModels
import SharedConstants

// MARK: - SamplesReadStrategy

/// 2026-05-26 audit #1055: per-source read strategy for `--source
/// samples` (and the legacy `apple-sample-code` alias). Pre-fix the
/// 3-arm bucket dispatch in `Services.ReadService.readFrom` had a
/// hardcoded `if source == .samples { try readFromSamples(...) }`
/// branch that opened `Sample.Index` and matched the identifier
/// against `<projectId>` or `<projectId>/<path>`.
///
/// Post-fix the strategy lives here. It returns nil when the
/// identifier doesn't match the project/file shape so the auto-source
/// fallback (try samples → packages → docs) can keep walking.
public struct SamplesReadStrategy: Search.SourceReadStrategy {
    public init() {}

    public func read(env: Search.ReadEnvironment) async throws -> Search.ReadResult? {
        guard FileManager.default.fileExists(atPath: env.samplesDB.path) else {
            return nil
        }

        if let slashIdx = env.identifier.firstIndex(of: "/") {
            let projectId = String(env.identifier[..<slashIdx])
            let path = String(env.identifier[env.identifier.index(after: slashIdx)...])
            if let fileContent = try await env.sampleLookup.readFile(
                projectId: projectId,
                path: path,
                samplesDB: env.samplesDB
            ) {
                return Search.ReadResult(
                    content: fileContent,
                    resolvedSourceID: Shared.Constants.SourcePrefix.samples
                )
            }
        } else {
            if let project = try await env.sampleLookup.readProject(
                id: env.identifier,
                samplesDB: env.samplesDB
            ) {
                return Search.ReadResult(
                    content: project.readmeOrDescription,
                    resolvedSourceID: Shared.Constants.SourcePrefix.samples
                )
            }
        }

        return nil
    }
}
