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
        /// #673 Phase B — one-shot flag so a broken disk / closed file
        /// surfaces ONCE on stderr instead of either silently losing
        /// every audit entry (the pre-fix behaviour) or spamming the
        /// terminal with a warning per row. After the first warning the
        /// sink keeps trying to write (next entry may succeed; we don't
        /// know what state the FS is in) but stays quiet about repeated
        /// failures.
        private var hasWarnedAboutWriteFailure = false

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
            fileHandle = handle
            encoder = JSONEncoder()
            // Compact JSONL — no pretty-printing, one record per line.
            encoder.outputFormatting = .sortedKeys
            encoder.dateEncodingStrategy = .iso8601
        }

        /// The path the sink is writing to. Exposed so the CLI can
        /// print it in the save final report.
        public var logPath: URL {
            path
        }

        public func record(_ entry: Search.ImportLogEntry) async {
            do {
                let data = try encoder.encode(entry)
                try fileHandle.write(contentsOf: data)
                try fileHandle.write(contentsOf: Data([0x0a])) // newline
            } catch {
                // #673 Phase B — surface the first failure on stderr.
                // Silent loss of audit entries was pre-fix behaviour;
                // the JSONL log is the user's only record of what
                // `cupertino save` rejected, so a half-empty log with
                // no warning misleads later forensics (cf. today's
                // #669 audit where "112 chars" was actually the error
                // path because we'd lost visibility into earlier
                // failure modes).
                warnOnceAboutWriteFailure(error)
            }
        }

        private func warnOnceAboutWriteFailure(_ error: Swift.Error) {
            guard !hasWarnedAboutWriteFailure else { return }
            hasWarnedAboutWriteFailure = true
            let message = "⚠️  JSONL audit log write failure on \(path.lastPathComponent): " +
                "\(error). Subsequent failures will be silent; the audit log may be incomplete.\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
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
