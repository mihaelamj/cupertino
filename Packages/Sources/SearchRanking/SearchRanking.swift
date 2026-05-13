import Foundation
import SharedConstants

/// Constants and heuristics used for search result ranking.
public enum SearchRanking {
    /// Apple-docs framework authority used as a HEURISTIC 1 tiebreak (#256).
    ///
    /// Only consulted when an apple-docs row already hit the exact-title boost
    /// in HEURISTIC 1 — i.e. multiple frameworks have a top-level page whose
    /// title equals the query (e.g. `Result` on Swift, Vision, Installer JS).
    /// At that point BM25F has nothing useful to say about which framework is
    /// canonical for the bare type name. The map nudges the canonical pick.
    ///
    /// Values are multipliers on `boost` (lower = stronger boost; FTS5 ranks
    /// are negative so smaller multipliers push higher). Frameworks not in
    /// the map default to 1.0 (no nudge).
    ///
    /// Kept narrow on purpose: only frameworks with an actual canonical-page
    /// conflict whose resolution is uncontroversial. Adding a framework here
    /// is an authority claim — be conservative.
    public static let frameworkAuthority: [String: Double] = [
        "swift": 0.5, // language types (Result, Task, String, ...)
        "swiftui": 0.7, // primary UI framework
        "foundation": 0.7, // primary system framework
        "installer_js": 1.4, // niche packaging-script API
        "webkitjs": 1.4, // legacy WebKit JS bindings
        "javascriptcore": 1.2, // JS bridge
        "devicemanagement": 1.2, // MDM payload schemas
    ]
}
