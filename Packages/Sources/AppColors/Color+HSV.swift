// Color+HSV.swift
// AppColors
//
// HSV conversion utilities for SwiftUI Color

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// Initialize from HSV color
    public init(hsv: HSVColor) {
        self = hsv.toColor()
    }

    /// Convert Color to HSV representation
    public func toHSV() -> HSVColor {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return HSVColor(
            hue: Double(hue),
            saturation: Double(saturation),
            value: Double(brightness),
            alpha: Double(alpha)
        )
        #elseif canImport(AppKit)
        let nsColor = NSColor(self)
        let converted = nsColor.usingColorSpace(.deviceRGB) ?? nsColor

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return HSVColor(
            hue: Double(hue),
            saturation: Double(saturation),
            value: Double(brightness),
            alpha: Double(alpha)
        )
        #else
        // Fallback for other platforms
        return HSVColor(hue: 0, saturation: 0, value: 0.5, alpha: 1.0)
        #endif
    }
}
