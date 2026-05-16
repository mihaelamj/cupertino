@testable import CoreJSONParser
import CoreProtocols
import Foundation
import SharedConstants
import Testing

/// Regression suite for [#274](https://github.com/mihaelamj/cupertino/issues/274).
///
/// Pre-fix, `AppleJSONToMarkdown.toStructuredPage` walked the
/// `relationshipsSections` and assigned three of the four common
/// section titles to dedicated fields (`Conforms To` → `conformsTo`,
/// `Inherited By` → `inheritedBy`, `Conforming Types` →
/// `conformingTypes`). The fourth, `Inherits From`, fell through to a
/// default `default:` branch that appended the section as a freeform
/// "Section" block alongside the page's body — its data still in the
/// indexed content, but unreachable from any queryable field.
///
/// For UIKit / AppKit / Foundation class chains the missing axis is
/// the most useful one: `UIButton.inheritsFrom == [UIControl]`
/// → `UIControl.inheritsFrom == [UIView]` → ... → `NSObject`. This
/// PR captures the field at the JSON-extraction layer so the
/// downstream indexer can persist a queryable edge table (#274
/// schema work) without re-walking the JSON.
@Suite("#274 AppleJSONToMarkdown.toStructuredPage captures inheritsFrom")
struct Issue274InheritsFromExtractionTests {
    /// Synthetic Apple DocC JSON shaped like a UIButton page.
    /// Mirrors the live JSON enough that the relationships walk
    /// fires: `metadata` with title + role, `relationshipsSections`
    /// with two entries (`Inherits From` listing UIControl,
    /// `Inherited By` listing nothing for UIButton in practice), and
    /// a `references` block resolving the doc:// identifier to a
    /// title + URL.
    private static let uiButtonJSON: String = """
    {
        "schemaVersion": {"major": 0, "minor": 3, "patch": 0},
        "identifier": {
            "url": "doc://com.apple.documentation/documentation/uikit/uibutton",
            "interfaceLanguage": "swift"
        },
        "metadata": {
            "title": "UIButton",
            "role": "symbol",
            "roleHeading": "Class",
            "modules": [{"name": "UIKit"}]
        },
        "abstract": [{"type": "text", "text": "A control that responds to taps."}],
        "primaryContentSections": [],
        "topicSections": [],
        "seeAlsoSections": [],
        "relationshipsSections": [
            {
                "title": "Inherits From",
                "identifiers": ["doc://com.apple.documentation/documentation/uikit/uicontrol"],
                "kind": "relationships",
                "type": "inheritsFrom"
            }
        ],
        "references": {
            "doc://com.apple.documentation/documentation/uikit/uicontrol": {
                "title": "UIControl",
                "url": "/documentation/uikit/uicontrol",
                "type": "topic",
                "kind": "symbol"
            }
        },
        "interfaceLanguage": "swift"
    }
    """

    private static let dataStruct: String = """
    {
        "schemaVersion": {"major": 0, "minor": 3, "patch": 0},
        "identifier": {
            "url": "doc://com.apple.documentation/documentation/foundation/data",
            "interfaceLanguage": "swift"
        },
        "metadata": {
            "title": "Data",
            "role": "symbol",
            "roleHeading": "Structure",
            "modules": [{"name": "Foundation"}]
        },
        "abstract": [],
        "primaryContentSections": [],
        "topicSections": [],
        "seeAlsoSections": [],
        "relationshipsSections": [],
        "references": {},
        "interfaceLanguage": "swift"
    }
    """

    @Test("UIButton-shaped page lifts `Inherits From` titles into `inheritsFrom`")
    func uiButtonExposesInheritsFrom() throws {
        let data = try #require(Self.uiButtonJSON.data(using: .utf8))
        let url = try #require(URL(string: "https://developer.apple.com/documentation/uikit/uibutton"))
        let page = try #require(Core.JSONParser.AppleJSONToMarkdown.toStructuredPage(data, url: url))

        try #require(page.inheritsFrom != nil, "page must expose inheritsFrom for a class with Inherits From")
        #expect(page.inheritsFrom == ["UIControl"])
    }

