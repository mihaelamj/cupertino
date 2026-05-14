import Foundation
import LoggingModels
import SharedConstants
extension Ingest {
    /// Crawl-session state helpers: clear saved sessions, requeue errored
    /// URLs, prepend missing URLs from a baseline corpus, enqueue a fixed
    /// URL list, find existing sessions on disk. All read/write
    /// `metadata.json` next to the corpus directory.
    ///
    /// Lifted verbatim from `CLI.FetchCommand` (#247). Same behaviour,
    /// same file format. Tests still drive these directly.
    public enum Session {
        /// Clear the saved crawl session at `outputDirectory`.
        /// `--start-clean` calls this before running the crawler.
        public static func clearSavedSession(at outputDirectory: URL, logger: any LoggingModels.Logging.Recording) throws {
            let metadataFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.metadata)
            guard FileManager.default.fileExists(atPath: metadataFile.path) else {
                logger.info(
                    "🧹 --start-clean: no saved session to clear at \(outputDirectory.path)"
                )
                return
            }
            var metadata = try Shared.Models.CrawlMetadata.load(from: metadataFile)
            metadata.crawlState = nil
            try metadata.save(to: metadataFile)
            logger.info(
                "🧹 --start-clean: cleared saved session at \(metadataFile.path)"
            )
        }

        /// Re-queue URLs that the crawler visited but never saved to the
        /// pages dict — typically pages whose save failed (filename too
        /// long, write errors, etc.). They get removed from the visited
        /// set and prepended to the queue at the configured `maxDepth`,
        /// so the resumed crawl retries them without re-discovering
        /// their children.
        public static func requeueErroredURLs(at outputDirectory: URL, maxDepth: Int, logger: any LoggingModels.Logging.Recording) throws {
            let metadataFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.metadata)
            guard FileManager.default.fileExists(atPath: metadataFile.path) else {
                logger.info(
                    "🔁 --retry-errors: no metadata.json at \(outputDirectory.path)"
                )
                return
            }
            var metadata = try Shared.Models.CrawlMetadata.load(from: metadataFile)
            guard var crawlState = metadata.crawlState else {
                logger.info(
                    "🔁 --retry-errors: no saved crawlState — nothing to retry"
                )
                return
            }

            let savedURLs = Set(metadata.pages.keys)
            let errored = crawlState.visited.subtracting(savedURLs)
            guard !errored.isEmpty else {
                logger.info(
                    "🔁 --retry-errors: no errored URLs to retry "
                        + "(every visited URL is in the pages dict)"
                )
                return
            }

            let erroredItems = errored.map { Shared.Models.QueuedURL(url: $0, depth: maxDepth) }
            crawlState.queue = erroredItems + crawlState.queue
            for url in errored {
                crawlState.visited.remove(url)
            }
            crawlState.lastSaveTime = Date()
            metadata.crawlState = crawlState
            try metadata.save(to: metadataFile)

