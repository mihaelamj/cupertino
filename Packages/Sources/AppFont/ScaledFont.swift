import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum AppFont {
    static let regular = "IBMPlexSans-Regular"
    static let light = "IBMPlexSans-Light"
    static let medium = "IBMPlexSans-Medium"
    static let semibold = "IBMPlexSans-SemiBold"
    static let bold = "IBMPlexSans-Bold"

    // Default font name (regular)
    static let fontName = regular

    static func scaled(_ textStyle: Font.TextStyle, weight: FontWeight = .regular) -> Font {
        let name = weight.fontName
        switch textStyle {
        case .largeTitle: return .custom(name, size: 34, relativeTo: .largeTitle)
        case .title: return .custom(name, size: 28, relativeTo: .title)
        case .title2: return .custom(name, size: 22, relativeTo: .title2)
        case .title3: return .custom(name, size: 20, relativeTo: .title3)
        case .headline: return .custom(name, size: 17, relativeTo: .headline)
        case .subheadline: return .custom(name, size: 15, relativeTo: .subheadline)
        case .body: return .custom(name, size: 17, relativeTo: .body)
        case .callout: return .custom(name, size: 16, relativeTo: .callout)
        case .footnote: return .custom(name, size: 13, relativeTo: .footnote)
        case .caption: return .custom(name, size: 12, relativeTo: .caption)
        case .caption2: return .custom(name, size: 11, relativeTo: .caption2)
        default: return .custom(name, size: 17, relativeTo: .body)
        }
    }

    public enum FontWeight {
        case light
        case regular
        case medium
        case semibold
        case bold

        public var fontName: String {
            switch self {
            case .light: return AppFont.light
            case .regular: return AppFont.regular
            case .medium: return AppFont.medium
            case .semibold: return AppFont.semibold
            case .bold: return AppFont.bold
            }
        }
    }
}

public extension View {
    /// Applies your custom font if installed; otherwise falls back to the system font for the given text style.
    func bdrFont(_ textStyle: Font.TextStyle, weight: AppFont.FontWeight = .regular) -> some View {
        let selectedFont = AppFont.isInstalled ? AppFont.scaled(textStyle, weight: weight) : Font.system(textStyle)
        return font(selectedFont)
    }
}

private extension AppFont {
    static var isInstalled: Bool {
        #if canImport(UIKit)
        return UIFont(name: fontName, size: 17) != nil
        #elseif canImport(AppKit)
        return NSFont(name: fontName, size: 17) != nil
        #else
        return false
        #endif
    }
}
