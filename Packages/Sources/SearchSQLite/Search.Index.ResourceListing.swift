import Foundation
import SearchModels
import SharedConstants
import SQLite3

// MARK: - Search.Index resources/list enumeration

extension Search.Index {
    /// Enumerate this DB's slice of the MCP `resources/list` page,
    /// purely from `docs_metadata` (+ `docs_structured` for titles).
    /// Principle 7 (`docs/PRINCIPLES.md`): no filesystem is consulted.
    ///
    /// - `.none`: empty (source exposes no MCP-resource URIs).
    /// - `.frameworkRoots`: one entry per distinct `framework` whose
    ///   framework-root URI (`<scheme><framework>`) is itself a row in
    ///   `docs_metadata`. Used by apple-docs (~350k sub-pages collapse
    ///   to ~398 readable roots).
    /// - `.allDocuments`: one entry per `docs_metadata` row, with the
    ///   `docs_structured.title` as the display name (falling back to
    ///   the URI's last path component). Used by the small docs
    ///   corpora (hig, swift-org, swift-book, swift-evolution,
    ///   apple-archive).
    public func listResourceEntries(
        mode: Search.ResourceListMode
    ) async throws -> [Search.URIResource] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        switch mode {
        case .none:
            return []
        case .frameworkRoots:
            return try frameworkRootResourceEntries(database: database)
        default:
            // `.allDocuments` and any future mode default to a full
            // per-row enumeration.
            return try allDocumentResourceEntries(database: database)
        }
    }

    private func frameworkRootResourceEntries(
        database: OpaquePointer
    ) throws -> [Search.URIResource] {
        // Only emit a framework whose root URI actually exists as a row
        // (so every listed resource is readable via readResource). The
        // root URI has no path segment beyond the framework, e.g.
        // `apple-docs://swiftui`.
        let sql = """
        SELECT m.uri, COALESCE(s.title, '') AS title, m.framework
        FROM docs_metadata m
        LEFT JOIN docs_structured s ON m.uri = s.uri
        WHERE m.uri = m.source || '://' || m.framework
        ORDER BY m.framework;
        """
        return try runResourceQuery(sql, database: database, fallbackToFramework: true)
    }

    private func allDocumentResourceEntries(
        database: OpaquePointer
    ) throws -> [Search.URIResource] {
        let sql = """
        SELECT m.uri, COALESCE(s.title, '') AS title, m.framework
        FROM docs_metadata m
        LEFT JOIN docs_structured s ON m.uri = s.uri
        ORDER BY m.uri;
        """
        return try runResourceQuery(sql, database: database, fallbackToFramework: false)
    }

    private func runResourceQuery(
        _ sql: String,
        database: OpaquePointer,
        fallbackToFramework: Bool
    ) throws -> [Search.URIResource] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("List resources failed: \(errorMessage)")
        }

        var resources: [Search.URIResource] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let uriPtr = sqlite3_column_text(statement, 0) else { continue }
            let uri = String(cString: uriPtr)
            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let framework = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""

            let name = Self.displayName(uri: uri, title: title, framework: framework, fallbackToFramework: fallbackToFramework)
            let description = framework.isEmpty ? "Documentation" : "Documentation: \(framework)"
            resources.append(Search.URIResource(uri: uri, name: name, description: description))
        }
        return resources
    }

    /// Resolve a display name for a resource entry: prefer the stored
    /// structured title; for framework-root entries with no title fall
    /// back to the (capitalised) framework; otherwise fall back to the
    /// URI's last path component.
    static func displayName(
        uri: String,
        title: String,
        framework: String,
        fallbackToFramework: Bool
    ) -> String {
        if !title.isEmpty {
            return title
        }
        if fallbackToFramework, !framework.isEmpty {
            return framework
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
        // Last path component of the URI (drop the scheme + path).
        let withoutScheme: String
        if let range = uri.range(of: "://") {
            withoutScheme = String(uri[range.upperBound...])
        } else {
            withoutScheme = uri
        }
        let lastComponent = withoutScheme.split(separator: "/").last.map(String.init) ?? withoutScheme
        return lastComponent.isEmpty ? uri : lastComponent
    }
}
