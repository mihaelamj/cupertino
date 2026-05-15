import Foundation
import SearchModels

// MARK: - Search.JSONLImportLogSink

extension Search {
    /// Concrete ``Search.ImportLogSink`` that appends each entry as a
    /// single JSONL line to a file on disk. Used by `cupertino save`
    /// (real and `--dry-run`) to emit the per-doc audit log described
    /// in `docs/PRINCIPLES.md` principle 3.
    ///
    /// Actor-isolated so concurrent strategy paths (directory scan +
    /// metadata-driven, plus any future parallel strategies) can write
    /// without stepping on each other; the line-by-line append order
    /// matches the order strategies call ``record(_:)``.
    public actor JSONLImportLogSink: Search.ImportLogSink {
        public enum SinkError: Swift.Error {
            case couldNotCreateLogFile(URL)
        }

        private let path: URL
        private var fileHandle: FileHandle
        private let encoder: JSONEncoder

        public init(path: URL) throws {
            self.path = path
            // Make sure the parent dir exists.
            let parent = path.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            // Create / truncate the file so each run produces a clean log.
            FileManager.default.createFile(atPath: path.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: path) else {
                throw SinkError.couldNotCreateLogFile(path)
            }
            self.fileHandle = handle
            self.encoder = JSONEncoder()
            // Compact JSONL — no pretty-printing, one record per line.
            self.encoder.outputFormatting = .sortedKeys
            self.encoder.dateEncodingStrategy = .iso8601
        }

        /// The path the sink is writing to. Exposed so the CLI can
        /// print it in the save final report.
        public var logPath: URL { path }

        public func record(_ entry: Search.ImportLogEntry) async {
            guard let data = try? encoder.encode(entry) else { return }
            try? fileHandle.write(contentsOf: data)
            try? fileHandle.write(contentsOf: Data([0x0A])) // newline
        }

        /// Flush + close. Call once at the end of the indexing run so
        /// the OS file handle is released even if the caller crashes
        /// later. Idempotent — repeated closes are a no-op.
        public func close() async {
            try? fileHandle.synchronize()
            try? fileHandle.close()
        }
    }
}
