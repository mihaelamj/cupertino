import Foundation
import SearchModels
import SharedConstants

// MARK: - PackagesReadStrategy

/// 2026-05-26 audit #1055: per-source read strategy for `--source
/// packages`. Pre-fix the 3-arm bucket dispatch in
/// `Services.ReadService.readFrom` had a hardcoded
/// `if source == .packages { try readFromPackages(...) }` branch
/// that opened packages.db and matched the identifier against
/// `<owner>/<repo>/<relpath>`.
///
/// Identifier shapes:
///   - `<owner>/<repo>/<relpath>` -> read file via packageFileLookup
///   - Anything else -> nil (auto-source flow continues)
public struct PackagesReadStrategy: Search.SourceReadStrategy {
    public init() {}

    public func read(env: Search.ReadEnvironment) async throws -> Search.ReadResult? {
        let components = env.identifier.split(separator: "/", maxSplits: 2)
        guard components.count == 3 else { return nil }
        let owner = String(components[0])
        let repo = String(components[1])
        let path = String(components[2])
        guard let content = try await env.packageFileLookup.read(
            packagesDB: env.packagesDB,
            owner: owner,
            repo: repo,
            path: path
        ) else {
            return nil
        }
        return Search.ReadResult(
            content: content,
            resolvedSourceID: Shared.Constants.SourcePrefix.packages
        )
    }
}
