import Components
import Foundation
import SharedComponents
import SwiftUI

public struct LanguageSwitcherComponent: Component {
    public struct Data: ComponentData, Codable, Sendable {
        /// Currently selected language code (e.g., "DE", "EN")
        public var selectedLanguageCode: String = "DE"

        /// Language regions to include (if specificLanguageCodes is empty)
        public var languageRegions: LanguageRegion = .all

        /// Specific language codes to include (overrides languageRegions if not empty)
        public var specificLanguageCodes: Set<String> = []

        /// Show search bar
        public var showSearch: Bool = true

        /// Pill size
        public var size: CGFloat = 32

        public init(
            selectedLanguageCode: String = "DE",
            languageRegions: LanguageRegion = .all,
            specificLanguageCodes: Set<String> = [],
            showSearch: Bool = true,
            size: CGFloat = 32
        ) {
            self.selectedLanguageCode = selectedLanguageCode
            self.languageRegions = languageRegions
            self.specificLanguageCodes = specificLanguageCodes
            self.showSearch = showSearch
            self.size = size
        }

        public var availableLanguages: [LanguageOption] {
            if !specificLanguageCodes.isEmpty {
                return LanguageOption.languages(for: specificLanguageCodes)
            }
            return LanguageOption.languages(for: languageRegions)
        }
    }

    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public func make() -> some View {
        LanguageSwitcherContent(data: data)
    }
}

/// Language region option set for filtering available languages
public struct LanguageRegion: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    // Individual regions
    public static let westernEurope = LanguageRegion(rawValue: 1 << 0) // DE, FR, ES, IT, PT, NL
    public static let easternEurope = LanguageRegion(rawValue: 1 << 1) // PL, RO, BG, UA, RU
    public static let nordicEurope = LanguageRegion(rawValue: 1 << 2) // SE, NO, DK, FI
    public static let britishIsles = LanguageRegion(rawValue: 1 << 3) // EN (GB)
    public static let northAmerica = LanguageRegion(rawValue: 1 << 4) // EN (US), FR (CA), ES (MX)
    public static let latinAmerica = LanguageRegion(rawValue: 1 << 5) // ES, PT (BR)
    public static let middleEast = LanguageRegion(rawValue: 1 << 6) // AR, FA, TR, HE
    public static let eastAsia = LanguageRegion(rawValue: 1 << 7) // ZH, JA, KO
    public static let southAsia = LanguageRegion(rawValue: 1 << 8) // HI, BN, UR
    public static let southeastAsia = LanguageRegion(rawValue: 1 << 9) // TH, VI, ID, MS
    public static let africa = LanguageRegion(rawValue: 1 << 10) // SW, AM, ZU

    // Convenient combinations
    public static let europe7: LanguageRegion = [.westernEurope, .britishIsles] // Top 7 European languages
    public static let europeAll: LanguageRegion = [.westernEurope, .easternEurope, .nordicEurope, .britishIsles]
    public static let americas: LanguageRegion = [.northAmerica, .latinAmerica]
    public static let asia: LanguageRegion = [.eastAsia, .southAsia, .southeastAsia]
    public static let all: LanguageRegion = [
        .westernEurope, .easternEurope, .nordicEurope, .britishIsles,
        .northAmerica, .latinAmerica, .middleEast, .eastAsia, .southAsia, .southeastAsia, .africa,
    ]
}

public struct LanguageOption: Hashable, Codable, Identifiable, Sendable {
    public var id: String { code }
    public let code: String
    public let name: String // English name
    public let nativeName: String // Native language name
    public let flagImage: String // Asset name (e.g., "de")
    public let regions: LanguageRegion

    public init(code: String, name: String, nativeName: String, flagImage: String, regions: LanguageRegion) {
        self.code = code
        self.name = name
        self.nativeName = nativeName
        self.flagImage = flagImage
        self.regions = regions
    }

