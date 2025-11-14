#if canImport(ApiClient)
import ApiClient
#endif
import BetaSettingsFeature
import SharedModels
import SwiftUI

#if canImport(ApiClient)
/// Demo app view showing BetaSettings + ApiClient integration
/// Use this as a reference or in a demo app target
///
/// Features:
/// - Settings automatically applied to ApiClient
/// - Live display of current settings
/// - Cache mode support (Record/Replay)
/// - Debug information
public struct DemoAppView: View {
    @State private var selectedTab: Tab = .home
    @State private var settings = BetaSettings.shared

    public var body: some View {
        TabView(selection: $selectedTab) {
            DemoHomeTabView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(Tab.home)

            BetaSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)

            DebugTabView()
                .tabItem {
                    Label("Debug", systemImage: "ant.fill")
                }
                .tag(Tab.debug)
        }
        .task {
            // Apply settings when app starts
            await applySettingsToApiClient()
        }
        .onChange(of: settings.serverEnvironment) { _, _ in
            Task { await applySettingsToApiClient() }
        }
        .onChange(of: settings.enableCaching) { _, _ in
            Task { await applySettingsToApiClient() }
        }
        .onChange(of: settings.cacheMode) { _, _ in
            Task { await applySettingsToApiClient() }
        }
        .onChange(of: settings.enableDebugLogging) { _, _ in
            Task { await applySettingsToApiClient() }
        }
    }

    public init() {}

    private func applySettingsToApiClient() async {
        do {
            try await settings.applyToApiClient()
        } catch {
            print("❌ Failed to apply settings to ApiClient: \(error)")
        }
    }
}

// MARK: - Home Tab

private struct DemoHomeTabView: View {
    @State private var settings = BetaSettings.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Demo App")
                        .font(.title)
                        .fontWeight(.bold)

                    Divider()

                    // Current Settings Display
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Current Settings")
                            .font(.headline)

                        LabeledContent("Environment", value: settings.serverEnvironment.displayName)
                        LabeledContent("Caching", value: settings.enableCaching ? "Enabled" : "Disabled")

                        if settings.enableCaching {
                            LabeledContent("Cache Mode", value: settings.cacheMode.displayName)
                        }

                        LabeledContent("Timeout", value: "\(Int(settings.requestTimeout))s")
                        LabeledContent("Debug Logging", value: settings.enableDebugLogging ? "On" : "Off")
                        LabeledContent("Animation Speed", value: String(format: "%.1fx", settings.animationSpeed))
                    }
                    .font(.subheadline)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)

                    // Cache Info (if enabled)
                    if settings.enableCaching {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Cache Information")
                                .font(.headline)

                            if let cachePath = try? BetaSettings.getCachePath() {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Location:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(cachePath)
                                        .font(.caption2)
                                        .monospaced()
                                }
                            }

                            HStack {
                                Image(systemName: settings.cacheMode == .record ? "record.circle" : "play.circle")
                                    .foregroundStyle(settings.cacheMode == .record ? .red : .green)
                                Text(settings.cacheMode == .record
                                    ? "Recording API responses to cache"
                                    : "Replaying from cache (offline mode)")
                                    .font(.caption)
                            }
                        }
                        .font(.subheadline)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }

                    // Demo Instructions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Demo Mode Instructions")
                            .font(.headline)

                        Text("1. Enable Caching in Settings")
                        Text("2. Set Cache Mode to Record")
                        Text("3. Restart the app")
                        Text("4. Use the app normally")
                        Text("5. API responses are saved to cache")
                        Text("6. Switch to Replay mode for offline demo")
                    }
                    .font(.caption)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Demo Home")
        }
    }
}

// MARK: - Debug Tab

private struct DebugTabView: View {
    @State private var apiClientStatus: String = "Checking..."
    @State private var settings = BetaSettings.shared

    var body: some View {
        NavigationStack {
            List {
                Section("ApiClient Status") {
                    Text(apiClientStatus)
                        .font(.caption)
                        .monospaced()

                    Button("Check ApiClient") {
                        Task {
                            await checkApiClient()
                        }
                    }

                    if let cachePath = try? BetaSettings.getCachePath() {
                        Button("Reveal Cache in Finder") {
                            revealInFinder(path: cachePath)
                        }
                    }
                }

                Section("Settings Values") {
                    LabeledContent("Server Environment", value: settings.serverEnvironment.rawValue)
                    LabeledContent("Enable Caching", value: settings.enableCaching ? "true" : "false")
                    LabeledContent("Cache Mode", value: settings.cacheMode.rawValue)
                    LabeledContent("Request Timeout", value: "\(settings.requestTimeout)")
                    LabeledContent("Debug Logging", value: settings.enableDebugLogging ? "true" : "false")
                    LabeledContent("Verbose Mode", value: settings.verboseMode ? "true" : "false")
                    LabeledContent("Animation Speed", value: "\(settings.animationSpeed)")
                    LabeledContent("Reduce Motion", value: settings.reduceMotion ? "true" : "false")
                }

                Section("Actions") {
                    Button("Reset Settings to Defaults") {
                        settings.resetToDefaults()
                    }
                    .foregroundStyle(.red)

                    Button("Apply Settings to ApiClient") {
                        Task {
                            do {
                                try await settings.applyToApiClient()
                                apiClientStatus = "✅ Settings applied successfully"
                            } catch {
                                apiClientStatus = "❌ Error: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
            .navigationTitle("Debug")
        }
        .task {
            await checkApiClient()
        }
    }

    private func checkApiClient() async {
        guard let client = ApiClient.shared else {
            apiClientStatus = "❌ ApiClient.shared is nil\nCall ApiClient.initializeShared() first"
            return
        }

        let env = await client.environment
        let cachingEnabled = await client.isCachingEnabled()

        apiClientStatus = """
        ✅ ApiClient initialized
        Environment: \(env.displayName)
        Caching: \(cachingEnabled ? "Enabled" : "Disabled")
        """
    }

    private func revealInFinder(path: String) {
        #if os(macOS)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        #endif
    }
}

// MARK: - Tab Enum

private enum Tab {
    case home
    case settings
    case debug
}
#endif
