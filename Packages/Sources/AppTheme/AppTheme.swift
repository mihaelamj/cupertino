// AppTheme.swift
// AppTheme
//
// Complete design system combining colors and typography

import AppColors
import AppFont
import SwiftUI

/// Complete application theme combining color palette and typography
public struct AppTheme: Sendable {
    /// Color palette for the theme
    public let colors: AppColors

    /// Initialize with custom color palette
    public init(colors: AppColors) {
        self.colors = colors
    }

    /// Default theme using system colors and fonts
    public static let system = AppTheme(
        colors: .system
    )
}

// MARK: - Environment Key

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.system
}

extension EnvironmentValues {
    /// Access app theme from environment
    public var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

extension View {
    /// Set custom app theme for this view hierarchy
    public func appTheme(_ theme: AppTheme) -> some View {
        environment(\.appTheme, theme)
            .appColors(theme.colors)
    }
}
