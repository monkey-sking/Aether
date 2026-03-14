import Foundation

enum AppLanguageMode: String, Identifiable, CaseIterable {
    case system = "system"
    case zhHans = "zh-Hans"
    case en = "en"

    static let allCases: [AppLanguageMode] = [
        .zhHans,
        .en
    ]

    var id: String { rawValue }

    var localizedTitleKey: String {
        switch self {
        case .system:
            return "language.system"
        case .zhHans:
            return "language.zh_CN"
        case .en:
            return "language.en_US"
        }
    }

    var appleLanguageIdentifier: String {
        switch self {
        case .system:
            return ""
        case .zhHans:
            return "zh-Hans"
        case .en:
            return "en"
        }
    }
}

enum AppLocalization {
    static let appLanguageKey = "appLanguageModeV1"

    private static func preferredSupportedMode(for localeIdentifier: String) -> AppLanguageMode {
        localeIdentifier.hasPrefix("zh") ? .zhHans : .en
    }

    static func storedAppLanguage() -> AppLanguageMode {
        guard let raw = UserDefaults.standard.string(forKey: appLanguageKey),
              let mode = AppLanguageMode(rawValue: raw) else {
            return preferredSupportedMode(for: Locale.current.identifier)
        }

        if mode == .system {
            return preferredSupportedMode(for: Locale.current.identifier)
        }
        return mode
    }

    static func setPreferredLanguage(_ mode: AppLanguageMode) {
        let defaults = UserDefaults.standard
        if mode == .system {
            defaults.removeObject(forKey: appLanguageKey)
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set(mode.rawValue, forKey: appLanguageKey)
            defaults.set([mode.appleLanguageIdentifier], forKey: "AppleLanguages")
        }
    }

    static var resolvedLocaleIdentifier: String {
        let mode = storedAppLanguage()
        switch mode {
        case .system:
            return Locale.current.identifier
        case .zhHans:
            return "zh-Hans"
        case .en:
            return "en"
        }
    }

    static var isChinese: Bool {
        resolvedLocaleIdentifier.hasPrefix("zh")
    }

    static func bundle(for localeIdentifier: String) -> Bundle {
        let language = localeIdentifier.hasPrefix("zh") ? "zh-Hans" : "en"
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return Bundle.main
    }

    static func localizedString(_ key: String, localeIdentifier: String? = nil, table: String? = nil) -> String {
        let resolved = localeIdentifier ?? resolvedLocaleIdentifier
        return bundle(for: resolved).localizedString(forKey: key, value: nil, table: table)
    }
}
