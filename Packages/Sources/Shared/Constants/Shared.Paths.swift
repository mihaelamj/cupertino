import Foundation

// MARK: - Shared.Paths

extension Shared {
    /// Process-wide resolved-paths value type. Each computed property
    /// returns a `URL` rooted at `baseDirectory`, which itself is
    /// resolved at construction time from a `Shared.Constants.BinaryConfig`
    /// (loaded from the `cupertino.config.json` sitting next to the running
    /// executable, or `~/.cupertino/` as the home-directory fallback).
    ///
    /// **Replaces** the previous `Shared.Constants.defaultBaseDirectory` /
    /// `defaultDocsDirectory` / etc. static accessors and the
    /// `Shared.Constants.BinaryConfig.shared` Singleton. The static
    /// accessors were Service Locators (Seemann, *Dependency Injection*,
    /// 2011, ch. 5): any caller anywhere in the codebase could reach into
    /// process-global config to resolve a path, hiding the dependency.
    ///
    /// The new shape: every consumer that needs a path receives a
    /// `Shared.Paths` value (or an explicit `URL`) by constructor or method
    /// parameter. The composition root (CLI's `@main`) constructs exactly
    /// one `Shared.Paths.live()` at process start and threads it down.
    /// Tests build their own with `Shared.Paths(baseDirectory: tempDir)`.
    public struct Paths: Sendable {
        /// Root data directory for this process. All other paths derive
        /// from here.
        public let baseDirectory: URL

        public init(baseDirectory: URL) {
            self.baseDirectory = baseDirectory
        }

        /// Resolve from a `BinaryConfig` value. The composition root
        /// loads `BinaryConfig` once (typically via
        /// `Shared.Constants.BinaryConfig.load(from:)`) and passes the
        /// resolved struct here.
        public init(binaryConfig: Shared.Constants.BinaryConfig) {
            if let override = binaryConfig.resolvedBaseDirectory {
                self.init(baseDirectory: override)
            } else {
                self.init(
                    baseDirectory: FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(Shared.Constants.baseDirectoryName)
                )
            }
        }

        /// Production factory: load `BinaryConfig` from the running
        /// executable's directory and build a `Paths` from it. Used by
        /// the CLI / TUI / MockAIAgent composition roots. Tests should
        /// construct `Paths(baseDirectory:)` with a UUID-tagged temp
        /// directory instead.
        public static func live() -> Paths {
            Paths(
                binaryConfig: Shared.Constants.BinaryConfig.load(
                    from: Shared.Constants.BinaryConfig.executableDirectory
                )
            )
        }

        // MARK: - Derived directories

        /// `<baseDirectory>/docs`
        public var docsDirectory: URL {
            baseDirectory.appendingPathComponent(Shared.Constants.Directory.docs)
        }

        /// `<baseDirectory>/swift-evolution`
        public var swiftEvolutionDirectory: URL {
            baseDirectory.appendingPathComponent(Shared.Constants.Directory.swiftEvolution)
        }

        /// `<baseDirectory>/swift-org`
        public var swiftOrgDirectory: URL {
            baseDirectory.appendingPathComponent(Shared.Constants.Directory.swiftOrg)
        }

        /// `<baseDirectory>/swift-book`
        public var swiftBookDirectory: URL {
            baseDirectory.appendingPathComponent(Shared.Constants.Directory.swiftBook)
        }

        /// `<baseDirectory>/packages`
        public var packagesDirectory: URL {
            baseDirectory.appendingPathComponent(Shared.Constants.Directory.packages)
        }

        /// `<baseDirectory>/sample-code`
        public var sampleCodeDirectory: URL {
            baseDirectory.appendingPathComponent(Shared.Constants.Directory.sampleCode)
        }

        /// `<baseDirectory>/archive`
        public var archiveDirectory: URL {
            baseDirectory.appendingPathComponent(Shared.Constants.Directory.archive)
        }

        /// `<baseDirectory>/hig`
        public var higDirectory: URL {
            baseDirectory.appendingPathComponent(Shared.Constants.Directory.hig)
        }

        // MARK: - Derived files

        /// `<baseDirectory>/metadata.json`
        public var metadataFile: URL {
            baseDirectory.appendingPathComponent(Shared.Constants.FileName.metadata)
        }

        /// `<baseDirectory>/config.json`
        public var configFile: URL {
            baseDirectory.appendingPathComponent(Shared.Constants.FileName.config)
        }

        /// `<baseDirectory>/search.db`
        public var searchDatabase: URL {
            baseDirectory.appendingPathComponent(Shared.Constants.FileName.searchDatabase)
        }

        /// `<baseDirectory>/packages.db`
        public var packagesDatabase: URL {
            baseDirectory.appendingPathComponent(Shared.Constants.FileName.packagesIndexDatabase)
        }
    }
}
