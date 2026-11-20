import Carbon
import Foundation

/// One selectable keyboard input source (layout or input-method mode).
struct InputSource {
    let id: String
    let name: String
    let flag: String
    let ref: TISInputSource

    func select() { TISSelectInputSource(ref) }
}

enum InputSources {
    private static let ignoredIDFragments = [
        "PressAndHold", "CharacterPalette", "EmojiFunctionRow", "Dictation", "KeyboardViewer",
    ]

    /// Enabled, selectable keyboard sources in the same order the system switcher uses.
    static func all() -> [InputSource] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable: true,
            kTISPropertyInputSourceIsEnabled: true,
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource] else { return [] }

        return list.compactMap { ref in
            guard let id: String = prop(ref, kTISPropertyInputSourceID) else { return nil }
            if ignoredIDFragments.contains(where: id.contains) { return nil }
            // Skip the parent "input method" entry when it has selectable modes.
            if let type: String = prop(ref, kTISPropertyInputSourceType),
               type == (kTISTypeKeyboardInputMethodModeEnabled as String) { return nil }
            let name: String = prop(ref, kTISPropertyLocalizedName) ?? id
            return InputSource(id: id, name: name, flag: Flags.flag(for: ref, id: id), ref: ref)
        }
    }

    static func currentID() -> String? {
        let ref = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return prop(ref, kTISPropertyInputSourceID)
    }

    static func prop<T>(_ ref: TISInputSource, _ key: CFString) -> T? {
        guard let raw = TISGetInputSourceProperty(ref, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? T
    }
}

enum Flags {
    /// Layout-name prefix → ISO country code. Longest prefix wins.
    /// Covers cases where the language alone is ambiguous (British vs U.S., Swiss, Canadian…).
    private static let layoutTable: [(String, String)] = [
        ("US", "US"), ("ABC", "US"),
        ("Colemak", "US"), ("Dvorak", "US"),
        ("British", "GB"), ("Irish", "IE"), ("Welsh", "GB"), ("Australian", "AU"),
        ("Canadian", "CA"),
        ("Czech", "CZ"), ("Slovak", "SK"), ("Polish", "PL"), ("Hungarian", "HU"),
        ("German", "DE"), ("Austrian", "AT"), ("Swiss", "CH"),
        ("French", "FR"), ("Belgian", "BE"), ("Dutch", "NL"),
        ("Spanish", "ES"), ("Portuguese", "PT"), ("Brazilian", "BR"), ("Italian", "IT"),
        ("Danish", "DK"), ("Swedish", "SE"), ("Norwegian", "NO"), ("Finnish", "FI"),
        ("Icelandic", "IS"), ("Estonian", "EE"), ("Latvian", "LV"), ("Lithuanian", "LT"),
        ("Slovenian", "SI"), ("Croatian", "HR"), ("Serbian", "RS"), ("Romanian", "RO"),
        ("Bulgarian", "BG"), ("Greek", "GR"), ("Turkish", "TR"), ("Russian", "RU"),
        ("Ukrainian", "UA"), ("Belarusian", "BY"), ("Hebrew", "IL"), ("Arabic", "SA"),
        ("Persian", "IR"), ("Hindi", "IN"), ("Thai", "TH"), ("Vietnamese", "VN"),
        ("Korean", "KR"), ("Japanese", "JP"), ("Kazakh", "KZ"), ("Georgian", "GE"),
        ("Armenian", "AM"), ("Maltese", "MT"), ("LatinAmerican", "MX"),
    ].sorted { $0.0.count > $1.0.count }

    static func flag(for ref: TISInputSource, id: String) -> String {
        let last = id.split(separator: ".").last.map(String.init) ?? id
        if id.hasPrefix("com.apple.keylayout."),
           let (_, cc) = layoutTable.first(where: { last.hasPrefix($0.0) }) {
            return emoji(cc)
        }
        // Fall back to the source's primary language → most likely region.
        if let langs: [String] = InputSources.prop(ref, kTISPropertyInputSourceLanguages),
           let lang = langs.first,
           let region = Locale.Language(identifier: lang).maximalIdentifier
               .split(separator: "-").last.map(String.init),
           region.count == 2 {
            return emoji(region)
        }
        return "⌨️"
    }

    /// "SK" → 🇸🇰: each letter maps to its Unicode "regional indicator" symbol.
    static func emoji(_ countryCode: String) -> String {
        let regionalIndicatorA: UInt32 = 0x1F1E6
        return countryCode.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(regionalIndicatorA + $0.value - 65) }
            .map(String.init).joined()
    }
}
