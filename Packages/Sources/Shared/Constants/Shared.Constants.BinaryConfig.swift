import Foundation

extension Shared.Constants {
    /// Optional configuration loaded from a JSON file sitting next to the cupertino
    /// executable. Lets multiple binaries (e.g. brew install vs dev build) point at
    /// different data directories without env vars or per-command flags.
    ///
    /// File name is `cupertino.config.json`, searched in the directory of
    /// `Bundle.main.executableURL` (symlinks resolved). Missing file, missing keys,
    /// or any decode error fall through to the location-derived default
    /// (`~/.cupertino/` for brew-installed binaries; `~/.cupertino-dev/` for
    /// every other binary location — see `provenance` below).
    public struct BinaryConfig: Decodable, Sendable, Equatable {
        public static let fileName = "cupertino.config.json"

        /// Override for the base data directory, e.g. `"~/.cupertino-dev"`.
        /// Tilde-expanded when resolved.
        public let baseDirectory: String?

        public init(baseDirectory: String? = nil) {
            self.baseDirectory = baseDirectory
        }

        /// Directory of the running executable, **without** resolving symlinks,
        /// so a config dropped next to a stable symlink (e.g.
        /// `~/.local/bin/cupertino-dev` → `.build/release/cupertino`) survives
        /// rebuilds that recreate the symlink target. Returns nil if the path
        /// can't be determined (some test runner contexts).
        public static var executableDirectory: URL? {
            Bundle.main.executableURL?.deletingLastPathComponent()
        }

        /// Loads `cupertino.config.json` from the given directory. Returns an
        /// empty config on missing directory, missing file, unreadable file,
        /// or invalid JSON.
        public static func load(from directory: URL?) -> BinaryConfig {
            guard let directory else { return BinaryConfig() }
            let url = directory.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: url) else { return BinaryConfig() }
            return (try? JSONDecoder().decode(BinaryConfig.self, from: data)) ?? BinaryConfig()
        }

        /// `baseDirectory` resolved to an absolute file URL with tildes expanded,
        /// or nil if no override was specified or the value was empty.
        public var resolvedBaseDirectory: URL? {
            guard let raw = baseDirectory, !raw.isEmpty else { return nil }
            let expanded = (raw as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }

        // MARK: - #675 — binary provenance (brew vs dev) for isolation-by-default

        /// Where the running binary lives. Drives the default `baseDirectory`
        /// when no `cupertino.config.json` override is present: brew-installed
        /// binaries default to the production path (`~/.cupertino/`); every
        /// other binary location (a `.build/`-relative dev build, a manually
        /// copied executable, etc.) defaults to the dev-isolated path
        /// (`~/.cupertino-dev/`), so a dev build cannot corrupt the brew
        /// install just by running a `save` / `setup` / `fetch` command.
        ///
        /// Pre-#675 the default was always `~/.cupertino/` and the
        /// `cupertino.config.json` drop (Makefile `build-release` / `build-debug`)
        /// was the only safety gate. Raw `swift build -c release` skipped the
        /// drop and the resulting binary silently targeted the brew path. This
        /// caused two corruption incidents in a single session on 2026-05-16.
        public enum Provenance: Sendable, Equatable {
            /// Binary lives at a brew install prefix
            /// (`/opt/homebrew/bin/`, `/opt/homebrew/Cellar/`,
            /// `/usr/local/bin/`, `/usr/local/Cellar/`, or
            /// `/home/linuxbrew/.linuxbrew/`). Production path is the
            /// correct default.
            case brewInstalled
            /// Binary lives anywhere else — typically a SwiftPM `.build/`
            /// directory, a manually-copied executable, a CI workspace, a
            /// pre-release smoke install, or an unrecognised system path.
            /// Dev-isolated path is the correct default.
            case other
        }

        /// Hard-coded set of path-prefix patterns that mark a brew-managed
        /// install. Both the executable path and its symlink-resolved real
        /// path are checked; either matching is sufficient.
        private static let brewInstallPrefixes: [String] = [
            "/opt/homebrew/bin/",
            "/opt/homebrew/Cellar/",
            "/usr/local/bin/",
            "/usr/local/Cellar/",
            "/home/linuxbrew/.linuxbrew/",
        ]

        /// Inspect a candidate executable path against the brew-install prefix
        /// set. Both the as-invoked path AND the symlink-resolved real path
        /// are checked so brew installs that exec the `bin/` symlink and brew
        /// installs that exec the Cellar realpath both resolve to
        /// `brewInstalled`. Pure function for tests; the live caller is
        /// `provenance(of:)` below.
        public static func classify(executablePath: String) -> Provenance {
            let resolvedPath = (executablePath as NSString).resolvingSymlinksInPath
            for prefix in brewInstallPrefixes {
                if executablePath.hasPrefix(prefix) || resolvedPath.hasPrefix(prefix) {
                    return .brewInstalled
                }
            }
            return .other
        }

        /// Live provenance of the currently-running binary. `.other` when the
        /// executable URL can't be resolved (treat unknown-source as
        /// dev-isolated; safest default).
        public static var provenance: Provenance {
            guard let executableURL = Bundle.main.executableURL else { return .other }
            return classify(executablePath: executableURL.path)
        }
    }
}
