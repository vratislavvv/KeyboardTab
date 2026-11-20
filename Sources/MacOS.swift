import AppKit
import Carbon

// Everything that reads or changes macOS's own keyboard-switching settings.

/// A shortcut macOS itself has configured for switching input sources.
struct SystemShortcut: Equatable {
    let shortcut: Shortcut
    let hotkeyID: Int32?  // symbolic-hotkey id (60/61), nil for the Globe key
}

/// System Settings → Keyboard → Keyboard Shortcuts → Input Sources
/// ("Select the previous input source" ⌃Space, "Select next source in Input menu" ⌃⌥Space).
enum InputSourceHotkeys {
    private static let previousSource: Int32 = 60
    private static let nextSource: Int32 = 61

    /// Shortcuts macOS currently has switched on, plus 🌐 if it switches layouts.
    static func detect() -> [SystemShortcut] {
        let control = NSEvent.ModifierFlags.control.rawValue
        let option = NSEvent.ModifierFlags.option.rawValue
        let macDefaults: [(Int32, Shortcut)] = [
            (previousSource, Shortcut(keyCode: kVK_Space, modifiers: control)),
            (nextSource, Shortcut(keyCode: kVK_Space, modifiers: control | option)),
        ]
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let hotkeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]

        var result: [SystemShortcut] = []
        for (id, fallback) in macDefaults {
            // No entry = never customised = macOS default (on).
            guard let entry = hotkeys[String(id)] as? [String: Any] else {
                result.append(SystemShortcut(shortcut: fallback, hotkeyID: id))
                continue
            }
            guard (entry["enabled"] as? Bool) ?? true else { continue }
            if let value = entry["value"] as? [String: Any],
               let p = value["parameters"] as? [Int], p.count == 3, p[1] != 65535 {  // [char, keyCode, modifiers]
                result.append(SystemShortcut(shortcut: Shortcut(keyCode: p[1], modifiers: UInt(p[2])), hotkeyID: id))
            }
        }
        if GlobeKeySetting.switchesInputSource {
            result.append(SystemShortcut(shortcut: .globe, hotkeyID: nil))
        }
        var seen = Set<Shortcut>()
        return result.filter { seen.insert($0.shortcut).inserted }
    }

    /// Each hotkey is live exactly when System Settings has it on and KeyboardTab isn't handling it.
    /// Only the live state changes; System Settings itself is never written.
    static func apply(enabledInSettings: Set<Int32>, takenOver: Set<Int32>) {
        for id in [previousSource, nextSource] {
            CGSSetSymbolicHotKeyEnabled(id, enabledInSettings.contains(id) && !takenOver.contains(id))
        }
    }

    /// Back to exactly what System Settings says.
    static func restore() {
        apply(enabledInSettings: Set(detect().compactMap(\.hotkeyID)), takenOver: [])
    }
}

/// System Settings → Keyboard → "Press 🌐 key to".
/// Uses HIToolbox's own getter/setter (the path System Settings takes), so changes apply
/// immediately; writing the preference alone would need a restart.
enum GlobeKeySetting {
    static let doNothing: Int32 = 0
    static let changeInputSource: Int32 = 1  // 2 = Emoji & Symbols, 3 = Dictation

    private static let savedKey = "globeSettingBeforeTakeOver"

    static var current: Int32 { TISGetFnUsageType() }

    /// What the setting was before KeyboardTab switched it to "Do Nothing" (nil = not taken over).
    static var valueBeforeTakeOver: Int32? {
        (UserDefaults.standard.object(forKey: savedKey) as? Int).map(Int32.init)
    }

    /// macOS switches layouts on 🌐 (or did, before KeyboardTab took it over).
    static var switchesInputSource: Bool {
        current == changeInputSource || valueBeforeTakeOver == changeInputSource
    }

    /// Stops macOS reacting to 🌐 so only KeyboardTab's panel appears.
    static func takeOver() {
        guard current != doNothing else { return }
        if valueBeforeTakeOver == nil { UserDefaults.standard.set(Int(current), forKey: savedKey) }
        set(doNothing)
    }

    /// Puts the setting back the way it was.
    static func giveBack() {
        guard let original = valueBeforeTakeOver else { return }
        if current == doNothing { set(original) }  // don't override a change the user made meanwhile
        UserDefaults.standard.removeObject(forKey: savedKey)
    }

    private static func set(_ value: Int32) {
        let domain = "com.apple.HIToolbox" as CFString
        CFPreferencesSetAppValue("AppleFnUsageType" as CFString, NSNumber(value: value), domain)
        CFPreferencesAppSynchronize(domain)
        TISUpdateFnUsageType(value)
    }
}

// MARK: Private macOS APIs

// SkyLight (also used by AltTab): turns a symbolic hotkey on/off for this login session only.
@_silgen_name("CGSSetSymbolicHotKeyEnabled")
@discardableResult
private func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: Bool) -> Int32

// HIToolbox: read / apply the "Press 🌐 key to" setting.
@_silgen_name("TISGetFnUsageType")
private func TISGetFnUsageType() -> Int32

@_silgen_name("TISUpdateFnUsageType")
@discardableResult
private func TISUpdateFnUsageType(_ value: Int32) -> Int32