    /// All available languages with their regions
    public static let allLanguages: [LanguageOption] = [
        // Western Europe
        LanguageOption(code: "DE", name: "German", nativeName: "Deutsch", flagImage: "de", regions: .westernEurope),
        LanguageOption(code: "FR", name: "French", nativeName: "Français", flagImage: "fr", regions: .westernEurope),
        LanguageOption(code: "ES", name: "Spanish", nativeName: "Español", flagImage: "es", regions: [.westernEurope, .latinAmerica]),
        LanguageOption(code: "IT", name: "Italian", nativeName: "Italiano", flagImage: "it", regions: .westernEurope),
        LanguageOption(code: "PT", name: "Portuguese", nativeName: "Português", flagImage: "pt", regions: [.westernEurope, .latinAmerica]),
        LanguageOption(code: "NL", name: "Dutch", nativeName: "Nederlands", flagImage: "nl", regions: .westernEurope),

        // British Isles
        LanguageOption(code: "EN", name: "English", nativeName: "English", flagImage: "gb", regions: [.britishIsles, .northAmerica]),

        // Eastern Europe
        LanguageOption(code: "PL", name: "Polish", nativeName: "Polski", flagImage: "pl", regions: .easternEurope),
        LanguageOption(code: "RU", name: "Russian", nativeName: "Русский", flagImage: "ru", regions: .easternEurope),
        LanguageOption(code: "UK", name: "Ukrainian", nativeName: "Українська", flagImage: "ua", regions: .easternEurope),
        LanguageOption(code: "RO", name: "Romanian", nativeName: "Română", flagImage: "ro", regions: .easternEurope),
        LanguageOption(code: "BG", name: "Bulgarian", nativeName: "Български", flagImage: "bg", regions: .easternEurope),
        LanguageOption(code: "HR", name: "Croatian", nativeName: "Hrvatski", flagImage: "hr", regions: .easternEurope),
        LanguageOption(code: "CS", name: "Czech", nativeName: "Čeština", flagImage: "cz", regions: .easternEurope),
        LanguageOption(code: "HU", name: "Hungarian", nativeName: "Magyar", flagImage: "hu", regions: .easternEurope),
        LanguageOption(code: "SK", name: "Slovak", nativeName: "Slovenčina", flagImage: "sk", regions: .easternEurope),

        // Nordic Europe
        LanguageOption(code: "SE", name: "Swedish", nativeName: "Svenska", flagImage: "se", regions: .nordicEurope),
        LanguageOption(code: "NO", name: "Norwegian", nativeName: "Norsk", flagImage: "no", regions: .nordicEurope),
        LanguageOption(code: "DK", name: "Danish", nativeName: "Dansk", flagImage: "dk", regions: .nordicEurope),
        LanguageOption(code: "FI", name: "Finnish", nativeName: "Suomi", flagImage: "fi", regions: .nordicEurope),

        // Middle East
        LanguageOption(code: "AR", name: "Arabic", nativeName: "العربية", flagImage: "sa", regions: .middleEast),
        LanguageOption(code: "FA", name: "Persian", nativeName: "فارسی", flagImage: "ir", regions: .middleEast),
        LanguageOption(code: "TR", name: "Turkish", nativeName: "Türkçe", flagImage: "tr", regions: .middleEast),
        LanguageOption(code: "HE", name: "Hebrew", nativeName: "עברית", flagImage: "il", regions: .middleEast),

        // East Asia
        LanguageOption(code: "ZH", name: "Chinese", nativeName: "中文", flagImage: "cn", regions: .eastAsia),
        LanguageOption(code: "JA", name: "Japanese", nativeName: "日本語", flagImage: "jp", regions: .eastAsia),
        LanguageOption(code: "KO", name: "Korean", nativeName: "한국어", flagImage: "kr", regions: .eastAsia),

        // South Asia
        LanguageOption(code: "HI", name: "Hindi", nativeName: "हिन्दी", flagImage: "in", regions: .southAsia),
        LanguageOption(code: "BN", name: "Bengali", nativeName: "বাংলা", flagImage: "bd", regions: .southAsia),
        LanguageOption(code: "UR", name: "Urdu", nativeName: "اردو", flagImage: "pk", regions: .southAsia),

        // Southeast Asia
        LanguageOption(code: "TH", name: "Thai", nativeName: "ไทย", flagImage: "th", regions: .southeastAsia),
        LanguageOption(code: "VI", name: "Vietnamese", nativeName: "Tiếng Việt", flagImage: "vn", regions: .southeastAsia),
        LanguageOption(code: "ID", name: "Indonesian", nativeName: "Bahasa Indonesia", flagImage: "id", regions: .southeastAsia),
        LanguageOption(code: "MS", name: "Malay", nativeName: "Bahasa Melayu", flagImage: "my", regions: .southeastAsia),

        // Africa
        LanguageOption(code: "SW", name: "Swahili", nativeName: "Kiswahili", flagImage: "tz", regions: .africa),
        LanguageOption(code: "AM", name: "Amharic", nativeName: "አማርኛ", flagImage: "et", regions: .africa),
        LanguageOption(code: "ZU", name: "Zulu", nativeName: "isiZulu", flagImage: "za", regions: .africa),
    ]

