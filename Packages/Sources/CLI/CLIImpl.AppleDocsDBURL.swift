import ArgumentParser
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
    /// Single source-of-truth help body for the seven AST-aware
    /// subcommands' `--search-db` option (round-14 critic finding #7:
    /// the literal was duplicated across 7 callsites with two
    /// divergent formattings; promoting it here removes the
    /// `N-place edit` smell and makes future help-text revisions
    /// land in one file).
    public static let appleDocsDBOverrideHelp: ArgumentHelp = .init(
        "Override the apple-docs database path. Default: apple-documentation.db (resolved through the production source registry)."
    )

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

    /// Build the standard "DB not found" diagnostic for an AST-aware
    /// CLI command. Migration-aware: when a legacy `search.db` is
    /// sitting in the same directory, the diagnostic explicitly
    /// surfaces it so the user knows the in-place upgrade path is
    /// `cupertino setup` (which runs the per-source DB split
    /// migration via `runPerSourceDBSplitMigrationIfNeeded`). Pre-fix
    /// the message just said "Run `cupertino setup` first." and the
    /// user with a populated legacy search.db sitting RIGHT THERE
    /// could be reasonably confused.
    public static func appleDocsDBMissingMessage(url: URL) -> String {
        let baseMessage = "❌ \(url.lastPathComponent) not found at \(url.path). Run `cupertino setup` first."
        let legacy = url.deletingLastPathComponent().appendingPathComponent(
            Shared.Constants.FileName.searchDatabase
        )
        if FileManager.default.fileExists(atPath: legacy.path) {
            return baseMessage + " (Detected legacy \(legacy.lastPathComponent) sitting in the same directory; `cupertino setup` migrates it into per-source DBs.)"
        }
        return baseMessage
    }
}