            logger.info(
                "🔁 --retry-errors: re-queued \(errored.count) errored URL(s) "
                    + "at depth \(maxDepth) (front of queue)"
            )
        }

        /// Inject URLs from a known-good baseline corpus that aren't in
        /// the current crawl's known set (queue ∪ visited ∪ pages
        /// keys). Comparison is case-insensitive on the URL path so the
        /// broken-extractor's case-mixed output still matches the
        /// baseline's casing.
        public static func requeueFromBaseline(
            at outputDirectory: URL,
            baselineDir: URL,
            maxDepth: Int,
            logger: any LoggingModels.Logging.Recording
        ) throws {
            let metadataFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.metadata)
            guard FileManager.default.fileExists(atPath: metadataFile.path) else {
                logger.info(
                    "🩹 --baseline: no metadata.json at \(outputDirectory.path)"
                )
                return
            }
            guard FileManager.default.fileExists(atPath: baselineDir.path) else {
                logger.info(
                    "🩹 --baseline: directory not found at \(baselineDir.path)"
                )
                return
            }

            var metadata = try Shared.Models.CrawlMetadata.load(from: metadataFile)
            guard var crawlState = metadata.crawlState else {
                logger.info(
                    "🩹 --baseline: no saved crawlState — run with auto-resume "
                        + "or --start-clean first"
                )
                return
            }

            let baselineURLs = collectBaselineURLs(in: baselineDir)
            guard !baselineURLs.isEmpty else {
                logger.info(
                    "🩹 --baseline: no URLs found in baseline at \(baselineDir.path)"
                )
                return
            }

            var knownLowercased = Set<String>()
            knownLowercased.reserveCapacity(
                crawlState.visited.count + crawlState.queue.count + metadata.pages.count
            )
            for url in crawlState.visited {
                knownLowercased.insert(lowercaseDocPath(url))
            }
            for queued in crawlState.queue {
                knownLowercased.insert(lowercaseDocPath(queued.url))
            }
            for url in metadata.pages.keys {
                knownLowercased.insert(lowercaseDocPath(url))
            }

            var missing: [String] = []
            var seenLowercased = Set<String>()
            for url in baselineURLs {
                let key = lowercaseDocPath(url)
                if !knownLowercased.contains(key), seenLowercased.insert(key).inserted {
                    missing.append(url)
                }
            }
            guard !missing.isEmpty else {
                logger.info(
                    "🩹 --baseline: every baseline URL already known "
                        + "(\(baselineURLs.count) URLs checked)"
                )
                return
            }

            let injected = missing.map { Shared.Models.QueuedURL(url: $0, depth: maxDepth) }
            crawlState.queue = injected + crawlState.queue
            crawlState.lastSaveTime = Date()
            metadata.crawlState = crawlState
            try metadata.save(to: metadataFile)

            logger.info(
                "🩹 --baseline: prepended \(missing.count) missing URL(s) "
                    + "from \(baselineURLs.count)-URL baseline at depth \(maxDepth)"
            )
        }

        /// Enqueue every URL listed in `urlsFile` (one URL per line) at
        /// depth 0. The crawler then follows each URL's outgoing links
        /// up to `maxDepth`. Lines starting with `#` and blank lines
        /// are ignored. (#210)
        public static func enqueueURLsFromFile(
            at outputDirectory: URL,
            urlsFile: URL,
            maxDepth: Int,
            startURL: URL,
            logger: any LoggingModels.Logging.Recording
        ) throws {
            let lines = try String(contentsOf: urlsFile, encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }

            guard !lines.isEmpty else {
                logger.info(
                    "📥 --urls: file \(urlsFile.path) had no URLs to enqueue"
                )
                return
            }

            var validURLs: [String] = []
            for raw in lines {
                guard let parsed = URL(string: raw),
                      let scheme = parsed.scheme,
                      !scheme.isEmpty
                else {
                    throw FetchURLsError.invalidURL(line: raw)
                }
                validURLs.append(raw)
            }

            let metadataFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.metadata)
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )

            var metadata: Shared.Models.CrawlMetadata
            if FileManager.default.fileExists(atPath: metadataFile.path) {
                metadata = try Shared.Models.CrawlMetadata.load(from: metadataFile)
            } else {
                metadata = Shared.Models.CrawlMetadata()
            }

            var crawlState = metadata.crawlState ?? Shared.Models.CrawlSessionState(
                startURL: startURL.absoluteString,
                outputDirectory: outputDirectory.path
            )

            let newItems = validURLs.map { Shared.Models.QueuedURL(url: $0, depth: 0) }
            crawlState.queue = newItems + crawlState.queue
            crawlState.lastSaveTime = Date()
            metadata.crawlState = crawlState
            try metadata.save(to: metadataFile)

            logger.info(
                "📥 --urls: enqueued \(validURLs.count) URL(s) from "
                    + "\(urlsFile.lastPathComponent) at depth 0 "
                    + "(descent up to maxDepth=\(maxDepth))"
            )
        }

        /// Walk `directory` looking for a saved session whose `startURL`
        /// matches the supplied `url`. Returns the directory itself
        /// (not the saved `outputDirectory` field) so the result works
        /// across rsynced corpora where the on-disk path drifts.
        public static func checkForSession(at directory: URL, matching url: URL, logger: any LoggingModels.Logging.Recording) -> URL? {
            let metadataFile = directory.appendingPathComponent(Shared.Constants.FileName.metadata)
            guard FileManager.default.fileExists(atPath: metadataFile.path),
                  let data = try? Data(contentsOf: metadataFile),
                  let metadata = try? Shared.Utils.JSONCoding.decode(Shared.Models.CrawlMetadata.self, from: data),
                  let session = metadata.crawlState,
                  session.isActive,
                  session.startURL == url.absoluteString
            else {
                return nil
            }
            logger.info(
                "📂 Found existing session, resuming to: \(directory.path)"
            )
            return directory
        }

        // MARK: - Internal helpers

        /// Walk the baseline directory and return every URL recorded in
        /// any JSON page file's top-level `url` field. Skips
        /// unparseable files — a corrupt baseline shouldn't block a
        /// recrawl.
        static func collectBaselineURLs(in baselineDir: URL) -> [String] {
            let fileManager = FileManager.default
            guard let enumerator = fileManager.enumerator(
                at: baselineDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            var urls: [String] = []
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension.lowercased() == "json" else { continue }
                guard let data = try? Data(contentsOf: fileURL),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let dict = object as? [String: Any],
                      let url = dict["url"] as? String,
                      !url.isEmpty
                else { continue }
                urls.append(url)
            }
            return urls
        }

        /// Lowercase the `/documentation/...` path portion of an Apple
        /// docs URL so case differences (HTML extractor's lowercase vs
        /// JSON extractor's case-preserving output) don't produce
        /// false-positive gaps.
        static func lowercaseDocPath(_ urlString: String) -> String {
            guard let docMarkerRange = urlString.range(of: "/documentation/") else {
                return urlString.lowercased()
            }
            let prefix = urlString[..<docMarkerRange.upperBound]
            let path = urlString[docMarkerRange.upperBound...].lowercased()
            return prefix + path
        }
    }
}
