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

        /// Resolve from a `BinaryConfig` value + the running binary's
        /// `Provenance`. Resolution rules (#675):
        ///
        /// 1. Explicit `cupertino.config.json` override wins.
        /// 2. Otherwise, brew-installed binaries default to `~/.cupertino/`
        ///    (the production path consumed by the brew CLI).
        /// 3. Otherwise (any other binary location — `.build/`-relative dev
        ///    build, manually copied executable, CI workspace, unrecognised
        ///    install path), default to `~/.cupertino-dev/` so a dev build
        ///    cannot silently corrupt the brew install just by running a
        ///    `save` / `setup` / `fetch` command.
        ///
        /// Pre-#675 the default was always `~/.cupertino/` regardless of
        /// binary provenance; the `cupertino.config.json` drop performed by
        /// `Makefile build-release` / `build-debug` was the only safety
        /// gate, and a raw `swift build -c release` (or any build that
        /// skipped the conf drop) silently targeted the brew path. Now
        /// the binary self-classifies at startup and the conf is an
        /// optional override, not a safety prerequisite.
        public init(
            binaryConfig: Shared.Constants.BinaryConfig,
            provenance: Shared.Constants.BinaryConfig.Provenance
        ) {
            if let override = binaryConfig.resolvedBaseDirectory {
                self.init(baseDirectory: override)
                return
            }
            let directoryName: String
            switch provenance {
            case .brewInstalled:
                directoryName = Shared.Constants.baseDirectoryName
            case .other:
                directoryName = Shared.Constants.devBaseDirectoryName
            }
            self.init(
                baseDirectory: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(directoryName)
            )
        }

        /// Production factory: load `BinaryConfig` from the running
        /// executable's directory + classify the binary's provenance, then
        /// build a `Paths` from both. Used by the CLI / TUI / MockAIAgent
        /// composition roots. Tests should construct `Paths(baseDirectory:)`
        /// with a UUID-tagged temp directory instead.
        public static func live() -> Paths {
            Paths(
                binaryConfig: Shared.Constants.BinaryConfig.load(
                    from: Shared.Constants.BinaryConfig.executableDirectory
                ),
                provenance: Shared.Constants.BinaryConfig.provenance
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

        /// `<baseDirectory>/selected-archive-guides.json` (#101).
        ///
        /// Canonical user-writable selection file for archive guides. Both the
        /// TUI (which writes user choices) and the crawler (which reads them
        /// to drive the Apple Archive crawl set) consume this property so the
        /// two cannot drift apart. Pre-#101 they each computed the URL
        /// independently — a "fun bug" waiting to happen the first time
        /// either side renamed the file.
        public var userArchiveSelectionsFile: URL {
            baseDirectory.appendingPathComponent(Shared.Constants.FileName.userArchiveSelections)
        }
    }
}
