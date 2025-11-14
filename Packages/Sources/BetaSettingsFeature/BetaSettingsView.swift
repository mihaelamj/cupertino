import SharedModels
import SwiftUI

// MARK: - Beta Settings View

public struct BetaSettingsView: View {
    @State private var settings = BetaSettings.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                apiSection
                debugSection
                performanceSection
                resetSection
            }
            .navigationTitle("Beta Settings")
        }
    }

    // MARK: - API Configuration

    @ViewBuilder
    private var apiSection: some View {
        Section {
            Picker("Server Environment", selection: $settings.serverEnvironment) {
                ForEach(ServerEnvironment.allCases) { env in
                    Text(env.displayName).tag(env)
                }
            }

            Toggle("Enable Response Caching", isOn: $settings.enableCaching)

            if settings.enableCaching {
                Picker("Cache Mode", selection: $settings.cacheMode) {
                    ForEach(CacheMode.allCases) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.displayName)
                            Text(mode.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Request Timeout (seconds)")
                    Spacer()
                    Text("\(settings.requestTimeout, specifier: "%.0f")s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $settings.requestTimeout,
                    in: 5...120,
                    step: 5
                )
            }
        } header: {
            Text("API Configuration")
        } footer: {
            Text("Active environment: \(settings.serverEnvironment.displayName)")
                .font(.caption)
        }
    }

    // MARK: - Debugging

    @ViewBuilder
    private var debugSection: some View {
        Section {
            Toggle("Enable Debug Logging", isOn: $settings.enableDebugLogging)

            Toggle("Verbose Mode", isOn: $settings.verboseMode)
        } header: {
            Text("Debugging")
        } footer: {
            if settings.verboseMode {
                Text("⚠️ Verbose mode may impact performance. Requires app restart.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Performance

    @ViewBuilder
    private var performanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Animation Speed")
                    Spacer()
                    Text("\(settings.animationSpeed, specifier: "%.1f")x")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $settings.animationSpeed,
                    in: 0.5...2.0,
                    step: 0.1
                )
            }

            Toggle("Reduce Motion", isOn: $settings.reduceMotion)
        } header: {
            Text("Performance")
        }
    }

    // MARK: - Reset

    @ViewBuilder
    private var resetSection: some View {
        Section {
            Button("Reset to Defaults") {
                settings.resetToDefaults()
            }
            .foregroundStyle(.red)
        }
    }
}

// MARK: - Preview

#Preview {
    BetaSettingsView()
}
