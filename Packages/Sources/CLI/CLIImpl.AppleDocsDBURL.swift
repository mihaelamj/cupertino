import Foundation
import SearchModels
import SharedConstants

// MARK: - CLIImpl.resolveAppleDocsDBURL

/// Shared apple-docs DB URL resolver for AST-aware CLI subcommands
/// (`cupertino search-symbols` / `inheritance` / `search-conformances`
/// / `search-concurrency` / `search-property-wrappers` /
/// `search-generics` / `list-frameworks`). Post-#1037 every docs source
/// owns its own SQLite file; all of these commands query apple-docs-
/// specific AST tables that live in `apple-documentation.db` per
/// `AppleDocsSource.destinationDB`. Centralising the lookup here keeps
/// the per-command surface a one-liner and routes through the
/// canonical `SourceProvider.destinationDB.filename` mapping (no
/// hardcoded filename literal).
///
/// `override` honours each subcommand's `--search-db` flag for
/// test + migration-window back-compat: when set, the override URL is
/// returned verbatim regardless of the registry.
extension CLIImpl {
    /// Returns the file URL the AST-aware search commands should open.
    /// Defaults to `<baseDirectory>/apple-documentation.db` (resolved
    /// through `CLIImpl.makeProductionSourceRegistry()`'s
    /// `AppleDocsSource.destinationDB.filename`). Falls back to the
    /// hardcoded descriptor filename if `AppleDocsSource` is somehow
    /// unregistered (defensive; unreachable in production).
    public static func resolveAppleDocsDBURL(override: String? = nil) -> URL {
        if let override {
            return URL(fileURLWithPath: override).expandingTildeInPath
        }
        let baseDirectory = Shared.Paths.live().baseDirectory
        if let provider = makeProductionSourceRegistry().allEnabled.first(where: {
            $0.definition.id == Shared.Constants.SourcePrefix.appleDocs
        }) {
            return baseDirectory.appendingPathComponent(provider.destinationDB.filename)
        }
        return baseDirectory.appendingPathComponent(
            Shared.Models.DatabaseDescriptor.appleDocumentation.filename
        )
    }
}
