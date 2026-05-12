// Re-export the SharedConstants module so callers that `import Shared` keep
// seeing `Shared.Constants.*` and the `Shared` namespace itself, both of
// which now live in SharedConstants. Removed in task 1.6 along with the
// `Shared` target rename to `SharedCore`.
@_exported import SharedConstants
