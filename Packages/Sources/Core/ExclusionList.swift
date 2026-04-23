import Foundation
import Shared

extension Core {
    /// User-maintained skip list at `~/.cupertino/excluded-packages.json`: a flat JSON
    /// array of `"owner/repo"` strings that the resolver must drop from its closure
    /// even when transitively discovered. Absent file = empty set.
    public enum ExclusionList {
        /// Load the exclusion set from the standard location. Missing or malformed
        /// files return an empty set — hand-editing mistakes shouldn't brick the fetch.
        public static func load(
            from directory: URL = Shared.Constants.defaultBaseDirectory
        ) -> Set<String> {
            let fileURL = directory.appendingPathComponent(Shared.Constants.FileName.excludedPackages)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return []
            }
            guard
                let data = try? Data(contentsOf: fileURL),
                let entries = try? JSONDecoder().decode([String].self, from: data)
            else {
                return []
            }
            return Set(entries.map(Self.normalise))
        }

        /// Normalise to the same key format the canonicalizer uses so membership checks
        /// are order-insensitive and case-insensitive.
        public static func normalise(_ entry: String) -> String {
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            return trimmed.lowercased()
        }
    }
}
