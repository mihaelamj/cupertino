import Foundation
import SharedConstants

// MARK: - Sample archive quarantine recovery (#657)

extension CLIImpl {
    /// One archive moved out of the active corpus during a quarantine sweep.
    struct QuarantinedArchive: Equatable {
        /// The original `.zip` path that failed ZIP-header validation.
        let original: URL
        /// Where it was parked (`<name>.invalid`), or `nil` in a dry run.
        let parkedAs: URL?
    }

    /// Sweep `directory` for `.zip` files whose header is not a valid ZIP
    /// (HTML landing pages / partial CDN bodies saved as `.zip`) and park
    /// each as `<name>.invalid`, removing it from the active corpus.
    ///
    /// #657: the per-download quarantine in `Sample.Core.Downloader`
    /// already parks a freshly-downloaded non-ZIP body, so new fetches are
    /// clean. But the issue recurred on an *installed* corpus carrying
    /// invalid archives from before that guard (or from the GitHub-mirror
    /// distribution): nothing removed them, and `cupertino save --samples`
    /// would keep tripping over them. This is the recovery path for an
    /// already-landed corpus, sharing the exact validity check
    /// (`Shared.Utils.ZipMagic.isValid`) the downloader and `doctor` use.
    ///
    /// Pure except for the optional move (`dryRun == false`); returns one
    /// `QuarantinedArchive` per invalid `.zip` found, so the caller can
    /// report counts and a dry run can preview without mutating disk.
    ///
    /// - Parameters:
    ///   - directory: the sample-code directory to sweep.
    ///   - dryRun: when `true`, report what would be parked without moving.
    /// - Returns: the invalid archives found (in directory order), each with
    ///   its parked destination (or `nil` under `dryRun`).
    static func quarantineInvalidSampleArchives(
        in directory: URL,
        dryRun: Bool = false
    ) -> [QuarantinedArchive] {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let invalidZips = contents
            .filter { $0.pathExtension.lowercased() == "zip" }
            .filter { !Shared.Utils.ZipMagic.isValid(at: $0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var results: [QuarantinedArchive] = []
        for zip in invalidZips {
            guard !dryRun else {
                results.append(QuarantinedArchive(original: zip, parkedAs: nil))
                continue
            }
            let parked = zip.appendingPathExtension("invalid")
            // A stale `.invalid` from a prior sweep must not block the move.
            if fm.fileExists(atPath: parked.path) {
                try? fm.removeItem(at: parked)
            }
            do {
                try fm.moveItem(at: zip, to: parked)
                results.append(QuarantinedArchive(original: zip, parkedAs: parked))
            } catch {
                // Leave it in place if the move fails; report it un-parked so
                // the caller's count still reflects the detection.
                results.append(QuarantinedArchive(original: zip, parkedAs: nil))
            }
        }
        return results
    }
}