    /// Get filtered languages based on regions
    public static func languages(for regions: LanguageRegion) -> [LanguageOption] {
        if regions == .all {
            return allLanguages
        }

        return allLanguages.filter { language in
            language.regions.isDisjoint(with: regions) == false
        }.sorted { $0.name < $1.name }
    }

    /// Get specific languages by ISO language codes
    public static func languages(for codes: Set<String>) -> [LanguageOption] {
        let uppercasedCodes = Set(codes.map { $0.uppercased() })
        return allLanguages.filter { language in
            uppercasedCodes.contains(language.code.uppercased())
        }.sorted { $0.name < $1.name }
    }

    /// Convenience: Get default languages (same as original - top European languages)
    public static var defaultLanguages: [LanguageOption] {
        languages(for: .europe7)
    }
}

struct LanguageSwitcherContent: View {
    @ObserveInjection private var iO
    var data: LanguageSwitcherComponent.Data

    @State private var isExpanded = false
    @State private var searchText = ""
    @State private var selectedLanguage: LanguageOption

    init(data: LanguageSwitcherComponent.Data) {
        self.data = data
        let selected = data.availableLanguages.first { $0.code == data.selectedLanguageCode } ?? data.availableLanguages.first!
        _selectedLanguage = State(initialValue: selected)
    }

    private var filteredLanguages: [LanguageOption] {
        if searchText.isEmpty {
            return data.availableLanguages
        }
        return data.availableLanguages.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.nativeName.localizedCaseInsensitiveContains(searchText) ||
                $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func calculateListHeight() -> CGFloat {
        let itemCount = CGFloat(filteredLanguages.count)
        let rowHeight: CGFloat = 64 // 40px image + 24px padding (12 top + 12 bottom)
        let dividerHeight: CGFloat = 1
        let dividersCount = max(0, itemCount - 1)

        let calculatedHeight = (itemCount * rowHeight) + (dividersCount * dividerHeight)
        let maxHeight: CGFloat = 400

        return min(calculatedHeight, maxHeight)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                // Collapsed pill button
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isExpanded.toggle()
                    }
                }, label: {
                    HStack(spacing: 6) {
                        Text(selectedLanguage.code)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        // Flag image in circle
                        Image(selectedLanguage.flagImage, bundle: .module)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: data.size, height: data.size)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.background)
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isExpanded ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1.5)
                    )
                })
                .buttonStyle(PlainButtonStyle())

                // Expanded language list
                if isExpanded {
                    VStack(spacing: 0) {
                        // Header with close button
                        HStack {
                            Text("Select Language")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Spacer()

                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    isExpanded = false
                                    searchText = ""
                                }
                            }, label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(Circle())
                            })
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                        // Search bar - only show if enabled AND 5+ languages
                        if data.showSearch, data.availableLanguages.count >= 5 {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)

                                TextField("Search", text: $searchText)
                                    .font(.body)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }

                        Divider()

                        // Language list
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredLanguages) { language in
                                    Button(action: {
                                        selectedLanguage = language
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            isExpanded = false
                                            searchText = ""
                                        }
                                    }, label: {
                                        HStack(spacing: 12) {
                                            // Flag image in circle
                                            Image(language.flagImage, bundle: .module)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 40, height: 40)
                                                .clipShape(Circle())
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                                )
                                                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(language.nativeName)
                                                    .font(.body)
                                                    .foregroundColor(.primary)

                                                Text(language.code)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }

                                            Spacer()

                                            if language.code == selectedLanguage.code {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 22))
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            language.code == selectedLanguage.code ?
                                                Color.green.opacity(0.05) : Color.clear
                                        )
                                    })
                                    .buttonStyle(PlainButtonStyle())

                                    if language.id != filteredLanguages.last?.id {
                                        Divider()
                                            .padding(.leading, 64)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: calculateListHeight())
                    }
                    .frame(width: 280)
                    .background(.background)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity)
                    ))
                }
            }
        }
        .enableInjection()
    }
}
