import Foundation
import Shared
import SQLite3

extension Search {
    // MARK: - Public API

    public enum QueryIntent: String, Sendable {
        case howTo           // "how do I ...", "how to ..."
        case example         // "show me an example of ...", "example of ..."
        case symbolLookup    // "what is the signature of ...", "what does X do"
        case crossReference  // "where is X used", "who uses X"
    }

    public struct PackageSearchResult: Sendable {
        public let owner: String
        public let repo: String
        public let relpath: String
        public let kind: String
        public let module: String?
        public let title: String
        public let score: Double
        public let chunk: String
    }

    /// Plain-text-question → top-N ranked chunks. Strategy:
    ///  1. Classify intent from the question string.
    ///  2. Pull top-20 BM25 candidates from `package_files_fts` using
    ///     intent-specific column weights + kind filter.
    ///  3. Extract the most relevant chunk from each (`##` section for
    ///     markdown, enclosing Swift declaration for source).
    ///  4. Rescore with per-intent kind bonus; dedupe by file; return top N.
    public actor PackageQuery {
        private var database: OpaquePointer?
        private let dbPath: URL

        public init(dbPath: URL = Shared.Constants.defaultPackagesDatabase) async throws {
            self.dbPath = dbPath
            var dbPointer: OpaquePointer?
            guard sqlite3_open_v2(dbPath.path, &dbPointer, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                let message = String(cString: sqlite3_errmsg(dbPointer))
                sqlite3_close(dbPointer)
                throw PackageQueryError.openFailed(message)
            }
            database = dbPointer
        }

        public func disconnect() {
            if let database {
                sqlite3_close(database)
                self.database = nil
            }
        }

        public func answer(_ question: String, maxResults: Int = 3) throws -> [PackageSearchResult] {
            guard database != nil else { throw PackageQueryError.databaseNotOpen }

            let intent = IntentClassifier.classify(question)
            let config = IntentConfig.for(intent)
            let ftsQuery = Self.buildFTSQuery(question: question)
            guard !ftsQuery.isEmpty else { return [] }

            let candidates = try fetchCandidates(
                ftsQuery: ftsQuery,
                weights: config.columnWeights,
                kinds: config.kindFilter,
                limit: 20
            )

            let queryTokens = Self.tokens(from: question)
            var scored: [(score: Double, result: PackageSearchResult)] = []
            var seenPaths = Set<String>()

            for c in candidates {
                let key = "\(c.owner)/\(c.repo)/\(c.relpath)"
                if seenPaths.contains(key) { continue }
                seenPaths.insert(key)

                let chunk = ChunkExtractor.extract(
                    relpath: c.relpath,
                    content: c.content,
                    queryTokens: queryTokens,
                    maxChunkLines: 60
                )
                // lower bm25 = better; invert so bigger is better
                let baseScore = -c.bm25
                let bonus = config.kindBonus(for: c.kind)
                let finalScore = baseScore + bonus

                scored.append((
                    finalScore,
                    PackageSearchResult(
                        owner: c.owner,
                        repo: c.repo,
                        relpath: c.relpath,
                        kind: c.kind,
                        module: c.module,
                        title: c.title,
                        score: finalScore,
                        chunk: chunk
                    )
                ))
            }

            return scored
                .sorted { $0.score > $1.score }
                .prefix(maxResults)
                .map(\.result)
        }

        // MARK: - Candidate fetch

        private struct Candidate {
            let owner: String
            let repo: String
            let module: String?
            let relpath: String
            let kind: String
            let title: String
            let content: String
            let bm25: Double
        }

        private func fetchCandidates(
            ftsQuery: String,
            weights: IntentConfig.Weights,
            kinds: Set<String>,
            limit: Int
        ) throws -> [Candidate] {
            guard let database else { throw PackageQueryError.databaseNotOpen }

            let kindList = kinds.map { "'\($0)'" }.joined(separator: ",")
            let sql = """
            SELECT owner, repo, module, relpath, kind, title, content,
                   bm25(package_files_fts, \(weights.title), \(weights.content), \(weights.symbols)) AS score
            FROM package_files_fts
            WHERE package_files_fts MATCH ?
              AND kind IN (\(kindList))
            ORDER BY score
            LIMIT \(limit)
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw PackageQueryError.sqliteError(String(cString: sqlite3_errmsg(database)))
            }
            sqlite3_bind_text(statement, 1, ftsQuery, -1, SQLITE_TRANSIENT_QUERY)

            var results: [Candidate] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let owner = String(cString: sqlite3_column_text(statement, 0))
                let repo = String(cString: sqlite3_column_text(statement, 1))
                let module: String?
                if sqlite3_column_type(statement, 2) == SQLITE_NULL {
                    module = nil
                } else {
                    module = String(cString: sqlite3_column_text(statement, 2))
                }
                let relpath = String(cString: sqlite3_column_text(statement, 3))
                let kind = String(cString: sqlite3_column_text(statement, 4))
                let title = String(cString: sqlite3_column_text(statement, 5))
                let content = String(cString: sqlite3_column_text(statement, 6))
                let bm25 = sqlite3_column_double(statement, 7)
                results.append(Candidate(
                    owner: owner, repo: repo, module: module, relpath: relpath,
                    kind: kind, title: title, content: content, bm25: bm25
                ))
            }
            return results
        }

        // MARK: - FTS query construction

        /// Build an FTS MATCH expression from natural language:
        /// - tokenize (alphanumeric + underscore + period runs)
        /// - drop stopwords
        /// - OR the remaining tokens with prefix matching where useful
        internal static func buildFTSQuery(question: String) -> String {
            let tokens = Self.tokens(from: question)
            guard !tokens.isEmpty else { return "" }
            // AND the meaningful tokens. FTS5 MATCH supports implicit AND via spaces
            // but we wrap each in quotes to avoid operator parsing for punctuated ids.
            return tokens.map { "\"\($0)\"" }.joined(separator: " OR ")
        }

        internal static func tokens(from question: String) -> [String] {
            let stopwords: Set<String> = [
                "how", "to", "do", "i", "can", "you", "please", "show", "me", "give",
                "a", "an", "the", "is", "are", "of", "for", "in", "on", "with", "and",
                "or", "what", "where", "who", "why", "when", "does", "using", "use",
                "find", "example", "examples", "sample", "my", "some", "any",
            ]
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_."))
            var current = ""
            var tokens: [String] = []
            for scalar in question.unicodeScalars {
                if allowed.contains(scalar) {
                    current.append(Character(scalar))
                } else if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            }
            if !current.isEmpty { tokens.append(current) }
            return tokens
                .filter { $0.count >= 2 }
                .filter { !stopwords.contains($0.lowercased()) }
        }
    }

    // MARK: - Intent classifier

    internal enum IntentClassifier {
        static func classify(_ question: String) -> QueryIntent {
            let lower = question.lowercased()
            if lower.contains("where is") || lower.contains("who uses") || lower.contains("who calls")
                || lower.contains("usage of")
            {
                return .crossReference
            }
            if lower.contains("signature") || lower.contains("declaration")
                || lower.hasPrefix("what does") || lower.hasPrefix("what is the ")
            {
                return .symbolLookup
            }
            if lower.contains("example") || lower.hasPrefix("show me") || lower.hasPrefix("give me")
                || lower.contains("sample")
            {
                return .example
            }
            return .howTo
        }
    }

    // MARK: - Per-intent config

    internal struct IntentConfig {
        struct Weights {
            let title: Double
            let content: Double
            let symbols: Double
        }

        let columnWeights: Weights
        let kindFilter: Set<String>
        let kindOrder: [String]  // best → worst for bonus

        func kindBonus(for kind: String) -> Double {
            guard let idx = kindOrder.firstIndex(of: kind) else { return 0 }
            // Ranks: first entry gets the biggest bonus, each step down decreases.
            return Double(kindOrder.count - idx)
        }

        static func `for`(_ intent: QueryIntent) -> IntentConfig {
            switch intent {
            case .howTo:
                return IntentConfig(
                    columnWeights: .init(title: 10, content: 5, symbols: 1),
                    kindFilter: ["doccArticle", "projectDoc", "readme", "doccTutorial", "changelog"],
                    kindOrder: ["doccArticle", "projectDoc", "readme", "doccTutorial", "changelog"]
                )
            case .example:
                return IntentConfig(
                    columnWeights: .init(title: 1, content: 3, symbols: 10),
                    kindFilter: ["example", "test", "source", "doccTutorial"],
                    kindOrder: ["example", "test", "doccTutorial", "source"]
                )
            case .symbolLookup:
                return IntentConfig(
                    columnWeights: .init(title: 0.1, content: 2, symbols: 20),
                    kindFilter: ["source", "doccArticle", "projectDoc"],
                    kindOrder: ["source", "doccArticle", "projectDoc"]
                )
            case .crossReference:
                return IntentConfig(
                    columnWeights: .init(title: 1, content: 5, symbols: 5),
                    kindFilter: ["source", "test", "example"],
                    kindOrder: ["source", "test", "example"]
                )
            }
        }
    }

    // MARK: - Chunk extractor

    internal enum ChunkExtractor {
        /// Return the most relevant chunk of a file given query tokens.
        /// - markdown: the `## `-delimited section containing the first token
        ///   match (or the file-leading preamble if no match).
        /// - Swift: the enclosing `func`/`struct`/`class`/`extension`/`actor`/
        ///   `enum`/`protocol`/`init` declaration around the first match line,
        ///   up to the matching brace close. Falls back to ±20 lines.
        /// - Otherwise: first 60 lines.
        static func extract(
            relpath: String,
            content: String,
            queryTokens: [String],
            maxChunkLines: Int
        ) -> String {
            let lower = relpath.lowercased()
            if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
                return markdownChunk(content: content, queryTokens: queryTokens, maxLines: maxChunkLines)
            }
            if lower.hasSuffix(".swift") {
                return swiftChunk(content: content, queryTokens: queryTokens, maxLines: maxChunkLines)
            }
            return firstLines(content: content, count: maxChunkLines)
        }

        static func markdownChunk(content: String, queryTokens: [String], maxLines: Int) -> String {
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            // Build section ranges: indices of lines starting with "## "
            var sectionStarts: [Int] = [0]
            for (i, line) in lines.enumerated() {
                if line.hasPrefix("## ") { sectionStarts.append(i) }
            }
            sectionStarts.append(lines.count)

            // Find the section containing the first match
            let lowerTokens = queryTokens.map { $0.lowercased() }
            for sectionIdx in 0..<(sectionStarts.count - 1) {
                let start = sectionStarts[sectionIdx]
                let end = sectionStarts[sectionIdx + 1]
                for i in start..<end {
                    let lineLower = lines[i].lowercased()
                    if lowerTokens.contains(where: { lineLower.contains($0) }) {
                        let take = Swift.min(end - start, maxLines)
                        return lines[start..<(start + take)].joined(separator: "\n")
                    }
                }
            }
            // Fallback: first section
            let end = Swift.min(sectionStarts[1], maxLines)
            return lines[0..<end].joined(separator: "\n")
        }

        static func swiftChunk(content: String, queryTokens: [String], maxLines: Int) -> String {
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let lowerTokens = queryTokens.map { $0.lowercased() }

            // Find first line with a token match.
            var matchLine: Int?
            for (i, line) in lines.enumerated() {
                let l = line.lowercased()
                if lowerTokens.contains(where: { l.contains($0) }) {
                    matchLine = i
                    break
                }
            }
            guard let matchLine else {
                return firstLines(content: content, count: maxLines)
            }

            // Walk backwards for enclosing declaration.
            let declMarkers = ["func ", "struct ", "class ", "extension ", "actor ", "enum ", "protocol ", "init"]
            var start = matchLine
            var declLine: Int?
            while start >= 0 {
                let trimmed = lines[start].trimmingCharacters(in: .whitespaces)
                if declMarkers.contains(where: { trimmed.hasPrefix($0) })
                    || trimmed.hasPrefix("public ")
                    || trimmed.hasPrefix("private ")
                    || trimmed.hasPrefix("internal ")
                    || trimmed.hasPrefix("open ")
                    || trimmed.hasPrefix("fileprivate ")
                {
                    declLine = start
                    break
                }
                start -= 1
            }
            let begin = declLine ?? Swift.max(0, matchLine - 10)
            let take = Swift.min(maxLines, lines.count - begin)
            return lines[begin..<(begin + take)].joined(separator: "\n")
        }

        static func firstLines(content: String, count: Int) -> String {
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            let take = Swift.min(count, lines.count)
            return lines.prefix(take).joined(separator: "\n")
        }
    }

    public enum PackageQueryError: Error, LocalizedError {
        case openFailed(String)
        case databaseNotOpen
        case sqliteError(String)

        public var errorDescription: String? {
            switch self {
            case .openFailed(let m): return "Could not open packages.db: \(m)"
            case .databaseNotOpen: return "packages.db connection closed"
            case .sqliteError(let m): return "SQLite error: \(m)"
            }
        }
    }
}

// Separate name to avoid collision with the same constant in PackageIndex.swift
// (both files define a private SQLITE_TRANSIENT but Swift is fine with per-file
// private naming collisions).
private let SQLITE_TRANSIENT_QUERY = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
