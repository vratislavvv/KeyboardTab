import AppKit
import Carbon
import Combine

/// A key combination that opens the switcher. `keyCode == -1` means the 🌐 Globe (fn) key.
struct Shortcut: Codable, Hashable, Identifiable {
    let keyCode: Int
    let modifiers: UInt  // NSEvent.ModifierFlags raw value, limited to ⌃⌥⇧⌘

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
        let detected = InputSourceHotkeys.detect()
        if detected != systemShortcuts { systemShortcuts = detected }
    }

    private func save(_ list: [Shortcut], _ key: String) {
        defaults.set(try? JSONEncoder().encode(list), forKey: key)
    }

    private static func load(_ key: String) -> [Shortcut] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Shortcut].self, from: data)) ?? []
    }
}

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
