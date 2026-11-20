import AppKit
import Carbon
import Combine

/// A key combination that opens the switcher. `keyCode == -1` means the 🌐 Globe (fn) key.
struct Shortcut: Codable, Hashable, Identifiable {
    var keyCode: Int
    var modifiers: UInt  // NSEvent.ModifierFlags raw value, limited to ⌃⌥⇧⌘

    static let relevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    static let holdable: NSEvent.ModifierFlags = [.control, .option, .command]
    static let globe = Shortcut(keyCode: -1, modifiers: 0)

    init(keyCode: Int, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Shortcut.relevant.rawValue
    }

    var id: String { "\(keyCode)-\(modifiers)" }
    var isGlobe: Bool { keyCode == -1 }
    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }
    /// Modifiers that keep the panel open while held (⌃⌥⌘). Empty → each press switches immediately.
    var holdFlags: NSEvent.ModifierFlags { flags.intersection(Shortcut.holdable) }

    var displayName: String {
        if isGlobe { return "🌐  Globe key" }
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + KeyNames.name(for: keyCode)
    }
}

/// A shortcut macOS itself has configured for switching input sources.
struct SystemShortcut: Equatable {
    let shortcut: Shortcut
    let hotkeyID: Int32?  // symbolic-hotkey id (60/61), nil for the Globe key
}

/// User preferences, saved in UserDefaults.
///
/// The active shortcut list = shortcuts macOS has configured (detected live, minus the ones
/// the user handed back to macOS) + shortcuts the user added in KeyboardTab.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    /// Shortcuts currently set up in macOS. Refreshed by `refreshSystemShortcuts()`.
    @Published private(set) var systemShortcuts: [SystemShortcut] = []
    /// Shortcuts added in KeyboardTab.
    @Published private(set) var customShortcuts: [Shortcut] {
        didSet { save(customShortcuts, "customShortcuts") }
    }
    /// macOS shortcuts the user removed from the list: macOS keeps handling those itself.
    @Published private(set) var returnedToSystem: [Shortcut] {
        didSet { save(returnedToSystem, "returnedToSystem") }
    }
    @Published var onlyWhenNoTextField: Bool {
        didSet { defaults.set(onlyWhenNoTextField, forKey: "onlyWhenNoTextField") }
    }
    /// True while the settings window is recording a new shortcut (the switcher stays quiet).
    @Published var isRecording = false

    private init() {
        customShortcuts = AppSettings.load("customShortcuts")
        returnedToSystem = AppSettings.load("returnedToSystem")
        onlyWhenNoTextField = defaults.object(forKey: "onlyWhenNoTextField") as? Bool ?? true
        refreshSystemShortcuts()
    }

    /// Shortcuts KeyboardTab reacts to.
    var shortcuts: [Shortcut] {
        var seen = Set<Shortcut>()
        return (takenOverSystemShortcuts.map(\.shortcut) + customShortcuts).filter { seen.insert($0).inserted }
    }

    var takenOverSystemShortcuts: [SystemShortcut] {
        systemShortcuts.filter { !returnedToSystem.contains($0.shortcut) }
    }

    func isFromSystem(_ sc: Shortcut) -> Bool { systemShortcuts.contains { $0.shortcut == sc } }

    func add(_ sc: Shortcut) {
        if isFromSystem(sc) { returnedToSystem.removeAll { $0 == sc } }
        else if !customShortcuts.contains(sc) { customShortcuts.append(sc) }
    }

    func remove(_ sc: Shortcut) {
        customShortcuts.removeAll { $0 == sc }
        if isFromSystem(sc), !returnedToSystem.contains(sc) { returnedToSystem.append(sc) }
    }

    /// Back to exactly what macOS has configured.
    func reset() {
        customShortcuts = []
        returnedToSystem = []
    }

    /// Re-reads macOS's shortcut configuration (cheap; called every few seconds).
    func refreshSystemShortcuts() {
        let detected = AppSettings.detectSystemShortcuts()
        if detected != systemShortcuts { systemShortcuts = detected }
    }

    /// Reads System Settings → Keyboard → Keyboard Shortcuts → Input Sources
    /// and System Settings → Keyboard → "Press 🌐 key to".
    static func detectSystemShortcuts() -> [SystemShortcut] {
        let control = NSEvent.ModifierFlags.control.rawValue
        let option = NSEvent.ModifierFlags.option.rawValue
        let macDefaults: [(Int32, Shortcut)] = [
            (60, Shortcut(keyCode: kVK_Space, modifiers: control)),           // select previous source
            (61, Shortcut(keyCode: kVK_Space, modifiers: control | option)),  // select next source
        ]
        let hotkeys = readPreference("AppleSymbolicHotKeys", in: "com.apple.symbolichotkeys") as? [String: Any] ?? [:]

        var result: [SystemShortcut] = []
        for (id, fallback) in macDefaults {
            // No entry = never customised = macOS default (enabled).
            guard let entry = hotkeys[String(id)] as? [String: Any] else {
                result.append(SystemShortcut(shortcut: fallback, hotkeyID: id))
                continue
            }
            guard (entry["enabled"] as? Bool) ?? true else { continue }
            if let value = entry["value"] as? [String: Any],
               let p = value["parameters"] as? [Int], p.count == 3, p[1] != 65535 {
                result.append(SystemShortcut(shortcut: Shortcut(keyCode: p[1], modifiers: UInt(p[2])), hotkeyID: id))
            }
        }
        if globeSwitchesInputSource {
            result.append(SystemShortcut(shortcut: .globe, hotkeyID: nil))
        }
        var seen = Set<Shortcut>()
        return result.filter { seen.insert($0.shortcut).inserted }
    }

    /// macOS itself switches input sources on 🌐 (or did, before KeyboardTab took it over).
    static var globeSwitchesInputSource: Bool {
        GlobeKeySetting.current == GlobeKeySetting.changeInputSource
            || GlobeKeySetting.valueBeforeTakeOver == GlobeKeySetting.changeInputSource
    }

    private static func readPreference(_ key: String, in domain: String) -> Any? {
        CFPreferencesAppSynchronize(domain as CFString)
        return CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }

    private func save(_ list: [Shortcut], _ key: String) {
        defaults.set(try? JSONEncoder().encode(list), forKey: key)
    }

    private static func load(_ key: String) -> [Shortcut] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Shortcut].self, from: data)) ?? []
    }
}

