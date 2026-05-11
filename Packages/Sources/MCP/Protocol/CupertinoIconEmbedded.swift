// CupertinoIconEmbedded.swift
//
// 64×64 PNG embedded as a base64 data URI for the MCP 2025-11-25
// `serverInfo.icons` field. Auto-generated from assets/cupertino-icon-64.png.
//
// Regenerate:
//   swift /tmp/make-icon.swift assets/cupertino-icon-64.png
//   B64=$(base64 -i assets/cupertino-icon-64.png | tr -d '\n')
//   # then rewrite the `dataURI` constant below
//
// Keeping the icon inline (rather than loading from assets/) matches the
// Swift-literal embed approach already used for the JSON catalogs (#161) —
// no bundle, no symlink resolution at runtime.

import Foundation

public enum CupertinoIconEmbedded {
    /// Raw base64 of the 64×64 PNG.
    ///
    /// One physical line by design: the base64 payload can't be wrapped
    /// without breaking the literal. This is the only intentional
    /// `line_length` exemption in the package.
    // swiftlint:disable:next line_length
    public static let base64 = "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"

    /// Fully-formed data URI suitable for an `Icon.src` field.
    public static let dataURI = "data:image/png;base64,\(base64)"
}
