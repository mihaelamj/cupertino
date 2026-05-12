import Foundation

extension Shared {
    /// Optional configuration loaded from a JSON file sitting next to the cupertino
    /// executable. Lets multiple binaries (e.g. brew install vs dev build) point at
    /// different data directories without env vars or per-command flags.
    ///
    /// File name is `cupertino.config.json`, searched in the directory of
    /// `Bundle.main.executableURL` (symlinks resolved). Missing file, missing keys,
    /// or any decode error fall through to the standard `~/.cupertino/` default.
    public struct BinaryConfig: Decodable, Sendable, Equatable {
        public static let fileName = "cupertino.config.json"

        /// Override for the base data directory, e.g. `"~/.cupertino-dev"`.
        /// Tilde-expanded when resolved.
        public let baseDirectory: String?

        public init(baseDirectory: String? = nil) {
            self.baseDirectory = baseDirectory
        }

        /// Process-wide cached config, loaded once relative to the running executable.
        public static let shared: BinaryConfig = load(from: executableDirectory)

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
    }
}
