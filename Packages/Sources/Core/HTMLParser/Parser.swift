import CoreProtocols

// MARK: - Parser Namespace

extension Core {
    /// Namespace for content parsers (HTML, XML) that convert raw documentation
    /// payloads to Markdown for downstream indexing.
    public enum Parser {
        // Namespace root - parsers are defined as nested types in extensions:
        //   Core.Parser.HTML (HTMLToMarkdown)
        //   Core.Parser.XML  (XMLTransformer)
    }
}
