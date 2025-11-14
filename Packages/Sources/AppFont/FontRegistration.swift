import CoreGraphics
import CoreText
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum FontRegistration {
    /// Register custom fonts from the AppFont package
    public static func registerFonts() {
        // Get all resource URLs and filter for .otf files
        guard let resourceURLs = Bundle.module.urls(forResourcesWithExtension: nil, subdirectory: nil) else {
            print("⚠️ No resources found in AppFont bundle")
            return
        }

        let fontURLs = resourceURLs.filter { $0.pathExtension.lowercased() == "otf" }

        guard !fontURLs.isEmpty else {
            print("⚠️ No .otf fonts found in AppFont bundle")
            return
        }

        for url in fontURLs {
            var errorRef: Unmanaged<CFError>?
            let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef)

            if !success {
                print("⚠️ Failed to register font: \(url.lastPathComponent)")
                if let error = errorRef?.takeRetainedValue() {
                    print("   Error: \(error)")
                }
            } else {
                print("✅ Registered font: \(url.lastPathComponent)")
            }
        }
    }
}
