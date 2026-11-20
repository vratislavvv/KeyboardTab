import AppKit
import Carbon

final class Switcher {
    private enum Mode {
        case none
        case hold(Shortcut)  // panel open while the shortcut's modifiers are held (AltTab-style)
        case tap             // each press switches immediately; panel fades out afterwards
    }

    private let settings = AppSettings.shared
    private let hud = HUDPanel()
    private var mode = Mode.none
    private var items: [InputSource] = []
    private var index = 0
    private var hideTimer: Timer?
    private var tap: CFMachPort?

    /// True once the keyboard hook runs (needs Accessibility access).
    var isActive: Bool { tap != nil }

    // 🌐 Globe key: a quick tap switches layouts; holding it (e.g. Wispr Flow's hold-to-talk)
    // or using it with another key does not.
    private enum GlobeState { case idle, tapCandidate, usedWithOtherKey, held }
    private var globeState = GlobeState.idle
    private var globeSwallowed = false
    private var globeTimer: Timer?
    private var globeDownEvent: CGEvent?
    private let globeHoldDelay = 0.3
    private static let syntheticMarker: Int64 = 0x4B54_4142  // marks events we re-post ourselves

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
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker { return pass }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case _ where settings.isRecording:
            return pass  // let the settings window see the keys
        case .flagsChanged:
            return handleFlags(event) ? nil : pass
        case .keyDown, .keyUp:
            return handleKey(event, down: type == .keyDown) ? nil : pass
        default:
            return pass
        }
    }

    private func modifiers(_ e: CGEvent) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(e.flags.rawValue)).intersection(Shortcut.relevant)
    }

    /// Returns true when the event should be swallowed.
    private func handleKey(_ e: CGEvent, down: Bool) -> Bool {
        let code = Int(e.getIntegerValueField(.keyboardEventKeycode))
        let flags = modifiers(e)
        if down && globeState == .tapCandidate { globeUsedWithOtherKey() }

        if case .hold(let sc) = mode {
            switch code {
            case sc.keyCode:
                let backwards = flags.contains(.shift) && !sc.flags.contains(.shift)
                if down { move(backwards ? -1 : 1) }
            case kVK_Escape: if down { finish(commit: false) }
            case kVK_Return, kVK_ANSI_KeypadEnter: if down { finish(commit: true) }
            case kVK_UpArrow, kVK_LeftArrow: if down { move(-1) }
            case kVK_DownArrow, kVK_RightArrow: if down { move(1) }
            default: return false
            }
            return true
        }

        guard let (sc, step) = match(code: code, flags: flags) else { return false }
        let isRepeat = e.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if down && !isRepeat { trigger(sc, step: step) }
        return true
    }

    /// Finds the shortcut for this key. Holding ⇧ in addition means "go backwards".
    private func match(code: Int, flags: NSEvent.ModifierFlags) -> (Shortcut, Int)? {
        for sc in settings.shortcuts where !sc.isGlobe && sc.keyCode == code {
            if flags == sc.flags { return (sc, 1) }
            if !sc.flags.contains(.shift), flags == sc.flags.union(.shift) { return (sc, -1) }
        }
        return nil
    }

    /// Returns true when the event should be swallowed.
    private func handleFlags(_ e: CGEvent) -> Bool {
        let code = Int(e.getIntegerValueField(.keyboardEventKeycode))

        if case .hold(let sc) = mode, !modifiers(e).contains(sc.holdFlags) {
            finish(commit: true)
        }
        if code == kVK_Function { return handleGlobe(e) }
        if globeState == .tapCandidate { globeUsedWithOtherKey() }  // 🌐 + another modifier
        return false
    }

    private func handleGlobe(_ e: CGEvent) -> Bool {
        guard settings.shortcuts.contains(.globe) else { globeState = .idle; return false }

        if e.flags.contains(.maskSecondaryFn) {
            // Normally KeyboardTab sets macOS's 🌐 action to "Do Nothing", so the press can pass
            // through untouched. If macOS would still react, hide the press from it until we
            // know it's a hold rather than a tap.
            globeSwallowed = GlobeKeySetting.current != GlobeKeySetting.doNothing
            globeState = .tapCandidate
            globeDownEvent = e.copy()
            globeTimer?.invalidate()
            globeTimer = Timer.scheduledTimer(withTimeInterval: globeHoldDelay, repeats: false) { [weak self] _ in
                self?.globeHeld()
            }
            return globeSwallowed
        }

        // Released.
        globeTimer?.invalidate()
        let state = globeState
        globeState = .idle
        switch state {
        case .tapCandidate:
            trigger(.globe, step: 1)  // quick tap → switch layout
            return globeSwallowed
        case .usedWithOtherKey:
            return globeSwallowed  // keep press/release consistent for whoever saw (or didn't see) the press
        case .held, .idle:
            return false
        }
    }

    /// 🌐 held longer than a tap: not ours. If we hid the press, hand it on now.
    private func globeHeld() {
        guard globeState == .tapCandidate else { return }
        globeState = .held
        guard globeSwallowed, let event = globeDownEvent else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        event.post(tap: .cgSessionEventTap)
    }

    /// 🌐 used as a modifier (🌐+arrow, 🌐+F…): not a tap.
    private func globeUsedWithOtherKey() {
        globeTimer?.invalidate()
        globeState = .usedWithOtherKey
    }

    // MARK: Switching

    private func trigger(_ sc: Shortcut, step: Int) {
        if case .tap = mode {
            move(step)
            selectAndScheduleHide()
            return
        }
        if settings.onlyWhenNoTextField && TextFocus.isTextInputFocused() {
            switchSilently(step)
            return
        }
        if sc.isGlobe || sc.holdFlags.isEmpty {
            begin(.tap, step: step)
            selectAndScheduleHide()
        } else {
            begin(.hold(sc), step: step)
        }
    }

    private func begin(_ newMode: Mode, step: Int) {
        items = InputSources.all()
        guard items.count > 1 else { return }
        index = wrap(currentIndex() + step)
        mode = newMode
        hideTimer?.invalidate()
        hud.show(items: items, selected: index)
    }

    /// Used while typing in a text field: switch straight away, no panel.
    private func switchSilently(_ step: Int) {
        items = InputSources.all()
        guard items.count > 1 else { return }
        items[wrap(currentIndex() + step)].select()
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

    private func selectAndScheduleHide() {
        guard case .tap = mode, items.indices.contains(index) else { return }
        items[index].select()
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            guard let self, case .tap = self.mode else { return }
            self.mode = .none
            self.hud.dismiss()
        }
    }

    private func currentIndex() -> Int {
        let current = InputSources.currentID()
        return items.firstIndex { $0.id == current } ?? 0
    }

    private func wrap(_ i: Int) -> Int { ((i % items.count) + items.count) % items.count }
}
