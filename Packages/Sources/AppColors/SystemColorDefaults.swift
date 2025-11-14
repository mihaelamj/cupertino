// SystemColorDefaults.swift
// AppColors
//
// System color defaults for fallback (Apple HIG inspired)

import SwiftUI

/// System color defaults for fallback (Apple HIG inspired)
public enum SystemColorDefaults {
    /// Primary action color (like systemBlue)
    public static let primary = HSVColor(
        hue: 0.58, // Blue hue
        saturation: 0.8,
        value: 0.9,
        alpha: 1.0
    )

    /// Success state color (like systemGreen)
    public static let success = HSVColor(
        hue: 0.33, // Green hue
        saturation: 0.7,
        value: 0.8,
        alpha: 1.0
    )

    /// Secondary brand color (like systemPurple)
    public static let secondary = HSVColor(
        hue: 0.75, // Purple hue
        saturation: 0.6,
        value: 0.85,
        alpha: 1.0
    )

    /// Destructive action color (like systemRed)
    public static let destructive = HSVColor(
        hue: 0.0, // Red hue
        saturation: 0.8,
        value: 0.9,
        alpha: 1.0
    )

    /// Primary text color (like UIColor.label)
    public static let label = HSVColor(
        hue: 0.0,
        saturation: 0.0,
        value: 0.1, // Very dark gray (light mode)
        alpha: 1.0
    )

    /// Secondary text color (like UIColor.secondaryLabel)
    public static let secondaryLabel = HSVColor(
        hue: 0.0,
        saturation: 0.0,
        value: 0.5, // Medium gray
        alpha: 1.0
    )

    /// Text on primary colored backgrounds
    public static let onPrimary = HSVColor(
        hue: 0.0,
        saturation: 0.0,
        value: 1.0, // White
        alpha: 1.0
    )

    /// Primary background (like systemBackground)
    public static let background = HSVColor(
        hue: 0.0,
        saturation: 0.0,
        value: 1.0, // White (light mode)
        alpha: 1.0
    )

    /// Secondary background (like secondarySystemBackground)
    public static let secondaryBackground = HSVColor(
        hue: 0.0,
        saturation: 0.0,
        value: 0.95, // Light gray
        alpha: 1.0
    )
}
