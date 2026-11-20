import AppKit
import ApplicationServices
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let switcher = Switcher()
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?

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

        SystemShortcuts.setEnabled(false)
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig) { _ in SystemShortcuts.setEnabled(true); exit(0) }
        }

        startTapWhenTrusted()
    }

    func applicationWillTerminate(_ note: Notification) {
        SystemShortcuts.setEnabled(true)
    }

    // MARK: Accessibility permission

    private func startTapWhenTrusted() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts), switcher.installTap() { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
            guard let self, AXIsProcessTrusted(), self.switcher.installTap() else { return }
            t.invalidate()
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
            let warn = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(openAccessibility), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }

        let hint = NSMenuItem(title: "Switch with ⌃Space (hold ⌃, tap Space)", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        let globe = NSMenuItem(title: "Also Use 🌐 Globe Key", action: #selector(toggleGlobe), keyEquivalent: "")
        globe.target = self
        globe.state = switcher.globeEnabled ? .on : .off
        menu.addItem(globe)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit KeyboardTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        InputSources.all().first { $0.id == id }?.select()
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleGlobe() {
        switcher.globeEnabled.toggle()
        guard switcher.globeEnabled else { return }
        let fnUsage = UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int
        if fnUsage != 0 {
            let alert = NSAlert()
            alert.messageText = "Set the 🌐 key to “Do Nothing”"
            alert.informativeText = "So macOS doesn't show its own switcher too, open System Settings → Keyboard and set “Press 🌐 key to” → “Do Nothing”."
            alert.addButton(withTitle: "Open Keyboard Settings")
            alert.addButton(withTitle: "Later")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
            }
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

