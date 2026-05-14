import Foundation

// MARK: - Logging namespace anchor

/// Foundation-only namespace anchor for the `Logging` SPM target pair.
///
/// Lives in `LoggingModels` (this target) so consumers can take
/// `any Logging.Recording` as an injected parameter without importing
/// the concrete `Logging` target. The concrete `Logging` target
/// re-uses this same namespace via `import LoggingModels` and adds
/// `Logging.LiveRecording`, the OSLog + console + file
/// implementation.
///
/// Mirrors the lifted-Models pattern used elsewhere in the monorepo
/// (`SearchModels`, `SampleIndexModels`, `ServicesModels`,
/// `CorePackageIndexingModels`, `CrawlerModels`): producers consume
/// the protocol type; the binary supplies the conformance witness at
/// the composition root.
public enum Logging {}
