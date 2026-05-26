import Foundation

// MARK: - Distribution module namespace

/// `Distribution` is the download + extract pipeline for the
/// pre-built database bundle. The CLI's `cupertino setup` subcommand
/// orchestrates it.
///
/// Layout:
/// - `Distribution.SetupService` → top-level orchestrator: takes a
///   `Request`, emits `Event`s, returns an `Outcome`. The CLI subscribes
///   via a `SetupService.EventObserving` conformer.
/// - `Distribution.ArtifactDownloader` → URLSession-backed file
///   download with a `Progress` reporter.
/// - `Distribution.ArtifactExtractor` → ZIP extraction with a
///   `TickObserving` callback for progress bar animation.
/// - `Distribution.InstalledVersion` → reads / writes / classifies
///   the `.installed-version` stamp under the cupertino base dir.
/// - `Distribution.SetupError` → typed errors thrown by the pipeline.
///
/// **Target split.** The value types (`Request`, `Outcome`, `Event`,
/// `Progress`, `Status`, `SetupError`) plus the GoF Observer protocols
/// (`EventObserving`, `ProgressObserving`, `TickObserving`) live here
/// in `DistributionModels` (foundation-only seam). The concrete
/// `static func` orchestrators (`SetupService.run`,
/// `ArtifactDownloader.download`, `ArtifactExtractor.extract`,
/// `InstalledVersion.read` / `.write` / `.classify`) live in the
/// `Distribution` producer target as extensions on the same enums.
public enum Distribution {}
