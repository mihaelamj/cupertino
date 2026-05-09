import Foundation
import Shared
import SQLite3

// swiftlint:disable function_body_length function_parameter_count
// Justification: extracted from SearchIndex.swift; the original 4598-line
// file's class_body_length / function_body_length / function_parameter_count
// rationale carries forward to the per-concern slices.

extension Search.Index {
    public func searchCodeExamples(
        query: String,
        limit: Int = 20
    ) async throws -> [(docUri: String, code: String, language: String)] {
        guard let database else {
            throw SearchError.databaseNotInitialized
        }

        let sql = """
        SELECT e.doc_uri, e.code, e.language
        FROM doc_code_examples e
        JOIN doc_code_fts f ON e.rowid = f.rowid
        WHERE doc_code_fts MATCH ?
        LIMIT ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SearchError.searchFailed("Code search prepare failed")
        }

        sqlite3_bind_text(statement, 1, (query as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var results: [(docUri: String, code: String, language: String)] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let docUri = String(cString: sqlite3_column_text(statement, 0))
            let code = String(cString: sqlite3_column_text(statement, 1))
            let language = String(cString: sqlite3_column_text(statement, 2))
            results.append((docUri: docUri, code: code, language: language))
        }

        return results
    }

    /// Get code examples count
    public func codeExamplesCount() async throws -> Int {
        guard let database else {
            throw SearchError.databaseNotInitialized
        }

        let sql = "SELECT COUNT(*) FROM doc_code_examples;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    /// Search sample code - optionally checks for local files in sampleCodeDirectory
    public func searchSampleCode(
        query: String,
        framework: String? = nil,
        limit: Int = Shared.Constants.Limit.defaultSearchLimit,
        sampleCodeDirectory: URL? = nil
    ) async throws -> [Search.SampleCodeResult] {
        guard let database else {
            throw SearchError.databaseNotInitialized
        }

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SearchError.invalidQuery("Query cannot be empty")
        }

        var sql = """
        SELECT
            f.url,
            f.framework,
            f.title,
            f.description,
            m.zip_filename,
            m.web_url,
            bm25(sample_code_fts) as rank
        FROM sample_code_fts f
        JOIN sample_code_metadata m ON f.url = m.url
        WHERE sample_code_fts MATCH ?
        """

        if framework != nil {
            sql += " AND f.framework = ?"
        }

        sql += " ORDER BY rank LIMIT ?;"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw SearchError.searchFailed("Sample code search prepare failed: \(errorMessage)")
        }

        // Bind parameters
        sqlite3_bind_text(statement, 1, (query as NSString).utf8String, -1, nil)

        if let framework {
            sqlite3_bind_text(statement, 2, (framework.lowercased() as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 3, Int32(limit))
        } else {
            sqlite3_bind_int(statement, 2, Int32(limit))
        }

        // Execute and collect results
        var results: [Search.SampleCodeResult] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let urlPtr = sqlite3_column_text(statement, 0),
                  let frameworkPtr = sqlite3_column_text(statement, 1),
                  let titlePtr = sqlite3_column_text(statement, 2),
                  let descriptionPtr = sqlite3_column_text(statement, 3),
                  let zipFilenamePtr = sqlite3_column_text(statement, 4),
                  let webURLPtr = sqlite3_column_text(statement, 5)
            else {
                continue
            }

            let url = String(cString: urlPtr)
            let framework = String(cString: frameworkPtr)
            let title = String(cString: titlePtr)
            let description = String(cString: descriptionPtr)
            let zipFilename = String(cString: zipFilenamePtr)
            let webURL = String(cString: webURLPtr)
            let rank = sqlite3_column_double(statement, 6)

            // Check if local file exists
            var localPath: String?
            var hasLocalFile = false
            if let sampleCodeDir = sampleCodeDirectory {
                let localFileURL = sampleCodeDir.appendingPathComponent(zipFilename)
                if FileManager.default.fileExists(atPath: localFileURL.path) {
                    localPath = localFileURL.path
                    hasLocalFile = true
                }
            }

            results.append(
                Search.SampleCodeResult(
                    url: url,
                    framework: framework,
                    title: title,
                    description: description,
                    zipFilename: zipFilename,
                    webURL: webURL,
                    localPath: localPath,
                    hasLocalFile: hasLocalFile,
                    rank: rank
                )
            )
        }

        return results
    }

    // MARK: - Indexing

    // Index a single document
    // - Parameters:
    //   - uri: Document URI
    //   - source: High-level source category (apple-docs, swift-evolution, swift-org, swift-book)
    //   - framework: Specific framework (swiftui, foundation, etc.) - nil for non-apple-docs sources
    //   - language: Programming language (swift, objc) - defaults to swift if not provided
    //   - title: Document title
    //   - content: Full document content
    //   - filePath: Path to source file
    //   - contentHash: SHA256 hash of content
    //   - lastCrawled: Crawl timestamp
    //   - sourceType: Legacy source type field (deprecated, use source instead)
    //   - packageId: Optional package ID for package docs
}
