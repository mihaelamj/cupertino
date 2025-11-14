// AppColors.swift
// AppColors
//
// Semantic color palette for the application (Apple HIG standard)

import SwiftUI

/// Semantic color palette for the application (Apple HIG standard)
public struct AppColors: Sendable {
    // MARK: - Semantic Colors

    /// Primary brand/action color (like systemBlue)
    public let primary: Color

    /// Success state color (like systemGreen)
    public let success: Color

    /// Secondary brand color (like systemPurple)
    public let secondary: Color

    /// Destructive/error action color (like systemRed)
    public let destructive: Color

    // MARK: - Text Colors

    /// Primary text color (like UIColor.label)
    public let label: Color

    /// Secondary text color (like UIColor.secondaryLabel)
    public let secondaryLabel: Color

    /// Text color for use on primary colored backgrounds
    public let onPrimary: Color

    // MARK: - Background Colors

    /// Primary background color (like systemBackground)
    public let background: Color

    /// Secondary background color (like secondarySystemBackground)
    public let secondaryBackground: Color

    // MARK: - Initialization

    /// Initialize with explicit HSV colors for light mode
    /// Dark mode variants will be calculated automatically
    public init(
        primaryHSV: HSVColor,
        successHSV: HSVColor,
        secondaryHSV: HSVColor,
        destructiveHSV: HSVColor,
        labelHSV: HSVColor,
        secondaryLabelHSV: HSVColor,
        onPrimaryHSV: HSVColor,
        backgroundHSV: HSVColor,
        secondaryBackgroundHSV: HSVColor
    ) {
        primary = Color(lightHSV: primaryHSV)
        success = Color(lightHSV: successHSV)
        secondary = Color(lightHSV: secondaryHSV)
        destructive = Color(lightHSV: destructiveHSV)
        label = Color(lightHSV: labelHSV)
        secondaryLabel = Color(lightHSV: secondaryLabelHSV)
        onPrimary = Color(lightHSV: onPrimaryHSV)
        background = Color(lightHSV: backgroundHSV)
        secondaryBackground = Color(lightHSV: secondaryBackgroundHSV)
    }

    /// Initialize with explicit light and dark Color pairs
    public init(
        primary: (light: Color, dark: Color),
        success: (light: Color, dark: Color),
        secondary: (light: Color, dark: Color),
        destructive: (light: Color, dark: Color),
        label: (light: Color, dark: Color),
        secondaryLabel: (light: Color, dark: Color),
        onPrimary: (light: Color, dark: Color),
        background: (light: Color, dark: Color),
        secondaryBackground: (light: Color, dark: Color)
    ) {
        self.primary = Color(light: primary.light, dark: primary.dark)
        self.success = Color(light: success.light, dark: success.dark)
        self.secondary = Color(light: secondary.light, dark: secondary.dark)
        self.destructive = Color(light: destructive.light, dark: destructive.dark)
        self.label = Color(light: label.light, dark: label.dark)
        self.secondaryLabel = Color(light: secondaryLabel.light, dark: secondaryLabel.dark)
        self.onPrimary = Color(light: onPrimary.light, dark: onPrimary.dark)
        self.background = Color(light: background.light, dark: background.dark)
        self.secondaryBackground = Color(light: secondaryBackground.light, dark: secondaryBackground.dark)
    }

    // MARK: - System Default

    /// Default color palette using system colors
    public static let system = AppColors(
        primaryHSV: SystemColorDefaults.primary,
        successHSV: SystemColorDefaults.success,
        secondaryHSV: SystemColorDefaults.secondary,
        destructiveHSV: SystemColorDefaults.destructive,
        labelHSV: SystemColorDefaults.label,
        secondaryLabelHSV: SystemColorDefaults.secondaryLabel,
        onPrimaryHSV: SystemColorDefaults.onPrimary,
        backgroundHSV: SystemColorDefaults.background,
        secondaryBackgroundHSV: SystemColorDefaults.secondaryBackground
    )
}

// MARK: - Environment Key

private struct AppColorsKey: EnvironmentKey {
    static let defaultValue = AppColors.system
}

extension EnvironmentValues {
    /// Access app colors from environment
    public var appColors: AppColors {
        get { self[AppColorsKey.self] }
        set { self[AppColorsKey.self] = newValue }
    }
}

extension View {
    /// Set custom app colors for this view hierarchy
    public func appColors(_ colors: AppColors) -> some View {
        environment(\.appColors, colors)
    }
}
