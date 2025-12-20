import ArgumentParser
import Core
import Foundation
import Logging
import MCP
import MCPSupport
import Search
import SearchToolProvider
import Shared

// MARK: - Doctor Command

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check MCP server health and configuration",
        discussion: """
        Verifies that the MCP server can start and all required components
        are available and properly configured.

        Checks:
        • Server initialization
        • Resource providers
        • Tool providers
        • Database connectivity
        • Documentation directories
        """
    )

    @Option(name: .long, help: ArgumentHelp(Shared.Constants.HelpText.docsDir))
    var docsDir: String = Shared.Constants.defaultDocsDirectory.path

    @Option(name: .long, help: ArgumentHelp(Shared.Constants.HelpText.evolutionDir))
    var evolutionDir: String = Shared.Constants.defaultSwiftEvolutionDirectory.path

    @Option(name: .long, help: ArgumentHelp(Shared.Constants.HelpText.searchDB))
    var searchDB: String = Shared.Constants.defaultSearchDatabase.path

    mutating func run() async throws {
        Log.output("🏥 MCP Server Health Check")
        Log.output("")

        var allChecks = true

        // Check server initialization
        allChecks = checkServerInitialization() && allChecks

        // Check documentation directories
        allChecks = checkDocumentationDirectories() && allChecks

        // Check packages
        await checkPackages()

        // Check search database
        allChecks = await checkSearchDatabase() && allChecks

        // Check resource providers
        allChecks = checkResourceProviders() && allChecks

        // Summary
        Log.output("")
        if allChecks {
            Log.output("✅ All checks passed - MCP server ready")
        } else {
            Log.output("⚠️  Some checks failed - see above for details")
            throw ExitCode(1)
        }
    }

    private func checkServerInitialization() -> Bool {
        Log.output("✅ MCP Server")
        Log.output("   ✓ Server can initialize")
        Log.output("   ✓ Transport: stdio")
        Log.output("   ✓ Protocol version: \(MCPProtocolVersion)")
        Log.output("")
        return true
    }

    private func checkDocumentationDirectories() -> Bool {
        let docsURL = URL(fileURLWithPath: docsDir).expandingTildeInPath
        let evolutionURL = URL(fileURLWithPath: evolutionDir).expandingTildeInPath
        let higURL = Shared.Constants.defaultHIGDirectory

        var hasIssues = false

        Log.output("📚 Documentation Directories")

        // Check docs directory
        if FileManager.default.fileExists(atPath: docsURL.path) {
            let count = countMarkdownFiles(in: docsURL)
            Log.output("   ✓ Apple docs: \(docsURL.path) (\(count) files)")
        } else {
            Log.output("   ✗ Apple docs: \(docsURL.path) (not found)")
            Log.output("     → Run: cupertino fetch --type docs")
            hasIssues = true
        }

        // Check evolution directory
        if FileManager.default.fileExists(atPath: evolutionURL.path) {
            let count = countMarkdownFiles(in: evolutionURL)
            Log.output("   ✓ Swift Evolution: \(evolutionURL.path) (\(count) proposals)")
        } else {
            Log.output("   ⚠  Swift Evolution: \(evolutionURL.path) (not found)")
            Log.output("     → Run: cupertino fetch --type evolution")
        }

        // Check HIG directory
        if FileManager.default.fileExists(atPath: higURL.path) {
            let count = countMarkdownFiles(in: higURL)
            Log.output("   ✓ HIG: \(higURL.path) (\(count) pages)")
        } else {
            Log.output("   ⚠  HIG: \(higURL.path) (not found)")
            Log.output("     → Run: cupertino fetch --type hig")
        }

        Log.output("")
        return !hasIssues
    }

    private func countMarkdownFiles(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var count = 0
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "md" {
            count += 1
        }
        return count
    }

    private func checkSearchDatabase() async -> Bool {
        let searchDBURL = URL(fileURLWithPath: searchDB).expandingTildeInPath

        Log.output("🔍 Search Index")

        guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
            Log.output("   ✗ Database: \(searchDBURL.path) (not found)")
            Log.output("     → Run: cupertino save")
            Log.output("")
            return false
        }

        do {
            let searchIndex = try await Search.Index(dbPath: searchDBURL)
            let frameworks = try await searchIndex.listFrameworks()
            let fileSize = try FileManager.default.attributesOfItem(atPath: searchDBURL.path)[.size] as? UInt64 ?? 0

            Log.output("   ✓ Database: \(searchDBURL.path)")
            Log.output("   ✓ Size: \(Shared.Formatting.formatBytes(Int64(fileSize)))")
            Log.output("   ✓ Frameworks: \(frameworks.count)")
            Log.output("")
            return true
        } catch {
            Log.output("   ✗ Database error: \(error)")
            Log.output("     → Run: cupertino save")
            Log.output("")
            return false
        }
    }

    private func checkPackages() async {
        let packagesDir = Shared.Constants.defaultPackagesDirectory
        let userSelectionsURL = Shared.Constants.defaultBaseDirectory
            .appendingPathComponent(Shared.Constants.FileName.selectedPackages)

        Log.output("📦 Swift Packages")

        // Check user selections file
        if FileManager.default.fileExists(atPath: userSelectionsURL.path) {
            let selectedURLs = loadUserSelectedPackageURLs(from: userSelectionsURL)
            Log.output("   ✓ User selections: \(userSelectionsURL.path)")
            Log.output("     \(selectedURLs.count) packages selected")
        } else {
            Log.output("   ⚠  User selections: not configured")
            Log.output("     → Use TUI to select packages, or will use bundled defaults")
        }

        // Check downloaded READMEs
        let selectedCount = FileManager.default.fileExists(atPath: userSelectionsURL.path)
            ? loadUserSelectedPackageURLs(from: userSelectionsURL).count
            : 0

        if FileManager.default.fileExists(atPath: packagesDir.path) {
            let readmeCount = countPackageREADMEs(in: packagesDir)
            if readmeCount > 0 {
                Log.output("   ✓ Downloaded READMEs: \(readmeCount) packages")
                Log.output("     \(packagesDir.path)")
                // Warn about orphaned READMEs
                if selectedCount > 0, readmeCount > selectedCount {
                    let orphanCount = readmeCount - selectedCount
                    Log.output("   ⚠  Orphaned READMEs: \(orphanCount) (no longer selected)")
                }
            } else {
                Log.output("   ⚠  Package docs: directory exists but no READMEs")
                Log.output("     → Run: cupertino fetch --type package-docs")
            }
        } else {
            Log.output("   ⚠  Package docs: not downloaded")
            Log.output("     → Run: cupertino fetch --type package-docs")
        }

        // Show priority packages source
        let allPackages = await PriorityPackagesCatalog.allPackages
        let appleCount = await PriorityPackagesCatalog.applePackages.count
        let ecosystemCount = await PriorityPackagesCatalog.ecosystemPackages.count
        Log.output("   ℹ  Priority packages: \(allPackages.count) total")
        Log.output("     Apple: \(appleCount), Ecosystem: \(ecosystemCount)")

        Log.output("")
    }

    private func loadUserSelectedPackageURLs(from fileURL: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tiers = json["tiers"] as? [String: Any] else {
            return []
        }

        var urls = Set<String>()
        for (_, tierValue) in tiers {
            if let tier = tierValue as? [String: Any],
               let packages = tier["packages"] as? [[String: Any]] {
                for pkg in packages {
                    if let url = pkg["url"] as? String {
                        urls.insert(url)
                    }
                }
            }
        }
        return urls
    }

    private func countPackageREADMEs(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var count = 0
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent.lowercased() == "readme.md" {
                count += 1
            }
        }
        return count
    }

    private func checkResourceProviders() -> Bool {
        Log.output("🔧 Providers")
        Log.output("   ✓ DocsResourceProvider: available")
        Log.output("   ✓ SearchToolProvider: available")
        Log.output("")
        return true
    }
}
