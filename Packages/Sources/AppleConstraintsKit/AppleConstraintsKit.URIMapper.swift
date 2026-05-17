import Foundation

extension AppleConstraintsKit {
    /// Pure-function transform from symbol-graph identity
    /// (`module` + `pathComponents`) to the cupertino-internal
    /// `apple-docs://<framework>/<path>` URI shape stored in
    /// `doc_symbols.doc_uri`.
    ///
    /// **Algorithm.**
    /// 1. Lowercase the module name (`"SwiftUI"` → `"swiftui"`). The
    ///    cupertino crawler stores Apple's docs under all-lowercase
    ///    URL slugs; the module-name PascalCase is dropped here.
    /// 2. Lowercase each path component the same way.
    /// 3. Join with `/`; prefix with `apple-docs://`.
    ///
    /// **What this maps to.**
    /// - Type-level: `["ForEach"]` → `apple-docs://swiftui/foreach`.
    ///   Exact match against the page-level `doc_symbols.doc_uri`.
    /// - Method / init / subscript-level:
    ///   `["NavigationLink", "init(_:isActive:destination:)"]` →
    ///   `apple-docs://swiftui/navigationlink/init(_:isactive:destination:)`.
    ///   This is the **un-disambiguated** form. Apple's URL renderer
    ///   appends a `-<hash>` suffix to distinguish overloads
    ///   (`init(_:content:)-7l1jb`). The symbol-graph itself doesn't
    ///   emit the hash; we don't have it. The consumer
    ///   (`Search.Index.applyAppleStaticConstraints`) handles the
    ///   discrepancy via a `LIKE doc_uri || '-%'` fallback after
    ///   the exact-match UPDATE.
    ///
    /// **Pure / stateless.** Per `gof-di-rules.md` rule 2. pure free
    /// functions are allowed; nothing here is a collaborator.
    public enum URIMapper {
        /// Construct the cupertino-style URI for one symbol-graph
        /// entry. Returns nil only when `pathComponents` is empty,
        /// which shouldn't happen in well-formed symbol-graph JSON
        /// (Apple's emitter always names at least the module-relative
        /// symbol path).
        public static func uri(
            forModule module: String,
            pathComponents: [String]
        ) -> String? {
            guard !pathComponents.isEmpty else {
                return nil
            }
            let frameworkSlug = module.lowercased()
            let pathSlug = pathComponents
                .map { $0.lowercased() }
                .joined(separator: "/")
            return "apple-docs://\(frameworkSlug)/\(pathSlug)"
        }

        /// Convert the symbol-graph URI to its "prefix" form for
        /// LIKE-matching against hash-disambiguated rows.
        ///
        /// Apple's URL renderer appends `-<hash>` to disambiguate
        /// overloaded init / subscript / method URIs. The symbol-graph
        /// emits the un-disambiguated form. For SQL UPDATE,
        /// `doc_uri = uri` matches non-overloaded rows; `doc_uri LIKE
        /// uri || '-%'` catches the hash-suffixed variants.
        ///
        /// Returns the LIKE pattern (suitable for direct binding to a
        /// `LIKE ?` parameter).
        public static func likePrefix(for uri: String) -> String {
            uri + "-%"
        }
    }
}
