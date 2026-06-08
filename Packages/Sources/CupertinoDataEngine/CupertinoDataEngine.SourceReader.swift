import SearchModels

// MARK: - CupertinoDataEngine.SourceReader

extension CupertinoDataEngine {
    /// App-facing name for Cupertino's source read surface.
    ///
    /// UI/backend clients ask Cupertino for source readers; they do not open
    /// or name the storage implementation that backs those readers.
    public protocol SourceReader: Search.DocumentReading, Search.SymbolReading {}

    /// App-facing document-browser refinement for expandable documentation UI.
    public protocol SourceBrowser: SourceReader, Search.DocumentBrowsing {}
}
