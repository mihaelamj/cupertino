import EnrichmentModels
import Foundation
import Search
import SearchModels
import SearchSQLite

extension Enrichment {
    /// Registers the framework alias table on search.db so queries like
    /// `"bluetooth"` route to `corebluetooth` results, `"nfc"` to `corenfc`,
    /// etc. 22 alias pairs as of #837 phase 1B-2.
    ///
    /// Moved verbatim out of `Search.IndexBuilder.registerFrameworkSynonyms`.
    /// The alias list lives here now since it is enrichment data, not
    /// indexer data.
    public final class SynonymsPass: EnrichmentPass {
        public let identifier = "synonyms"
        public let schemaVersion = 1
        public let dependsOn: [String] = []
        public let target = EnrichmentModels.Target.search

        private let searchIndex: Search.Index

        public init(searchIndex: Search.Index) {
            self.searchIndex = searchIndex
        }

        public func run(database: OpaquePointer?) async throws -> EnrichmentModels.Result {
            var affected = 0
            for entry in Self.aliases {
                try await searchIndex.updateFrameworkSynonyms(
                    identifier: entry.identifier,
                    synonyms: entry.synonyms
                )
                affected += 1
            }
            return EnrichmentModels.Result(
                passIdentifier: identifier,
                rowsAffected: affected,
                rowsSkipped: 0,
                durationMs: 0
            )
        }

        /// Hand-curated alias list. Each entry maps a Swift framework
        /// identifier (lowercased; e.g. `corebluetooth`) to a comma-separated
        /// list of natural-language search terms users would type instead.
        static let aliases: [(identifier: String, synonyms: String)] = [
            ("corenfc", "nfc"),
            ("journalingsuggestions", "journaling"),
            ("corebluetooth", "bluetooth"),
            ("corelocation", "location"),
            ("coredata", "data"),
            ("coremotion", "motion"),
            ("coregraphics", "graphics"),
            ("coreimage", "imageprocessing"),
            ("coremedia", "media"),
            ("coreaudio", "audio"),
            ("coreml", "ml,machinelearning"),
            ("corespotlight", "spotlight"),
            ("coretext", "text"),
            ("corevideo", "video"),
            ("corehaptics", "haptics"),
            ("corewlan", "wifi,wlan"),
            ("coretelephony", "telephony"),
            ("metalperformanceshadersgraph", "mpsgraph"),
            ("avfoundation", "av"),
            ("scenekit", "scene"),
            ("spritekit", "sprite"),
            ("groupactivities", "shareplay"),
        ]
    }
}
