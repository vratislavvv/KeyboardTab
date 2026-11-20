import AppKit
import ApplicationServices
import Carbon
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let switcher = Switcher()
    private let settingsWindow = SettingsWindowController()
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var syncTimer: Timer?
    private var settingsObserver: AnyCancellable?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshStatusTitle()

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(refreshStatusTitle),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, suspensionBehavior: .deliverImmediately)

        // macOS's own ⌃Space-style shortcuts are switched off while KeyboardTab handles them,
        // so only one switcher appears. Re-applied whenever the shortcut list changes.
        let settings = AppSettings.shared
        applyTakeOver()
        settingsObserver = settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.applyTakeOver() }
        }
        // Pick up changes made in System Settings (or by other apps) while running.
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            settings.refreshSystemShortcuts()
        }
        // Quit cleanly (restoring macOS's shortcuts) when killed from Terminal / Activity Monitor.
        signalSources = [SIGINT, SIGTERM, SIGHUP].map { sig in
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            return source
        }

        startTapWhenTrusted()

        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            openSettings()
        }
    }

    private func applyTakeOver() {
        let settings = AppSettings.shared
        // Without the keyboard hook KeyboardTab can't switch anything, so leave macOS's shortcuts alone.
        let takenOver = switcher.isActive ? Set(settings.takenOverSystemShortcuts.compactMap(\.hotkeyID)) : []
        SystemShortcuts.apply(enabledInSettings: Set(settings.systemShortcuts.compactMap(\.hotkeyID)),
                              takenOver: takenOver)
        if switcher.isActive && settings.shortcuts.contains(.globe) {
            GlobeKeySetting.takeOver()
        } else {
            GlobeKeySetting.giveBack()
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        SystemShortcuts.restore()
        GlobeKeySetting.giveBack()
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) while it's running shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: Accessibility permission

    private func startTapWhenTrusted() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts), switcher.installTap() { applyTakeOver(); return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
            guard let self, AXIsProcessTrusted(), self.switcher.installTap() else { return }
            t.invalidate()
            self.applyTakeOver()
            self.refreshStatusTitle()
        }
    }

    // MARK: Menu bar

    @objc private func refreshStatusTitle() {
        let current = InputSources.currentID()
        let flag = InputSources.all().first { $0.id == current }?.flag ?? "⌨️"
        statusItem.button?.title = AXIsProcessTrusted() ? flag : "\(flag)⚠️"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = InputSources.currentID()
        for src in InputSources.all() {
            let item = NSMenuItem(title: "\(src.flag)  \(src.name)", action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = src.id
            item.state = src.id == current ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        if !AXIsProcessTrusted() {
            let warn = NSMenuItem(title: "⚠️ Grant Accessibility Access…", action: #selector(openSettings), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit KeyboardTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        InputSources.all().first { $0.id == id }?.select()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }
}
