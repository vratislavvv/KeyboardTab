import AppKit
import Carbon

// Private SkyLight API (also used by AltTab) to temporarily turn off the system's
// own ⌃Space / ⌃⌥Space input-source shortcuts so only our switcher reacts.
// The change is not persisted — it lasts only while this app is running.
@_silgen_name("CGSSetSymbolicHotKeyEnabled")
@discardableResult
private func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: Bool) -> Int32

enum SystemShortcuts {
    static let ids: [Int32] = [60, 61]  // 60 = select previous source (⌃Space), 61 = next (⌃⌥Space)
    static func setEnabled(_ on: Bool) { ids.forEach { CGSSetSymbolicHotKeyEnabled($0, on) } }
}

final class Switcher {
    private enum Mode { case none, control, globe }

    private let hud = HUDPanel()
    private var mode = Mode.none
    private var items: [InputSource] = []
    private var index = 0
    private var hideTimer: Timer?
    private var fnDown = false
    private var fnUsedAsModifier = false
    private var tap: CFMachPort?

    var globeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "globeEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "globeEnabled") }
    }

    // MARK: Event tap

    @discardableResult
    func installTap() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, info in
                let s = Unmanaged<Switcher>.fromOpaque(info!).takeUnretainedValue()
                return s.handle(type: type, event: event)
            },
            userInfo: me)
        else { return false }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .flagsChanged:
            return handleFlags(event) ? nil : pass
        case .keyDown, .keyUp:
            return handleKey(event, down: type == .keyDown) ? nil : pass
        default:
            return pass
        }
    }

    /// Returns true when the event should be swallowed.
    private func handleKey(_ e: CGEvent, down: Bool) -> Bool {
        let code = Int(e.getIntegerValueField(.keyboardEventKeycode))
        let flags = e.flags
        if down && fnDown { fnUsedAsModifier = true }

        if mode == .control {
            switch code {
            case kVK_Space:
                if down { move(flags.contains(.maskShift) ? -1 : 1) }
                return true
            case kVK_Escape:
                if down { finish(commit: false) }
                return true
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if down { finish(commit: true) }
                return true
            case kVK_UpArrow, kVK_LeftArrow:
                if down { move(-1) }
                return true
            case kVK_DownArrow, kVK_RightArrow:
                if down { move(1) }
                return true
            default:
                return false
            }
        }

        // ⌃Space or ⌃⌥Space (no ⌘) opens the switcher.
        if down, code == kVK_Space, flags.contains(.maskControl), !flags.contains(.maskCommand) {
            begin(.control, step: flags.contains(.maskShift) ? -1 : 1)
            return true
        }
        return false
    }

    private func handleFlags(_ e: CGEvent) -> Bool {
        let code = Int(e.getIntegerValueField(.keyboardEventKeycode))
        let flags = e.flags

        if mode == .control && !flags.contains(.maskControl) {
            finish(commit: true)
        }

        if code == kVK_Function && globeEnabled {
            if flags.contains(.maskSecondaryFn) {
                fnDown = true
                fnUsedAsModifier = false
            } else if fnDown {
                fnDown = false
                if !fnUsedAsModifier { globeTapped() }
            }
        } else if fnDown, code != kVK_Function {
            fnUsedAsModifier = true  // fn + another modifier
        }
        return false
    }

    // MARK: Switching

    private func begin(_ newMode: Mode, step: Int) {
        items = InputSources.all()
        guard items.count > 1 else { return }
        let current = items.firstIndex { $0.id == InputSources.currentID() } ?? 0
        index = wrap(current + step)
        mode = newMode
        hideTimer?.invalidate()
        hud.show(items: items, selected: index)
    }

    private func move(_ step: Int) {
        guard !items.isEmpty else { return }
        index = wrap(index + step)
        hud.update(selected: index)
    }

    private func finish(commit: Bool) {
        if commit, items.indices.contains(index) { items[index].select() }
        mode = .none
        hud.dismiss()
    }

    /// Globe key behaves like the system one: each tap switches immediately
    /// and the panel fades out shortly after the last tap.
    private func globeTapped() {
        if mode == .globe {
            move(1)
        } else {
            if mode == .control { finish(commit: false) }
            begin(.globe, step: 1)
        }
        guard mode == .globe, items.indices.contains(index) else { return }
        items[index].select()
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            guard let self, self.mode == .globe else { return }
            self.mode = .none
            self.hud.dismiss()
        }
    }

    private func wrap(_ i: Int) -> Int { ((i % items.count) + items.count) % items.count }
}
