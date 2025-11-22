import Testing

// MARK: - Shared Test Tags

/// Centralized test tags used across all test targets
/// This prevents duplicate tag definitions and ensures consistency
public extension Tag {
    /// Integration tests that make real network requests or use real resources
    @Tag static var integration: Self

    /// CLI-specific tests
    @Tag static var cli: Self

    /// MCP server-specific tests
    @Tag static var mcp: Self

    /// Tests that take a long time to complete
    @Tag static var slow: Self
}