    @Test("Page with no inheritsFrom section keeps `inheritsFrom` nil (e.g. Foundation.Data, a struct)")
    func dataStructHasNoInheritsFrom() throws {
        let data = try #require(Self.dataStruct.data(using: .utf8))
        let url = try #require(URL(string: "https://developer.apple.com/documentation/foundation/data"))
        let page = try #require(Core.JSONParser.AppleJSONToMarkdown.toStructuredPage(data, url: url))

        #expect(
            page.inheritsFrom == nil,
            "non-class pages should not synthesise an empty inheritsFrom; got \(String(describing: page.inheritsFrom))"
        )
    }

    @Test("`Inherits From` does NOT leak into the default-section bucket post-fix")
    func inheritsFromNotInDefaultSectionBucket() throws {
        let data = try #require(Self.uiButtonJSON.data(using: .utf8))
        let url = try #require(URL(string: "https://developer.apple.com/documentation/uikit/uibutton"))
        let page = try #require(Core.JSONParser.AppleJSONToMarkdown.toStructuredPage(data, url: url))

        let inheritsFromBucketTitles = page.sections.map(\.title)
        #expect(
            !inheritsFromBucketTitles.contains("Inherits From"),
            "`Inherits From` should be lifted into the dedicated field, not the default sections bucket: \(inheritsFromBucketTitles)"
        )
    }

    @Test("`Inherited By` still routes to its dedicated field (no regression)")
    func inheritedByStillExtracted() throws {
        // Same shape but with an Inherited By section.
        let json = """
        {
            "schemaVersion": {"major": 0, "minor": 3, "patch": 0},
            "identifier": {
                "url": "doc://com.apple.documentation/documentation/uikit/uicontrol",
                "interfaceLanguage": "swift"
            },
            "metadata": {
                "title": "UIControl",
                "role": "symbol",
                "roleHeading": "Class",
                "modules": [{"name": "UIKit"}]
            },
            "abstract": [],
            "primaryContentSections": [],
            "topicSections": [],
            "seeAlsoSections": [],
            "relationshipsSections": [
                {
                    "title": "Inherited By",
                    "identifiers": [
                        "doc://com.apple.documentation/documentation/uikit/uibutton",
                        "doc://com.apple.documentation/documentation/uikit/uiswitch"
                    ],
                    "kind": "relationships",
                    "type": "inheritedBy"
                }
            ],
            "references": {
                "doc://com.apple.documentation/documentation/uikit/uibutton": {
                    "title": "UIButton", "url": "/documentation/uikit/uibutton",
                    "type": "topic", "kind": "symbol"
                },
                "doc://com.apple.documentation/documentation/uikit/uiswitch": {
                    "title": "UISwitch", "url": "/documentation/uikit/uiswitch",
                    "type": "topic", "kind": "symbol"
                }
            },
            "interfaceLanguage": "swift"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let url = try #require(URL(string: "https://developer.apple.com/documentation/uikit/uicontrol"))
        let page = try #require(Core.JSONParser.AppleJSONToMarkdown.toStructuredPage(data, url: url))

        try #require(page.inheritedBy != nil)
        #expect(Set(page.inheritedBy ?? []) == Set(["UIButton", "UISwitch"]))
        // And `inheritsFrom` stays nil because there's no `Inherits From` section.
        #expect(page.inheritsFrom == nil)
    }

    // MARK: - Model fidelity

    @Test("Round-trip Codable preserves the new inheritsFrom field")
    func codableRoundtripPreservesInheritsFrom() throws {
        let page = try Shared.Models.StructuredDocumentationPage(
            url: #require(URL(string: "https://developer.apple.com/documentation/uikit/uibutton")),
            title: "UIButton",
            kind: .class,
            source: .appleJSON,
            inheritsFrom: ["UIControl", "UIView"]
        )
        let encoded = try JSONEncoder().encode(page)
        let decoded = try JSONDecoder().decode(Shared.Models.StructuredDocumentationPage.self, from: encoded)
        #expect(decoded.inheritsFrom == ["UIControl", "UIView"])
    }

    // MARK: - URI resolution (#274 follow-up)

    @Test("UIButton page populates `inheritsFromURIs` parallel to titles via doc.references lookup")
    func uiButtonResolvesInheritsFromURIs() throws {
        let data = try #require(Self.uiButtonJSON.data(using: .utf8))
        let url = try #require(URL(string: "https://developer.apple.com/documentation/uikit/uibutton"))
        let page = try #require(Core.JSONParser.AppleJSONToMarkdown.toStructuredPage(data, url: url))

        try #require(page.inheritsFromURIs != nil, "page must expose inheritsFromURIs")
        // Apple-docs canonical form: lowercase framework + path.
        #expect(page.inheritsFromURIs == ["apple-docs://uikit/uicontrol"])
        // Parallel to the title array — same order, same length.
        #expect(page.inheritsFromURIs?.count == page.inheritsFrom?.count)
    }

    @Test("Page with no `Inherits From` section keeps `inheritsFromURIs` nil")
    func noInheritsFromMeansNilURIs() throws {
        let data = try #require(Self.dataStruct.data(using: .utf8))
        let url = try #require(URL(string: "https://developer.apple.com/documentation/foundation/data"))
        let page = try #require(Core.JSONParser.AppleJSONToMarkdown.toStructuredPage(data, url: url))

        #expect(page.inheritsFromURIs == nil)
    }

    @Test("Inherited By URIs are resolved through the same path")
    func inheritedByResolvesURIs() throws {
        let json = """
        {
            "schemaVersion": {"major": 0, "minor": 3, "patch": 0},
            "identifier": {
                "url": "doc://com.apple.documentation/documentation/uikit/uicontrol",
                "interfaceLanguage": "swift"
            },
            "metadata": {
                "title": "UIControl",
                "role": "symbol",
                "roleHeading": "Class",
                "modules": [{"name": "UIKit"}]
            },
            "abstract": [],
            "primaryContentSections": [],
            "topicSections": [],
            "seeAlsoSections": [],
            "relationshipsSections": [
                {
                    "title": "Inherited By",
                    "identifiers": [
                        "doc://com.apple.documentation/documentation/uikit/uibutton",
                        "doc://com.apple.documentation/documentation/uikit/uiswitch"
                    ],
                    "kind": "relationships",
                    "type": "inheritedBy"
                }
            ],
            "references": {
                "doc://com.apple.documentation/documentation/uikit/uibutton": {
                    "title": "UIButton", "url": "/documentation/uikit/uibutton",
                    "type": "topic", "kind": "symbol"
                },
                "doc://com.apple.documentation/documentation/uikit/uiswitch": {
                    "title": "UISwitch", "url": "/documentation/uikit/uiswitch",
                    "type": "topic", "kind": "symbol"
                }
            },
            "interfaceLanguage": "swift"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let url = try #require(URL(string: "https://developer.apple.com/documentation/uikit/uicontrol"))
        let page = try #require(Core.JSONParser.AppleJSONToMarkdown.toStructuredPage(data, url: url))

        try #require(page.inheritedByURIs != nil)
        #expect(Set(page.inheritedByURIs ?? []) == Set([
            "apple-docs://uikit/uibutton",
            "apple-docs://uikit/uiswitch",
        ]))
    }
}
