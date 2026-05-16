import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SharedConstants
import Testing

// MARK: - #113 follow-up — audit-count emission via the indexer logger

//
// PR #710 (the #113 base PR) shipped the doc:// → https:// rewriter
// + the wire contract + the post-save invariant. It explicitly deferred
// the audit-count emission ("save run emits rewrite count to logs")
// to a small follow-up — that's this PR.
//
// Contract: when the rewriter substitutes one or more occurrences in a
// given page, the indexer emits a `debug` record via the injected
// logger with the count + the URI. Zero-count pages stay silent (the
// vast majority of indexed pages have no doc:// at all; logging on
// every page would drown the save logs in no-op events).
//
// The test installs a thread-safe in-memory `Logging.Recording` that
// captures every record, indexes a couple of pages with assorted
// doc:// shapes, then asserts the captured records carry the expected
// audit signal.

private final class CapturingRecording: LoggingModels.Logging.Recording, @unchecked Sendable {
    private let lock = NSLock()
    private var _records: [(message: String, level: LoggingModels.Logging.Level, category: LoggingModels.Logging.Category)] = []

    func record(_ message: String, level: LoggingModels.Logging.Level, category: LoggingModels.Logging.Category) {
        lock.lock(); defer { lock.unlock() }
        _records.append((message, level, category))
    }

    func output(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        _records.append((message, .info, .cli))
    }

    var records: [(message: String, level: LoggingModels.Logging.Level, category: LoggingModels.Logging.Category)] {
        lock.lock(); defer { lock.unlock() }
        return _records
    }
}

@Suite("#113 follow-up — audit-count emission on indexer rewrite", .serialized)
struct Issue113AuditCountEmissionTests {
    private func makeIndex(logger: any LoggingModels.Logging.Recording) async throws -> (Search.Index, URL) {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-113-audit-\(UUID().uuidString).db")
        let index = try await Search.Index(dbPath: tempDB, logger: logger)
        return (index, tempDB)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("indexDocument with 2 doc:// in content + 1 in jsonData emits a debug record with total=3")
    func indexDocumentEmitsTotalCount() async throws {
        let recorder = CapturingRecording()
        let (index, dbPath) = try await makeIndex(logger: recorder)
        defer { cleanup(dbPath) }

        let dirtyContent = """
        See doc://X/documentation/swiftui/view and doc://Y/documentation/swiftui/viewbuilder.
        """
        let dirtyJSON = #"{"raw":"doc://Z/documentation/swiftui/text"}"#

        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: "apple-docs://swiftui/view",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: "View",
            content: dirtyContent,
            filePath: "/tmp/view.json",
            contentHash: "audit-1",
            lastCrawled: Date(),
            jsonData: dirtyJSON
        ))
        await index.disconnect()

        let auditRecords = recorder.records.filter { $0.message.contains("doc-link-rewrite") }
        #expect(auditRecords.count == 1, "expected exactly one audit-count record per call; got: \(auditRecords.count)")
        guard let record = auditRecords.first else {
            Issue.record("no audit record captured")
            return
        }
        #expect(
            record.message.contains("3 substitutions"),
            "audit record must report total count of 3 (2 in content + 1 in json); got: \(record.message)"
        )
        #expect(
            record.message.contains("apple-docs://swiftui/view"),
            "audit record must name the URI being indexed; got: \(record.message)"
        )
        #expect(record.level == .debug, "audit record must be at .debug level (low-traffic, opt-in); got: \(record.level)")
        #expect(record.category == .search, "audit record category must be .search; got: \(record.category)")
    }

    @Test("indexDocument with zero doc:// emits no audit record (no log spam on clean pages)")
    func indexDocumentZeroCountStaysSilent() async throws {
        let recorder = CapturingRecording()
        let (index, dbPath) = try await makeIndex(logger: recorder)
        defer { cleanup(dbPath) }

        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: "apple-docs://swiftui/clean",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: "Clean",
            content: "Plain prose with https://developer.apple.com/documentation/swiftui/view inside.",
            filePath: "/tmp/clean.json",
            contentHash: "audit-2",
            lastCrawled: Date(),
            jsonData: nil
        ))
        await index.disconnect()

        let auditRecords = recorder.records.filter { $0.message.contains("doc-link-rewrite") }
        #expect(auditRecords.isEmpty, "zero-count case must stay silent; got: \(auditRecords.map(\.message))")
    }

    @Test("indexStructuredDocument with doc:// in jsonData emits a debug record with the count")
    func indexStructuredDocumentEmitsCount() async throws {
        let recorder = CapturingRecording()
        let (index, dbPath) = try await makeIndex(logger: recorder)
        defer { cleanup(dbPath) }

        let url = try #require(URL(string: "https://developer.apple.com/documentation/swiftui/view"))
        let dirtyJSON = #"{"raw":"doc://X/documentation/swiftui/viewbuilder"}"#
        let page = Shared.Models.StructuredDocumentationPage(
            url: url,
            title: "View",
            kind: .protocol,
            source: .appleJSON,
            contentHash: "audit-struct-1"
        )

        try await index.indexStructuredDocument(
            uri: "apple-docs://swiftui/view",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            page: page,
            jsonData: dirtyJSON
        )
        await index.disconnect()

        let auditRecords = recorder.records.filter { $0.message.contains("doc-link-rewrite") }
        #expect(!auditRecords.isEmpty, "structured-doc path must emit audit count too; got nothing")
        if let record = auditRecords.first {
            #expect(
                record.message.contains("substitutions in apple-docs://swiftui/view"),
                "audit record must name the URI; got: \(record.message)"
            )
            #expect(record.level == .debug)
            #expect(record.category == .search)
        }
    }

    @Test("multi-page save aggregates: 3 dirty pages emit 3 audit records, 1 clean page stays silent (4 total → 3 audit lines)")
    func multiPageAggregate() async throws {
        let recorder = CapturingRecording()
        let (index, dbPath) = try await makeIndex(logger: recorder)
        defer { cleanup(dbPath) }

        let pages: [(uri: String, content: String, expectAudit: Bool)] = [
            ("apple-docs://uikit/uibutton", "Inherits from doc://X/documentation/uikit/uicontrol.", true),
            ("apple-docs://uikit/uicontrol", "Inherits from doc://X/documentation/uikit/uiview.", true),
            ("apple-docs://uikit/uiview", "Inherits from doc://X/documentation/uikit/uiresponder.", true),
            ("apple-docs://uikit/clean", "No doc:// here.", false),
        ]

        for page in pages {
            try await index.indexDocument(Search.Index.IndexDocumentParams(
                uri: page.uri,
                source: Shared.Constants.SourcePrefix.appleDocs,
                framework: "uikit",
                title: page.uri,
                content: page.content,
                filePath: "/tmp/\(UUID().uuidString).json",
                contentHash: "audit-multi-\(UUID().uuidString.prefix(8))",
                lastCrawled: Date()
            ))
        }
        await index.disconnect()

        let auditRecords = recorder.records.filter { $0.message.contains("doc-link-rewrite") }
        let expectedAuditCount = pages.filter(\.expectAudit).count
        #expect(
            auditRecords.count == expectedAuditCount,
            "audit-record count must match dirty-page count; expected \(expectedAuditCount), got: \(auditRecords.count) — messages: \(auditRecords.map(\.message))"
        )
        // The clean page's URI must NOT appear in any audit record.
        for record in auditRecords {
            #expect(
                !record.message.contains("uikit/clean"),
                "clean page must not surface in any audit record; got: \(record.message)"
            )
        }
    }
}
