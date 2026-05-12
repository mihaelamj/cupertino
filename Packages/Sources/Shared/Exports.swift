// Re-export the SharedConstants and SharedUtils modules so callers that
// `import Shared` keep seeing `Shared.Constants.*`, `Shared.BinaryConfig`,
// `Shared.Formatting`, `Shared.FTSQuery`, `Shared.SchemaVersion`, the
// `Shared` namespace itself, and the module-level `JSONCoding` and
// `PathResolver` types, all of which now live in SharedConstants /
// SharedUtils. Removed in task 1.6 along with the `Shared` target rename
// to `SharedCore`.
@_exported import SharedConstants
@_exported import SharedModels
@_exported import SharedUtils
