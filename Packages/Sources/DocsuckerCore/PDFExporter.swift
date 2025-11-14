import Foundation
import WebKit
import DocsuckerLogging
#if canImport(AppKit)
import AppKit
#endif

// MARK: - PDF Exporter

/// Exports markdown documentation to PDF format
@MainActor
public final class PDFExporter {
    private let inputDirectory: URL
    private let outputDirectory: URL
    private let maxFiles: Int?
    private let forceExport: Bool

    public init(inputDirectory: URL, outputDirectory: URL, maxFiles: Int? = nil, forceExport: Bool = false) {
        self.inputDirectory = inputDirectory
        self.outputDirectory = outputDirectory
        self.maxFiles = maxFiles
        self.forceExport = forceExport
    }

    // MARK: - Public API

    /// Export markdown files to PDF
    public func export(onProgress: ((PDFProgress) -> Void)? = nil) async throws -> PDFStatistics {
        var stats = PDFStatistics(startTime: Date())

        logInfo("📄 Starting PDF export")
        logInfo("   Input: \(inputDirectory.path)")
        logInfo("   Output: \(outputDirectory.path)")

        // Find all markdown files
        logInfo("\n📋 Scanning for markdown files...")
        let markdownFiles = try findMarkdownFiles()
        logInfo("   Found \(markdownFiles.count) markdown files")

        // Limit if needed
        let filesToExport = if let maxFiles {
            Array(markdownFiles.prefix(maxFiles))
        } else {
            markdownFiles
        }

        logInfo("   Exporting \(filesToExport.count) files\n")

        // Export each file
        for (index, fileURL) in filesToExport.enumerated() {
            do {
                try await exportFile(fileURL, stats: &stats)

                // Progress callback
                if let onProgress {
                    let progress = PDFProgress(
                        current: index + 1,
                        total: filesToExport.count,
                        fileName: fileURL.lastPathComponent,
                        stats: stats
                    )
                    onProgress(progress)
                }
            } catch {
                stats.errors += 1
                logError("Failed to export \(fileURL.lastPathComponent): \(error)")
            }
        }

        stats.endTime = Date()

        logInfo("\n✅ Export completed!")
        logStatistics(stats)

        return stats
    }

    // MARK: - Private Methods

