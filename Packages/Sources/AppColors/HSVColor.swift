// HSVColor.swift
// AppColors
//
// Internal HSV color representation for color manipulation

import SwiftUI

/// Internal HSV color representation for manipulation
public struct HSVColor: Equatable, Sendable {
    /// Hue (0.0 - 1.0)
    public let hue: Double

    /// Saturation (0.0 - 1.0)
    public let saturation: Double

    /// Value/Brightness (0.0 - 1.0)
    public let value: Double

    /// Alpha/Opacity (0.0 - 1.0)
    public let alpha: Double

    public init(hue: Double, saturation: Double, value: Double, alpha: Double = 1.0) {
        self.hue = hue
        self.saturation = saturation
        self.value = value
        self.alpha = alpha
    }

    /// Convert to SwiftUI Color
    public func toColor() -> Color {
        Color(hue: hue, saturation: saturation, brightness: value, opacity: alpha)
    }

    /// Calculate dark mode variant
    /// Reduces brightness and slightly increases saturation
    public func darkVariant() -> HSVColor {
        HSVColor(
            hue: hue,
            saturation: min(1.0, saturation * 1.1), // Slightly more saturated
            value: max(0.15, value * 0.6), // Darker (60% of original)
            alpha: alpha
        )
    }

    /// Calculate light mode variant
    /// Increases brightness and slightly reduces saturation
    public func lightVariant() -> HSVColor {
        HSVColor(
            hue: hue,
            saturation: max(0.0, saturation * 0.85), // Slightly less saturated
            value: min(1.0, value * 1.3), // Brighter (130% of original)
            alpha: alpha
        )
    }

    /// Adjust brightness by factor
    public func adjustingValue(by factor: Double) -> HSVColor {
        HSVColor(
            hue: hue,
            saturation: saturation,
            value: min(1.0, max(0.0, value * factor)),
            alpha: alpha
        )
    }

    /// Adjust saturation by factor
    public func adjustingSaturation(by factor: Double) -> HSVColor {
        HSVColor(
            hue: hue,
            saturation: min(1.0, max(0.0, saturation * factor)),
            value: value,
            alpha: alpha
        )
    }
}
