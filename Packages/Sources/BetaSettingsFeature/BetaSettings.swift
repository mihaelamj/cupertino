import SharedModels
import SwiftUI

// MARK: - Cache Mode

/// Cache mode for API responses
/// Note: Changing mode requires app restart to take effect
public enum CacheMode: String, Codable, CaseIterable, Identifiable {
    /// Record new responses while making real API calls
    case record
    /// Only replay existing cached responses (no network calls)
    case replay

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .record:
            return "Record Mode"
        case .replay:
            return "Replay Mode (Demo/Offline)"
        }
    }

    public var description: String {
        switch self {
        case .record:
            return "Makes real API calls and saves responses to cache files"
        case .replay:
            return "Only uses cached responses (works offline, fails if not cached)"
        }
    }
}

// MARK: - Protocol

/// Protocol for beta settings, allowing testability and flexibility
@MainActor
public protocol BetaSettingsProtocol: Observable {
    var serverEnvironment: ServerEnvironment { get set }
    var enableCaching: Bool { get set }
    var cacheMode: CacheMode { get set }
    var requestTimeout: Double { get set }
    var enableDebugLogging: Bool { get set }
    var verboseMode: Bool { get set }
    var animationSpeed: Double { get set }
    var reduceMotion: Bool { get set }
}

// MARK: - Implementation

/// Concrete implementation of beta settings with UserDefaults persistence
/// All settings are automatically persisted when changed via didSet
/// sourcery: settings
@Observable
@MainActor
public final class BetaSettings: BetaSettingsProtocol {
    public static let shared = BetaSettings()

    // MARK: - API Settings

    /// Server environment selection
    /// sourcery: setting, section = "API Configuration", label = "Server Environment"
    public var serverEnvironment: ServerEnvironment = .production {
        didSet {
            UserDefaults.standard.set(serverEnvironment.rawValue, forKey: Keys.serverEnvironment)
        }
    }

    /// Enable response caching for API calls
    /// sourcery: setting, section = "API Configuration", label = "Enable Response Caching"
    public var enableCaching: Bool = false {
        didSet {
            UserDefaults.standard.set(enableCaching, forKey: Keys.enableCaching)
        }
    }

    /// Cache mode for API responses
    /// sourcery: setting, section = "API Configuration", label = "Cache Mode"
    public var cacheMode: CacheMode = .record {
        didSet {
            UserDefaults.standard.set(cacheMode.rawValue, forKey: Keys.cacheMode)
        }
    }

    /// Request timeout in seconds
    /// sourcery: setting, section = "API Configuration", label = "Request Timeout (seconds)", range = "5...120", step = "5"
    public var requestTimeout: Double = 30.0 {
        didSet {
            UserDefaults.standard.set(requestTimeout, forKey: Keys.requestTimeout)
        }
    }

    // MARK: - Debug Settings

    /// Enable debug logging to console
    /// sourcery: setting, section = "Debugging", label = "Enable Debug Logging"
    public var enableDebugLogging: Bool = false {
        didSet {
            UserDefaults.standard.set(enableDebugLogging, forKey: Keys.enableDebugLogging)
        }
    }

    /// Verbose logging mode (requires app restart)
    /// sourcery: setting, section = "Debugging", label = "Verbose Mode", requiresRestart
    public var verboseMode: Bool = false {
        didSet {
            UserDefaults.standard.set(verboseMode, forKey: Keys.verboseMode)
        }
    }

    // MARK: - Performance Settings

    /// Animation speed multiplier
    /// sourcery: setting, section = "Performance", label = "Animation Speed", range = "0.5...2.0", step = "0.1"
    public var animationSpeed: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(animationSpeed, forKey: Keys.animationSpeed)
        }
    }

    /// Reduce motion for accessibility
    /// sourcery: setting, section = "Performance", label = "Reduce Motion"
    public var reduceMotion: Bool = false {
        didSet {
            UserDefaults.standard.set(reduceMotion, forKey: Keys.reduceMotion)
        }
    }

    // MARK: - Initialization

    private init() {
        // Load from UserDefaults, overriding defaults above
        // Note: Setting properties here triggers didSet, which saves back to UserDefaults (harmless)
        if let envString = UserDefaults.standard.string(forKey: Keys.serverEnvironment),
           let env = ServerEnvironment(rawValue: envString) {
            serverEnvironment = env
        }

        enableCaching = UserDefaults.standard.bool(forKey: Keys.enableCaching)

        if let modeString = UserDefaults.standard.string(forKey: Keys.cacheMode),
           let mode = CacheMode(rawValue: modeString) {
            cacheMode = mode
        }

        let timeout = UserDefaults.standard.double(forKey: Keys.requestTimeout)
        if timeout > 0 {
            requestTimeout = timeout
        }

        enableDebugLogging = UserDefaults.standard.bool(forKey: Keys.enableDebugLogging)
        verboseMode = UserDefaults.standard.bool(forKey: Keys.verboseMode)

        let speed = UserDefaults.standard.double(forKey: Keys.animationSpeed)
        if speed > 0 {
            animationSpeed = speed
        }

        reduceMotion = UserDefaults.standard.bool(forKey: Keys.reduceMotion)
    }

    // MARK: - Reset

    /// Reset all settings to defaults
    public func resetToDefaults() {
        serverEnvironment = .production
        enableCaching = false
        cacheMode = .record
        requestTimeout = 30.0
        enableDebugLogging = false
        verboseMode = false
        animationSpeed = 1.0
        reduceMotion = false
    }

    // MARK: - Keys

    private enum Keys {
        static let serverEnvironment = "betaSettings.serverEnvironment"
        static let enableCaching = "betaSettings.enableCaching"
        static let cacheMode = "betaSettings.cacheMode"
        static let requestTimeout = "betaSettings.requestTimeout"
        static let enableDebugLogging = "betaSettings.enableDebugLogging"
        static let verboseMode = "betaSettings.verboseMode"
        static let animationSpeed = "betaSettings.animationSpeed"
        static let reduceMotion = "betaSettings.reduceMotion"
    }
}

// MARK: - Mock for Testing

/// Mock implementation for testing
@Observable
@MainActor
public final class MockBetaSettings: BetaSettingsProtocol {
    public var serverEnvironment: ServerEnvironment = .production
    public var enableCaching: Bool = false
    public var cacheMode: CacheMode = .record
    public var requestTimeout: Double = 30.0
    public var enableDebugLogging: Bool = false
    public var verboseMode: Bool = false
    public var animationSpeed: Double = 1.0
    public var reduceMotion: Bool = false

    public init() {}
}