    private func findMarkdownFiles() throws -> [URL] {
        var files: [URL] = []

        if let enumerator = FileManager.default.enumerator(
            at: inputDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "md" {
                    files.append(fileURL)
                }
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    private func exportFile(_ fileURL: URL, stats: inout PDFStatistics) async throws {
        logInfo("📄 [\(stats.totalFiles + 1)] \(fileURL.lastPathComponent)")

        // Determine output path
        let relativePath = fileURL.path.replacingOccurrences(of: inputDirectory.path, with: "")
        let outputPath = outputDirectory.appendingPathComponent(relativePath).deletingPathExtension().appendingPathExtension("pdf")

        // Check if already exists
        if !forceExport && FileManager.default.fileExists(atPath: outputPath.path) {
            stats.skippedFiles += 1
            stats.totalFiles += 1
            logInfo("   ⏭️  Already exists, skipping")
            return
        }

        // Create output subdirectory if needed
        let outputDir = outputPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Read markdown content
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)

        // Convert markdown to HTML
        let html = convertMarkdownToHTML(markdown, title: fileURL.deletingPathExtension().lastPathComponent)

        // Generate PDF from HTML
        try await generatePDF(from: html, outputPath: outputPath)

        stats.exportedFiles += 1
        stats.totalFiles += 1
        logInfo("   ✅ Exported: \(outputPath.lastPathComponent)")
    }

    private func convertMarkdownToHTML(_ markdown: String, title: String) -> String {
        // Simple markdown to HTML conversion
        var html = markdown

        // Use the custom replacingOccurrences method from HTMLToMarkdown extension
        // Convert inline code first (before code blocks)
        html = regexReplace(html, pattern: #"`([^`]+)`"#, replacement: "<code>$1</code>")

        // Convert code blocks with language
        html = regexReplace(html, pattern: #"```(\w+)\n(.*?)\n```"#, replacement: "<pre><code class=\"language-$1\">$2</code></pre>")

        // Convert code blocks without language
        html = regexReplace(html, pattern: #"```\n(.*?)\n```"#, replacement: "<pre><code>$1</code></pre>")

        // Convert headers (with multiline option)
        html = regexReplace(html, pattern: #"^######\s+(.+)$"#, replacement: "<h6>$1</h6>", multiline: true)
        html = regexReplace(html, pattern: #"^#####\s+(.+)$"#, replacement: "<h5>$1</h5>", multiline: true)
        html = regexReplace(html, pattern: #"^####\s+(.+)$"#, replacement: "<h4>$1</h4>", multiline: true)
        html = regexReplace(html, pattern: #"^###\s+(.+)$"#, replacement: "<h3>$1</h3>", multiline: true)
        html = regexReplace(html, pattern: #"^##\s+(.+)$"#, replacement: "<h2>$1</h2>", multiline: true)
        html = regexReplace(html, pattern: #"^#\s+(.+)$"#, replacement: "<h1>$1</h1>", multiline: true)

        // Convert bold
        html = regexReplace(html, pattern: #"\*\*(.+?)\*\*"#, replacement: "<strong>$1</strong>")

        // Convert italic
        html = regexReplace(html, pattern: #"\*(.+?)\*"#, replacement: "<em>$1</em>")

        // Convert links
        html = regexReplace(html, pattern: #"\[([^\]]+)\]\(([^\)]+)\)"#, replacement: "<a href=\"$2\">$1</a>")

        // Convert paragraphs (double newlines)
        html = html.replacingOccurrences(of: "\n\n", with: "</p><p>")

        // Convert line breaks
        html = html.replacingOccurrences(of: "\n", with: "<br>")

        // Wrap in HTML document with styling
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>\(title)</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                    font-size: 12pt;
                    line-height: 1.6;
                    color: #333;
                    max-width: 800px;
                    margin: 40px auto;
                    padding: 0 20px;
                }
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 24px;
                    margin-bottom: 16px;
                    font-weight: 600;
                    line-height: 1.25;
                }
                h1 { font-size: 24pt; border-bottom: 1px solid #eee; padding-bottom: 8px; }
                h2 { font-size: 18pt; border-bottom: 1px solid #eee; padding-bottom: 6px; }
                h3 { font-size: 14pt; }
                h4 { font-size: 12pt; }
                code {
                    background: #f6f8fa;
                    padding: 2px 6px;
                    border-radius: 3px;
                    font-family: "SF Mono", Monaco, Consolas, monospace;
                    font-size: 10pt;
                }
                pre {
                    background: #f6f8fa;
                    padding: 16px;
                    border-radius: 6px;
                    overflow-x: auto;
                    border: 1px solid #e1e4e8;
                }
                pre code {
                    background: none;
                    padding: 0;
                }
                a {
                    color: #0366d6;
                    text-decoration: none;
                }
                a:hover {
                    text-decoration: underline;
                }
                p {
                    margin-bottom: 16px;
                }
            </style>
        </head>
        <body>
            <p>\(html)</p>
        </body>
        </html>
        """
    }

    private func generatePDF(from html: String, outputPath: URL) async throws {
        #if os(macOS)
        // Create a web view to render the HTML
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 595, height: 842)) // A4 size in points
        webView.loadHTMLString(html, baseURL: nil)

        // Wait for the page to load
        try await Task.sleep(for: .seconds(1))

        // Create PDF data
        let pdfData = try await webView.pdf(configuration: WKPDFConfiguration())

        // Write to file
        try pdfData.write(to: outputPath)
        #else
        throw PDFExporterError.unsupportedPlatform
        #endif
    }

    // MARK: - Utilities

    private func regexReplace(_ text: String, pattern: String, replacement: String, multiline: Bool = false) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: multiline ? [.anchorsMatchLines] : []
        ) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    // MARK: - Logging

    private func logInfo(_ message: String) {
        DocsuckerLogger.pdf.info(message)
        print(message)
    }

    private func logError(_ message: String) {
        let errorMessage = "❌ \(message)"
        DocsuckerLogger.pdf.error(message)
        fputs("\(errorMessage)\n", stderr)
    }

    private func logStatistics(_ stats: PDFStatistics) {
        let messages = [
            "📊 Statistics:",
            "   Total files: \(stats.totalFiles)",
            "   Exported: \(stats.exportedFiles)",
            "   Skipped: \(stats.skippedFiles)",
            "   Errors: \(stats.errors)",
            stats.duration.map { "   Duration: \(Int($0))s" } ?? "",
            "",
            "📁 Output: \(outputDirectory.path)",
        ]

        for message in messages where !message.isEmpty {
            DocsuckerLogger.pdf.info(message)
            print(message)
        }
    }
}

// MARK: - Models

public struct PDFStatistics: Sendable {
    public var totalFiles: Int = 0
    public var exportedFiles: Int = 0
    public var skippedFiles: Int = 0
    public var errors: Int = 0
    public var startTime: Date?
    public var endTime: Date?

    public init(
        totalFiles: Int = 0,
        exportedFiles: Int = 0,
        skippedFiles: Int = 0,
        errors: Int = 0,
        startTime: Date? = nil,
        endTime: Date? = nil
    ) {
        self.totalFiles = totalFiles
        self.exportedFiles = exportedFiles
        self.skippedFiles = skippedFiles
        self.errors = errors
        self.startTime = startTime
        self.endTime = endTime
    }

    public var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else {
            return nil
        }
        return end.timeIntervalSince(start)
    }
}

public struct PDFProgress: Sendable {
    public let current: Int
    public let total: Int
    public let fileName: String
    public let stats: PDFStatistics

    public var percentage: Double {
        Double(current) / Double(total) * 100
    }
}

// MARK: - Errors

enum PDFExporterError: Error {
    case unsupportedPlatform
}
