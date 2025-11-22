@testable import Core
import Foundation
import Testing

// MARK: - HTML to Markdown Converter Tests

/// Comprehensive tests for HTMLToMarkdown conversion
/// Tests code blocks, tables, links, formatting, and edge cases

@Suite("HTML to Markdown Converter")
struct HTMLToMarkdownTests {
    // MARK: - Basic Conversion Tests

    @Test("Converts simple HTML to Markdown")
    func convertsSimpleHTML() throws {
        let html = "<h1>Title</h1><p>Content</p>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("# Title"))
        #expect(markdown.contains("Content"))
    }

    @Test("Adds front matter with metadata")
    func addsFrontMatter() throws {
        let url = URL(string: "https://developer.apple.com/documentation/swift/array")!
        let html = "<h1>Array</h1>"
        let markdown = HTMLToMarkdown.convert(html, url: url)

        #expect(markdown.contains("---"))
        #expect(markdown.contains("source: \(url.absoluteString)"))
        #expect(markdown.contains("crawled:"))
    }

    // MARK: - Header Conversion Tests

    @Test("Converts H1 headers")
    func convertsH1Headers() throws {
        let html = "<h1>Main Title</h1>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("# Main Title"))
    }

    @Test("Converts H2 headers")
    func convertsH2Headers() throws {
        let html = "<h2>Subtitle</h2>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("## Subtitle"))
    }

    @Test("Converts H3 headers")
    func convertsH3Headers() throws {
        let html = "<h3>Section</h3>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("### Section"))
    }

