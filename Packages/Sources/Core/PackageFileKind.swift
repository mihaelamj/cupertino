import Foundation

extension Core {
    /// Categorisation for every indexed file inside a Swift package. Drives the
    /// `kind` column in `package_files_fts`, which is how queries narrow results
    /// (e.g. `WHERE kind='example'` for "show me code that uses X").
    public enum PackageFileKind: String, Codable, Sendable {
        case readme
        case changelog
        case license
        case packageManifest // Package.swift
        case packageResolved // Package.resolved (apps commit this)
        case doccArticle // Sources/**/*.docc/**/*.md
        case doccTutorial // Sources/**/*.docc/**/*.tutorial
        case source // Sources/**/*.swift
        case test // Tests/**/*.swift
        case example // Examples|Example|Demo|Demos/**
        case projectDoc // Top-level MIGRATING.md, CONTRIBUTING.md, ARCHITECTURE.md, etc.
    }

    /// In-memory representation of a file pulled out of a package tarball after
    /// exclusion-rule pruning. Consumed directly by the indexer; never hits the
    /// user's filesystem as a standalone file.
    public struct ExtractedFile: Sendable {
        public let relpath: String // path inside the repo, e.g. Sources/Logging/Logger.swift
        public let kind: PackageFileKind
        public let module: String? // inferred from Sources/<module>/... or Tests/<module>Tests/...
        public let content: String
        public let byteSize: Int

        public init(
            relpath: String,
            kind: PackageFileKind,
            module: String?,
            content: String,
            byteSize: Int
        ) {
            self.relpath = relpath
            self.kind = kind
            self.module = module
            self.content = content
            self.byteSize = byteSize
        }
    }

    /// Maps a repo-relative path to a `PackageFileKind`. Returns nil for anything
    /// we don't want indexed (the caller drops those). Implemented as a pure
    /// function so it's trivially testable independent of tar + filesystem.
    public enum PackageFileKindClassifier {
        public static func classify(relpath: String) -> (kind: PackageFileKind, module: String?)? {
            let parts = relpath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !parts.isEmpty else { return nil }
            let lastComponent = parts.last ?? ""
            let lower = lastComponent.lowercased()

            // Top-level files first.
            if parts.count == 1 {
                if lower == "readme.md" || lower == "readme" || lower == "readme.markdown" {
                    return (.readme, nil)
                }
                if lower == "changelog.md" || lower == "changelog" || lower == "changelog.markdown" || lower == "changes.md" {
                    return (.changelog, nil)
                }
                if lower.hasPrefix("license") {
                    return (.license, nil)
                }
                if lower == "package.swift" {
                    return (.packageManifest, nil)
                }
                if lower == "package.resolved" {
                    return (.packageResolved, nil)
                }
                // Remaining top-level .md files land under projectDoc so things like
                // MIGRATING.md, CONTRIBUTING.md, ARCHITECTURE.md, DESIGN.md are kept.
                if lastComponent.hasSuffix(".md") || lastComponent.hasSuffix(".markdown") {
                    return (.projectDoc, nil)
                }
                return nil
            }

            // DocC catalogs: `.docc` appears as a path component.
            if parts.contains(where: { $0.hasSuffix(".docc") }) {
                if lastComponent.hasSuffix(".md") || lastComponent.hasSuffix(".markdown") {
                    return (.doccArticle, moduleFromPath(parts))
                }
                if lastComponent.hasSuffix(".tutorial") {
                    return (.doccTutorial, moduleFromPath(parts))
                }
                return nil
            }

            let topLevel = parts[0]

            // Sources/ and Tests/ Swift files.
            if topLevel == "Sources", lastComponent.hasSuffix(".swift") {
                return (.source, parts.count >= 2 ? parts[1] : nil)
            }
            if topLevel == "Tests", lastComponent.hasSuffix(".swift") {
                let module = parts.count >= 2 ? parts[1] : nil
                return (.test, module)
            }

            // Examples / Example / Demo / Demos
            if ["Examples", "Example", "Demo", "Demos"].contains(topLevel) {
                // Keep text-ish files only; binaries already pruned upstream. The indexer
                // skips whatever can't be UTF-8 decoded, so this is a belt-and-braces.
                let ext = (lastComponent as NSString).pathExtension.lowercased()
                if ["swift", "md", "markdown", "txt", "json", "yml", "yaml", "sh"].contains(ext) {
                    return (.example, nil)
                }
                return nil
            }

            // Other .md files deeper in the tree (e.g. Documentation/Article.md)
            if lastComponent.hasSuffix(".md") || lastComponent.hasSuffix(".markdown") {
                return (.projectDoc, nil)
            }

            return nil
        }

        /// Inside a DocC catalog, the module name is usually the parent directory of
        /// the `.docc` folder: `Sources/<Module>/<Name>.docc/...` → `<Module>`.
        private static func moduleFromPath(_ parts: [String]) -> String? {
            guard let doccIndex = parts.firstIndex(where: { $0.hasSuffix(".docc") }) else { return nil }
            guard doccIndex >= 1 else { return nil }
            let before = parts[doccIndex - 1]
            // If the `.docc` is directly under Sources/ with no module dir, there's
            // no meaningful module (rare).
            if before == "Sources" { return nil }
            return before
        }
    }
}
