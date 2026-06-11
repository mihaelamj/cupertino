import Foundation
import LoggingModels
import SearchModels

extension CLIImpl {
    /// Per-save JSONL audit log for the enrichment pipeline. Captures
    /// `recordPassStart` / `recordEntry` / `recordPassEnd` events from
    /// every per-source DB enrichment pass and writes them to a
    /// single file at `<base-dir>/enrichment-<ISO8601>.jsonl`.
    ///
    /// 2026-05-27: added after a 9.5-hour Claw mini apple-docs reindex
    /// finished with zero per-pass visibility. Pre-fix the only signal
    /// was the one-line `[enrichment/<pass>] affected=N skipped=N (Nms)`
    /// summary; you couldn't tell which of the 61,040 lookup entries
    /// actually matched rows or which frameworks the pass missed. This
    /// writer emits one JSON line per matched URI so a grep on the
    /// file answers questions like "did Foundation's NSDecimalNumber
    /// get its constraint" without re-querying the DB.
    ///
    /// Format: each line is a self-contained JSON object with `event`,
    /// `timestamp`, `pass`, `dbPath`, plus event-specific fields.
    /// File is line-buffered; the JSONL is safe to tail mid-run.
    final class LiveEnrichmentAuditWriter: SearchModels.Search.EnrichmentAuditObserver {
        private let fileURL: URL
        private let queue = DispatchQueue(label: "cupertino.enrichment-audit")
        private nonisolated(unsafe) var handle: FileHandle?

        init(baseDirectory: URL, runTimestamp: Date = Date()) {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            let stamp = isoFormatter.string(from: runTimestamp).replacingOccurrences(of: ":", with: "-")
            fileURL = baseDirectory.appendingPathComponent("enrichment-\(stamp).jsonl")
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            handle = try? FileHandle(forWritingTo: fileURL)
        }

        /// Path to the audit JSONL file. Surfaced to the user at save
        /// end so they know where to grep for per-URI detail.
        var path: URL {
            fileURL
        }

        deinit {
            try? handle?.close()
        }

        func recordPassStart(passIdentifier: String, dbPath: String) {
            write([
                "event": "pass-start",
                "pass": passIdentifier,
                "dbPath": dbPath,
                "timestamp": isoTimestamp(),
            ])
        }

        func recordEntry(
            passIdentifier: String,
            docURI: String,
            value: String,
            matchType: String,
            rowsAffected: Int
        ) {
            write([
                "event": "entry",
                "pass": passIdentifier,
                "dbPath": "",
                "doc_uri": docURI,
                "value": value,
                "match_type": matchType,
                "rows_affected": "\(rowsAffected)",
                "timestamp": isoTimestamp(),
            ])
        }

        func recordPassEnd(
            passIdentifier: String,
            totalRowsAffected: Int,
            totalRowsSkipped: Int,
            durationMs: Int
        ) {
            write([
                "event": "pass-end",
                "pass": passIdentifier,
                "total_rows_affected": "\(totalRowsAffected)",
                "total_rows_skipped": "\(totalRowsSkipped)",
                "duration_ms": "\(durationMs)",
                "timestamp": isoTimestamp(),
            ])
        }

        // MARK: - JSONL writer

        private func isoTimestamp() -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: Date())
        }

        private func write(_ object: [String: String]) {
            guard let handle else { return }
            // Render as a single-line JSON object. Hand-rolled to keep
            // ordering stable + avoid the JSONSerialization
            // string-quoting overhead per entry (60k+ lines on a full
            // run).
            var line = "{"
            var first = true
            let numericKeys: Set = [
                "rows_affected", "total_rows_affected", "total_rows_skipped", "duration_ms",
            ]
            for (key, value) in object where !value.isEmpty || numericKeys.contains(key) {
                if !first { line += "," }
                first = false
                line += "\"\(key)\":\(jsonEscape(value))"
            }
            line += "}\n"
            queue.sync {
                try? handle.write(contentsOf: Data(line.utf8))
            }
        }

        private func jsonEscape(_ string: String) -> String {
            // Numeric-looking values (counts, durations) pass through
            // unquoted; everything else gets quoted + escaped.
            if Int(string) != nil { return string }
            var escaped = "\""
            for char in string {
                switch char {
                case "\"": escaped += "\\\""
                case "\\": escaped += "\\\\"
                case "\n": escaped += "\\n"
                case "\r": escaped += "\\r"
                case "\t": escaped += "\\t"
                default: escaped.append(char)
                }
            }
            escaped += "\""
            return escaped
        }
    }
}
