import CoreProtocols
import Foundation

// MARK: - Core.JSONParser Namespace

// Note: the `Core.JSONParser` namespace anchor lives in `CoreProtocols`
// (foundation tier) post-#904 so the `CoreJSONParserWebKit` sibling
// target can extend `Core.JSONParser.*` without importing the parent
// producer. Per-feature constants on the namespace are added below via
// `extension Core.JSONParser`.
extension Core.JSONParser {
    /// Module version
    public static let version = "1.0.0"
}