/// System Settings → Keyboard → "Press 🌐 key to".
/// Uses HIToolbox's own (private) getter/setter, the same path System Settings takes,
/// so changes apply immediately without a restart.
enum GlobeKeySetting {
    static let doNothing: Int32 = 0
    static let changeInputSource: Int32 = 1  // 2 = Emoji & Symbols, 3 = Dictation

    private static let savedKey = "globeSettingBeforeTakeOver"

    static var current: Int32 { TISGetFnUsageType() }

    /// What the setting was before KeyboardTab switched it to "Do Nothing" (nil = not taken over).
    static var valueBeforeTakeOver: Int32? {
        (UserDefaults.standard.object(forKey: savedKey) as? Int).map(Int32.init)
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

@_silgen_name("TISGetFnUsageType")
private func TISGetFnUsageType() -> Int32

@_silgen_name("TISUpdateFnUsageType")
@discardableResult
private func TISUpdateFnUsageType(_ value: Int32) -> Int32

enum KeyNames {
    static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]
    private static let special: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
        kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_ANSI_KeypadEnter: "⌤",
    ]

    static func isFunctionKey(_ code: Int) -> Bool { functionKeys[code] != nil }

    /// Human-readable key name, using the Mac's current keyboard layout for character keys.
    static func name(for code: Int) -> String {
        if let s = special[code] ?? functionKeys[code] { return s }
        guard let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData)
        else { return "Key \(code)" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { buf in
            UCKeyTranslate(buf.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self),
                           UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "Key \(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
