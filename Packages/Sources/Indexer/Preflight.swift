import Foundation
import SharedCore
import SharedConstants
import SharedUtils

extension Indexer {
    /// Pre-write inspection of the on-disk corpus state. Surfaces missing
    /// or un-annotated sources before any DB write so the user can bail
    /// out before a half-populated save run. Drives both the `cupertino
    /// save` confirmation prompt and the read-only `cupertino doctor
    /// --save` summary (#232).
    public enum Preflight {
        // MARK: - Composed report

        /// Build the printable preflight summary lines for the chosen
        /// scope. Pure: no I/O beyond filesystem reads, no stdin/stdout.
        public static func preflightLines(
            buildDocs: Bool,
            buildPackages: Bool,
            buildSamples: Bool,
            baseDir: String? = nil,
            docsDir: String? = nil,
            samplesDir: String? = nil
        ) -> [String] {
            var lines: [String] = []
            let fm = FileManager.default
            let effectiveBase = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? Shared.Constants.defaultBaseDirectory

            if buildDocs {
                lines.append(contentsOf: docsLines(
                    effectiveBase: effectiveBase,
                    docsDir: docsDir,
                    fm: fm
                ))
            }
            if buildPackages {
                lines.append(contentsOf: packagesLines(
                    effectiveBase: effectiveBase,
                    fm: fm
                ))
            }
            if buildSamples {
                lines.append(contentsOf: samplesLines(
                    samplesDir: samplesDir,
                    fm: fm
                ))
            }
            return lines
        }

        private static func docsLines(
            effectiveBase: URL,
            docsDir: String?,
            fm: FileManager
        ) -> [String] {
            var lines = ["  Docs (search.db)"]
            let docsURL = docsDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.docs)
            if fm.fileExists(atPath: docsURL.path) {
                let count = (try? fm.subpathsOfDirectory(atPath: docsURL.path).count) ?? 0
                lines.append("    ✓  \(docsURL.path)  (\(count) entries)")
                if checkDocsHaveAvailability(docsDir: docsURL) {
                    lines.append("    ✓  Availability annotation present")
                } else {
                    lines.append("    ⚠  Availability annotation NOT detected")
                    lines.append("       min_ios / min_macos / etc. columns will be NULL.")
                    lines.append("       Run `cupertino fetch --type availability` first for platform filtering.")
                }
            } else {
                lines.append("    ✗  \(docsURL.path)  (missing — docs scope will be skipped)")
            }
            lines.append("")
            return lines
        }

        private static func packagesLines(effectiveBase: URL, fm: FileManager) -> [String] {
            var lines = ["  Packages (packages.db)"]
            let packagesURL = effectiveBase.appendingPathComponent(Shared.Constants.Directory.packages)
            if fm.fileExists(atPath: packagesURL.path) {
                let stats = countPackagesAndSidecars(at: packagesURL)
                lines.append("    ✓  \(packagesURL.path)  (\(stats.packages) packages)")
                if stats.packages == 0 {
                    lines.append("    ⚠  No <owner>/<repo>/ subdirs — nothing to index.")
                } else if stats.sidecars == stats.packages {
                    lines.append("    ✓  availability.json sidecars  (\(stats.sidecars)/\(stats.packages))")
                } else {
                    lines.append("    ⚠  availability.json sidecars  (\(stats.sidecars)/\(stats.packages))")
                    lines.append(
                        "       Missing \(stats.packages - stats.sidecars) — run "
                            + "`cupertino fetch --type packages --skip-metadata --skip-archives "
                            + "--annotate-availability` to backfill."
                    )
                }
            } else {
                lines.append("    ✗  \(packagesURL.path)  (missing — packages scope will be skipped)")
            }
            lines.append("")
            return lines
        }

        private static func samplesLines(samplesDir: String?, fm: FileManager) -> [String] {
            var lines = ["  Samples (samples.db)"]
            let samplesURL = samplesDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? Shared.Constants.defaultSampleCodeDirectory
            if fm.fileExists(atPath: samplesURL.path) {
                let zipCount = (try? fm.contentsOfDirectory(atPath: samplesURL.path))?
                    .filter { $0.hasSuffix(".zip") }.count ?? 0
                lines.append("    ✓  \(samplesURL.path)  (\(zipCount) zips)")
                if zipCount == 0 {
                    lines.append("    ⚠  No zips — nothing to index.")
                } else {
                    lines.append("    (annotation runs inline during save — no preflight check needed)")
                }
            } else {
                lines.append("    ✗  \(samplesURL.path)  (missing — samples scope will be skipped)")
            }
            lines.append("")
            return lines
        }

        // MARK: - Standalone probes

        /// Heuristic: does the docs corpus on disk carry availability
        /// annotations from `cupertino fetch --type availability`? Sampled
        /// — we don't read every page. Good enough for preflight + the
        /// inline docs-mode warning. True when at least half of the
        /// sampled JSONs carry an `availability` key.
        public static func checkDocsHaveAvailability(docsDir: URL) -> Bool {
            let report = sampleDocsAvailability(docsDir: docsDir)
            return report.checked > 0 && report.withAvailability >= (report.checked / 2)
        }

        /// Pure inspection — counts how many sampled docs JSON files
        /// carry an `availability` field. Internal API surface so tests
        /// can pin both the sampling shape and the threshold separately.
        public static func sampleDocsAvailability(
            docsDir: URL,
            maxFrameworks: Int = 5,
            maxSamples: Int = 3
        ) -> (checked: Int, withAvailability: Int) {
            guard FileManager.default.fileExists(atPath: docsDir.path) else {
                return (0, 0)
            }
            guard let frameworks = try? FileManager.default.contentsOfDirectory(
                at: docsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return (0, 0)
            }

            var checked = 0
            var withAvailability = 0
            for frameworkDir in frameworks.prefix(maxFrameworks) {
                guard checked < maxSamples else { break }
                guard isDirectory(frameworkDir) else { continue }
                guard let firstJSON = firstJSONFile(in: frameworkDir) else { continue }
                checked += 1
                if jsonContainsAvailability(at: firstJSON) {
                    withAvailability += 1
                }
            }
            return (checked, withAvailability)
        }

        /// Count `<owner>/<repo>/` directories under `packagesURL` and
        /// how many carry an `availability.json` sidecar (#219 stage 3).
        public static func countPackagesAndSidecars(
            at packagesURL: URL
        ) -> (packages: Int, sidecars: Int) {
            let fm = FileManager.default
            guard let owners = try? fm.contentsOfDirectory(
                at: packagesURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return (0, 0) }

            var packageCount = 0
            var sidecarCount = 0
            for ownerURL in owners {
                guard isDirectory(ownerURL) else { continue }
                guard let repos = try? fm.contentsOfDirectory(
                    at: ownerURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for repoURL in repos {
                    guard isDirectory(repoURL) else { continue }
                    packageCount += 1
                    let sidecarURL = repoURL.appendingPathComponent("availability.json")
                    if fm.fileExists(atPath: sidecarURL.path) {
                        sidecarCount += 1
                    }
                }
            }
            return (packageCount, sidecarCount)
        }

        // MARK: - Internal helpers

        private static func isDirectory(_ url: URL) -> Bool {
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }

        private static func firstJSONFile(in directory: URL) -> URL? {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { return nil }
            return files.first { $0.pathExtension == "json" }
        }

        private static func jsonContainsAvailability(at url: URL) -> Bool {
            guard let data = try? Data(contentsOf: url) else { return false }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            return json["availability"] != nil
        }
    }
}
