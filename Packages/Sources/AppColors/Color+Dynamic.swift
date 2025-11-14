// Color+Dynamic.swift
// AppColors
//
// Dynamic color support for light and dark mode

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// Creates dynamic color that adapts to appearance
    public init(light: Color, dark: Color) {
        #if os(iOS)
        self = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif os(macOS)
        self = Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #else
        self = light
        #endif
    }

    /// Creates dynamic color from HSV, automatically calculating dark variant
    public init(lightHSV: HSVColor) {
        let lightColor = lightHSV.toColor()
        let darkColor = lightHSV.darkVariant().toColor()
        self.init(light: lightColor, dark: darkColor)
    }

    /// Creates dynamic color from HSV, automatically calculating light variant
    public init(darkHSV: HSVColor) {
        let darkColor = darkHSV.toColor()
        let lightColor = darkHSV.lightVariant().toColor()
        self.init(light: lightColor, dark: darkColor)
    }
}