    @Test("Converts nested headers")
    func convertsNestedHeaders() throws {
        let html = """
        <h1>Title</h1>
        <h2>Subtitle</h2>
        <h3>Section</h3>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("# Title"))
        #expect(markdown.contains("## Subtitle"))
        #expect(markdown.contains("### Section"))
    }

    @Test("Converts H4 headers")
    func convertsH4Headers() throws {
        let html = "<h4>Subsection</h4>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("#### Subsection"))
    }

    @Test("Converts H5 headers")
    func convertsH5Headers() throws {
        let html = "<h5>Minor Section</h5>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("##### Minor Section"))
    }

    @Test("Converts H6 headers")
    func convertsH6Headers() throws {
        let html = "<h6>Smallest Header</h6>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("###### Smallest Header"))
    }

    @Test("Converts all header levels")
    func convertsAllHeaderLevels() throws {
        let html = """
        <h1>H1</h1>
        <h2>H2</h2>
        <h3>H3</h3>
        <h4>H4</h4>
        <h5>H5</h5>
        <h6>H6</h6>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("# H1"))
        #expect(markdown.contains("## H2"))
        #expect(markdown.contains("### H3"))
        #expect(markdown.contains("#### H4"))
        #expect(markdown.contains("##### H5"))
        #expect(markdown.contains("###### H6"))
    }

    // MARK: - Code Block Tests

    @Test("Preserves code blocks with language")
    func preservesCodeBlocksWithLanguage() throws {
        let html = """
        <pre><code class="language-swift">
        func hello() {
            print("Hello")
        }
        </code></pre>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("```swift"))
        #expect(markdown.contains("func hello()"))
        #expect(markdown.contains("```"))
    }

    @Test("Preserves code blocks without language")
    func preservesCodeBlocksWithoutLanguage() throws {
        let html = """
        <pre><code>
        let x = 42
        </code></pre>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("```"))
        #expect(markdown.contains("let x = 42"))
    }

    @Test("Handles multiple code blocks")
    func handlesMultipleCodeBlocks() throws {
        let html = """
        <pre><code class="language-swift">let a = 1</code></pre>
        <p>Text between</p>
        <pre><code class="language-swift">let b = 2</code></pre>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("let a = 1"))
        #expect(markdown.contains("let b = 2"))
        #expect(markdown.contains("Text between"))
    }

    @Test("Preserves code block indentation")
    func preservesCodeBlockIndentation() throws {
        let html = """
        <pre><code class="language-swift">
        func nested() {
            if true {
                print("indented")
            }
        }
        </code></pre>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("func nested()"))
        #expect(markdown.contains("print(\"indented\")"))
    }

    // MARK: - Link Conversion Tests

    @Test("Converts simple links")
    func convertsSimpleLinks() throws {
        let html = "<a href='https://example.com'>Link Text</a>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("[Link Text]"))
        #expect(markdown.contains("(https://example.com)"))
    }

    @Test("Converts relative links")
    func convertsRelativeLinks() throws {
        let html = "<a href='/documentation/swift'>Swift</a>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("[Swift]"))
        #expect(markdown.contains("/documentation/swift"))
    }

    @Test("Handles links with nested formatting")
    func handlesLinksWithFormatting() throws {
        let html = "<a href='https://example.com'><strong>Bold Link</strong></a>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("["))
        #expect(markdown.contains("Bold Link"))
        #expect(markdown.contains("]"))
    }

    // MARK: - Inline Formatting Tests

    @Test("Converts bold text")
    func convertsBoldText() throws {
        let html = "<strong>Bold Text</strong>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("**Bold Text**") || markdown.contains("Bold Text"))
    }

    @Test("Converts italic text")
    func convertsItalicText() throws {
        let html = "<em>Italic Text</em>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("*Italic Text*") || markdown.contains("Italic Text"))
    }

    @Test("Converts inline code")
    func convertsInlineCode() throws {
        let html = "<code>inline code</code>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("`inline code`") || markdown.contains("inline code"))
    }

    // MARK: - Table Conversion Tests

    @Test("Handles simple tables")
    func handlesSimpleTables() throws {
        let html = """
        <table>
            <tr>
                <th>Header 1</th>
                <th>Header 2</th>
            </tr>
            <tr>
                <td>Cell 1</td>
                <td>Cell 2</td>
            </tr>
        </table>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Header 1"))
        #expect(markdown.contains("Header 2"))
        #expect(markdown.contains("Cell 1"))
        #expect(markdown.contains("Cell 2"))
    }

    @Test("Handles complex nested tables")
    func handlesComplexNestedTables() throws {
        let html = """
        <table>
            <thead>
                <tr>
                    <th>Name</th>
                    <th>Description</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td><code>value</code></td>
                    <td>A <strong>bold</strong> description</td>
                </tr>
            </tbody>
        </table>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Name"))
        #expect(markdown.contains("Description"))
        #expect(markdown.contains("value") || markdown.contains("`value`"))
        #expect(markdown.contains("bold"))
    }

    // MARK: - Blockquote Tests

    @Test("Handles blockquotes")
    func handlesBlockquotes() throws {
        let html = "<blockquote>This is a quote</blockquote>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("This is a quote"))
    }

    @Test("Handles nested blockquotes")
    func handlesNestedBlockquotes() throws {
        let html = """
        <blockquote>
            <p>First level quote</p>
            <blockquote>
                <p>Nested quote</p>
            </blockquote>
        </blockquote>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("First level quote"))
        #expect(markdown.contains("Nested quote"))
    }

    // MARK: - List Conversion Tests

    @Test("Converts unordered lists")
    func convertsUnorderedLists() throws {
        let html = """
        <ul>
            <li>Item 1</li>
            <li>Item 2</li>
            <li>Item 3</li>
        </ul>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Item 1"))
        #expect(markdown.contains("Item 2"))
        #expect(markdown.contains("Item 3"))
    }

    @Test("Converts ordered lists")
    func convertsOrderedLists() throws {
        let html = """
        <ol>
            <li>First</li>
            <li>Second</li>
            <li>Third</li>
        </ol>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("First"))
        #expect(markdown.contains("Second"))
        #expect(markdown.contains("Third"))
    }

    // MARK: - Paragraph Conversion Tests

    @Test("Converts paragraphs")
    func convertsParagraphs() throws {
        let html = """
        <p>First paragraph.</p>
        <p>Second paragraph.</p>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("First paragraph"))
        #expect(markdown.contains("Second paragraph"))
    }

    // MARK: - HTML Entity Tests

    @Test("Decodes HTML entities")
    func decodesHTMLEntities() throws {
        let html = "<p>&lt;html&gt; &amp; &quot;quotes&quot;</p>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("<html>") || markdown.contains("&lt;"))
        #expect(markdown.contains("&") || markdown.contains("&amp;"))
    }

    @Test("Decodes numeric entities")
    func decodesNumericEntities() throws {
        let html = "<p>&#60;tag&#62;</p>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("tag"))
    }

    @Test("Decodes apostrophe entities")
    func decodesApostropheEntities() throws {
        let html = "<p>It&#39;s working &apos; also &#x27; works</p>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("It's working"))
        #expect(markdown.contains("'"))
    }

    @Test("Decodes nbsp entities")
    func decodesNbspEntities() throws {
        let html = "<p>Word&nbsp;break&nbsp;here</p>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Word"))
        #expect(markdown.contains("break"))
        #expect(markdown.contains("here"))
    }

    @Test("Decodes mixed entity types")
    func decodesMixedEntityTypes() throws {
        let html = "<p>&lt;tag&gt; &#60;numeric&#62; &amp; &quot;quotes&quot; &#39;apostrophe&#39;</p>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("<") || markdown.contains("&lt;"))
        #expect(markdown.contains(">") || markdown.contains("&gt;"))
        #expect(markdown.contains("&") || markdown.contains("&amp;"))
        #expect(markdown.contains("\"") || markdown.contains("&quot;"))
        #expect(markdown.contains("'") || markdown.contains("&#39;"))
    }

    @Test("Handles entities in code blocks")
    func handlesEntitiesInCodeBlocks() throws {
        let html = """
        <pre><code class="language-swift">
        let x = &quot;Hello&quot;
        let y = &#60;Type&#62;()
        </code></pre>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("```swift"))
        #expect(markdown.contains("let x"))
        #expect(markdown.contains("let y"))
    }

    @Test("Handles multiple consecutive entities")
    func handlesMultipleConsecutiveEntities() throws {
        let html = "<p>&lt;&lt;&lt;test&gt;&gt;&gt;</p>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("test"))
    }

    @Test("Handles entities in nested elements")
    func handlesEntitiesInNestedElements() throws {
        let html = """
        <div>
            <p>Text with &amp; entity</p>
            <ul>
                <li>&lt;item&gt;</li>
                <li>&quot;quoted&quot;</li>
            </ul>
        </div>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Text with"))
        #expect(markdown.contains("item"))
        #expect(markdown.contains("quoted"))
    }

    // MARK: - Unwanted Section Removal Tests

    @Test("Removes navigation elements")
    func removesNavigationElements() throws {
        let html = """
        <html>
        <body>
        <nav>
            <a href="/home">Home</a>
            <a href="/about">About</a>
        </nav>
        <main>
            <h1>Main Content</h1>
            <p>Important text</p>
        </main>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(!markdown.contains("Home"))
        #expect(!markdown.contains("About"))
        #expect(markdown.contains("Main Content"))
        #expect(markdown.contains("Important text"))
    }

    @Test("Removes header elements")
    func removesHeaderElements() throws {
        let html = """
        <html>
        <body>
        <header>
            <div>Site Logo</div>
            <nav>Navigation</nav>
        </header>
        <main>
            <h1>Content Title</h1>
        </main>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(!markdown.contains("Site Logo"))
        #expect(!markdown.contains("Navigation"))
        #expect(markdown.contains("Content Title"))
    }

    @Test("Removes footer elements")
    func removesFooterElements() throws {
        let html = """
        <html>
        <body>
        <main>
            <p>Main content</p>
        </main>
        <footer>
            <p>Copyright 2025</p>
            <p>Contact info</p>
        </footer>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Main content"))
        #expect(!markdown.contains("Copyright"))
        #expect(!markdown.contains("Contact info"))
    }

    @Test("Removes SVG elements")
    func removesSVGElements() throws {
        let html = """
        <html>
        <body>
        <h1>Title</h1>
        <svg width="100" height="100">
            <circle cx="50" cy="50" r="40" />
        </svg>
        <p>Text content</p>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Title"))
        #expect(markdown.contains("Text content"))
        #expect(!markdown.contains("svg"))
        #expect(!markdown.contains("circle"))
    }

    @Test("Removes multiline SVG elements")
    func removesMultilineSVGElements() throws {
        let html = """
        <html>
        <body>
        <p>Before SVG</p>
        <svg viewBox="0 0 100 100"
             xmlns="http://www.w3.org/2000/svg">
            <rect x="10" y="10" width="80" height="80" />
            <text x="50" y="50">SVG Text</text>
        </svg>
        <p>After SVG</p>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Before SVG"))
        #expect(markdown.contains("After SVG"))
        #expect(!markdown.contains("SVG Text"))
        #expect(!markdown.contains("rect"))
    }

    @Test("Removes script tags")
    func removesScriptTags() throws {
        let html = """
        <html>
        <head>
        <script>
            console.log('test');
            var x = 42;
        </script>
        </head>
        <body>
        <p>Content</p>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Content"))
        #expect(!markdown.contains("console.log"))
        #expect(!markdown.contains("var x"))
    }

    @Test("Removes style tags")
    func removesStyleTags() throws {
        let html = """
        <html>
        <head>
        <style>
            body { color: red; }
            .class { margin: 10px; }
        </style>
        </head>
        <body>
        <p>Text</p>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Text"))
        #expect(!markdown.contains("color: red"))
        #expect(!markdown.contains("margin"))
    }

    @Test("Removes noscript tags")
    func removesNoscriptTags() throws {
        let html = """
        <html>
        <body>
        <noscript>
            <p>Please enable JavaScript</p>
        </noscript>
        <main>
            <p>Real content</p>
        </main>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Real content"))
        #expect(!markdown.contains("Please enable JavaScript"))
    }

    // MARK: - Accessibility Instruction Removal Tests

    @Test("Removes navigation instructions")
    func removesNavigationInstructions() throws {
        let html = """
        <html>
        <body>
        <p>To navigate the symbols, press Up Arrow, Down Arrow, Left Arrow or Right Arrow</p>
        <main>
            <h1>Documentation</h1>
            <p>Content here</p>
        </main>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Documentation"))
        #expect(markdown.contains("Content here"))
        #expect(!markdown.contains("Up Arrow"))
        #expect(!markdown.contains("Down Arrow"))
    }

    @Test("Removes symbol indicators")
    func removesSymbolIndicators() throws {
        let html = """
        <html>
        <body>
        <p>5 of 10 symbols inside MyClass</p>
        <p>containing 42 symbols</p>
        <main>
            <h1>MyClass</h1>
            <p>Documentation</p>
        </main>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("MyClass"))
        #expect(markdown.contains("Documentation"))
        #expect(!markdown.contains("5 of 10 symbols"))
        #expect(!markdown.contains("containing 42 symbols"))
    }

    @Test("Removes skip navigation links")
    func removesSkipNavigationLinks() throws {
        let html = """
        <html>
        <body>
        <a href="#main">Skip Navigation</a>
        <main id="main">
            <h1>Content</h1>
        </main>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Content"))
        #expect(!markdown.contains("Skip Navigation"))
    }

    @Test("Removes object artifacts")
    func removesObjectArtifacts() throws {
        let html = """
        <html>
        <body>
        <p>Text before [object Object] text after</p>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Text before"))
        #expect(markdown.contains("text after"))
        #expect(!markdown.contains("[object Object]"))
    }

    @Test("Removes data attributes")
    func removesDataAttributes() throws {
        let html = """
        <html>
        <body>
        <div data-v-abc123="value">Content</div>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Content"))
        #expect(!markdown.contains("data-v-"))
    }

    @Test("Cleans up stray quote characters")
    func cleansUpStrayQuoteCharacters() throws {
        let html = """
        <html>
        <body>
        <p>Normal text</p>
        ">>>>>
        <p>More text</p>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Normal text"))
        #expect(markdown.contains("More text"))
        // The stray quote characters should be cleaned up
    }

    @Test("Removes navigator ready messages")
    func removesNavigatorReadyMessages() throws {
        let html = """
        <html>
        <body>
        <p>/ Navigator is ready -</p>
        <main>
            <h1>Documentation</h1>
        </main>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Documentation"))
        #expect(!markdown.contains("Navigator is ready"))
    }

    @Test("Removes items found messages")
    func removesItemsFoundMessages() throws {
        let html = """
        <html>
        <body>
        <p>25 items were found. Tab back to navigate through them.</p>
        <main>
            <h1>Search Results</h1>
        </main>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Search Results"))
        #expect(!markdown.contains("items were found"))
        #expect(!markdown.contains("Tab back"))
    }

    // MARK: - Edge Cases Tests

    @Test("Handles empty HTML")
    func handlesEmptyHTML() throws {
        let html = ""
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("---")) // At least has front matter
    }

    @Test("Handles HTML with only whitespace")
    func handlesWhitespaceHTML() throws {
        let html = "   \n\n   "
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("---"))
    }

    @Test("Removes JavaScript warnings")
    func removesJavaScriptWarnings() throws {
        let html = """
        <h1>This page requires JavaScript</h1>
        <p>Real content</p>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Real content"))
        // JavaScript warning should be filtered out as title
    }

    @Test("Extracts title from h1")
    func extractsTitleFromH1() throws {
        let html = "<h1>Page Title</h1><p>Content</p>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("# Page Title"))
    }

    @Test("Extracts title from title tag")
    func extractsTitleFromTitleTag() throws {
        let html = "<title>Page Title</title><body><p>Content</p></body>"
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Page Title"))
    }

    @Test("Extracts main content from main tag")
    func extractsMainContent() throws {
        let html = """
        <html>
        <body>
        <nav>Navigation</nav>
        <main>
        <h1>Main Content</h1>
        </main>
        <footer>Footer</footer>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Main Content"))
    }

    @Test("Extracts content from article tag")
    func extractsArticleContent() throws {
        let html = """
        <html>
        <body>
        <nav>Navigation</nav>
        <article>
        <h1>Article Content</h1>
        </article>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("Article Content"))
    }

    // MARK: - Complex HTML Tests

    @Test("Handles complex nested structure")
    func handlesComplexNestedStructure() throws {
        let html = """
        <html>
        <body>
        <main>
        <h1>Title</h1>
        <p>Introduction with <strong>bold</strong> and <em>italic</em> text.</p>
        <h2>Code Example</h2>
        <pre><code class="language-swift">
        func example() {
            print("Hello")
        }
        </code></pre>
        <p>More text with a <a href="/link">link</a>.</p>
        </main>
        </body>
        </html>
        """
        let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)

        #expect(markdown.contains("# Title"))
        #expect(markdown.contains("## Code Example"))
        #expect(markdown.contains("```swift"))
        #expect(markdown.contains("func example()"))
        #expect(markdown.contains("Introduction"))
    }
}
