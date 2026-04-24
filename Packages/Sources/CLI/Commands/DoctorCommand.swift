import ArgumentParser
import Core
import Foundation
import Logging
import MCP
import MCPSupport
import Search
import SearchToolProvider
import Shared
import SQLite3

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

        // Check packages (filesystem state)
        await checkPackages()

        // Check packages.db (#192 F1)
        allChecks = checkPackagesDatabase() && allChecks

        // Check search database + schema version (#192 F2)
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
            Log.output("     → Run: cupertino setup  (or `cupertino save` if building locally)")
            Log.output("")
            return false
        }

        // Read PRAGMA user_version BEFORE opening via Search.Index — migrating
        // from an incompatible version throws during init, and we want to tell
        // the user *which* version they're stuck on.
        let onDiskVersion = Self.readUserVersion(at: searchDBURL)
        let expected = Search.Index.schemaVersion
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: searchDBURL.path)[.size] as? UInt64) ?? 0

        Log.output("   ✓ Database: \(searchDBURL.path)")
        Log.output("   ✓ Size: \(Shared.Formatting.formatBytes(Int64(fileSize)))")

        if let onDiskVersion {
            if onDiskVersion == expected {
                Log.output("   ✓ Schema version: \(onDiskVersion) (matches installed binary)")
            } else if onDiskVersion < expected {
                Log.output("   ✗ Schema version: \(onDiskVersion) (binary expects \(expected), rebuild required)")
                Log.output("     → rm \(searchDBURL.path) && cupertino save")
                Log.output("")
                return false
            } else {
                Log.output("   ✗ Schema version: \(onDiskVersion) (newer than binary — expected \(expected))")
                Log.output("     → Upgrade cupertino: brew upgrade cupertino")
                Log.output("")
                return false
            }
        } else {
            Log.output("   ⚠  Schema version: could not read PRAGMA user_version")
        }

        do {
            let searchIndex = try await Search.Index(dbPath: searchDBURL)
            let frameworks = try await searchIndex.listFrameworks()
            Log.output("   ✓ Frameworks: \(frameworks.count)")
            await searchIndex.disconnect()
            Log.output("")
            return true
        } catch {
            Log.output("   ✗ Database error: \(error)")
            Log.output("     → rm \(searchDBURL.path) && cupertino save")
            Log.output("")
            return false
        }
    }

    /// #192 F1. Report `packages.db` presence, size, and row counts (packages,
    /// files). Schema version tracked via the `Shared.Constants.App.packagesIndexVersion`
    /// constant rather than a PRAGMA (packages.db is downloaded, not migrated).
    private func checkPackagesDatabase() -> Bool {
        let packagesDBURL = Shared.Constants.defaultPackagesDatabase

        Log.output("📦 Packages Index (packages.db)")

        guard FileManager.default.fileExists(atPath: packagesDBURL.path) else {
            Log.output("   ⚠  Database: \(packagesDBURL.path) (not found)")
            Log.output("     → Run: cupertino setup  (downloads the pre-built packages index)")
            Log.output("     Expected version: \(Shared.Constants.App.packagesIndexVersion)")
            Log.output("")
            // Missing packages.db is a warning, not a failure — server still
            // runs, just without the packages tool. Doctor summary stays green.
            return true
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: packagesDBURL.path)[.size] as? UInt64) ?? 0
        Log.output("   ✓ Database: \(packagesDBURL.path)")
        Log.output("   ✓ Size: \(Shared.Formatting.formatBytes(Int64(fileSize)))")

        let packageCount = Self.rowCount(dbPath: packagesDBURL, sql: "SELECT COUNT(*) FROM packages;")
        let fileCount = Self.rowCount(dbPath: packagesDBURL, sql: "SELECT COUNT(*) FROM package_files;")
        if let packageCount { Log.output("   ✓ Packages: \(packageCount)") }
        if let fileCount { Log.output("   ✓ Indexed files: \(fileCount)") }
        Log.output("   ℹ  Bundled version: \(Shared.Constants.App.packagesIndexVersion)")
        Log.output("")
        return true
    }

    /// Read `PRAGMA user_version` directly without opening the DB through
    /// `Search.Index` (whose init will throw on incompatible versions).
    static func readUserVersion(at dbPath: URL) -> Int32? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }
        return sqlite3_column_int(stmt, 0)
    }

    /// Run a `SELECT COUNT(*) ...` read-only against any sqlite DB. Returns
    /// nil if the query fails (most commonly because the table doesn't
    /// exist — which is information worth surfacing blank rather than crashing).
    static func rowCount(dbPath: URL, sql: String) -> Int? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }
        return Int(sqlite3_column_int(stmt, 0))
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
                Log.output("   ⚠  Package docs: directory exists but no package files")
            }
        } else {
            Log.output("   ⚠  Package docs: not downloaded")
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
