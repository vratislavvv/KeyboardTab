import AppKit
import Carbon
import ServiceManagement
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            hosting.sizingOptions = []
            let w = NSWindow(contentViewController: hosting)
            w.title = "KeyboardTab Settings"
            w.styleMask = [.titled, .closable, .resizable]
            w.setContentSize(NSSize(width: 480, height: 560))
            w.contentMinSize = NSSize(width: 420, height: 400)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var monitor: Any?
    @State private var message: String?
    @State private var trusted = AXIsProcessTrusted()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                if settings.shortcuts.isEmpty {
                    Text("No shortcuts. Add one below.").foregroundStyle(.secondary)
                }
                ForEach(settings.shortcuts) { sc in
                    HStack {
                        Text(sc.displayName).font(.system(size: 15, weight: .medium, design: .rounded))
                        if settings.isFromSystem(sc) { MacOSBadge() }
                        Spacer()
                        Button {
                            settings.remove(sc)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help(settings.isFromSystem(sc)
                              ? "Stop using this in KeyboardTab (macOS handles it again)"
                              : "Remove this shortcut")
                    }
                }
                ForEach(returnedShortcuts) { sc in
                    HStack {
                        Text(sc.displayName).font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        MacOSBadge()
                        Text("handled by macOS").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            settings.add(sc)
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                        }
                        .buttonStyle(.borderless)
                        .help("Use this shortcut in KeyboardTab again")
                    }
                }
                HStack {
                    Button(settings.isRecording ? "Press keys… (Esc cancels)" : "Add Shortcut…") {
                        settings.isRecording ? stopRecording() : startRecording()
                    }
                    if !settings.shortcuts.contains(.globe) && !returnedShortcuts.contains(.globe) {
                        Button("Add 🌐 Globe Key") { settings.add(.globe) }
                    }
                    Spacer()
                    Button("Reset") {
                        settings.reset()
                        message = nil
                    }
                    .help("Use exactly the shortcuts set up in macOS and remove the ones you added")
                }
                if let message {
                    Text(message).font(.callout).foregroundStyle(.orange)
                }
            } header: {
                Text("Shortcuts that switch the keyboard")
            } footer: {
                Text("Shortcuts marked macOS are read from System Settings → Keyboard and update automatically. Hold the modifier keys and keep pressing the key to move through layouts, then release to switch. Add ⇧ to go backwards. Shortcuts without ⌃ ⌥ ⌘ (F-keys, 🌐) switch on every press.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                HStack {
                    Label(trusted ? "Accessibility access granted" : "Accessibility access needed",
                          systemImage: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Spacer()
                    if !trusted {
                        Button("Open Settings") {
                            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            // Keep the Accessibility status current while the window is open.
            while !Task.isCancelled {
                trusted = AXIsProcessTrusted()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
        .onDisappear(perform: stopRecording)
    }

    /// macOS shortcuts the user removed from the list (macOS handles them again).
    private var returnedShortcuts: [Shortcut] {
        settings.systemShortcuts.map(\.shortcut).filter { !settings.shortcuts.contains($0) }
    }

    // MARK: Recording

    private func startRecording() {
        message = nil
        settings.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(Shortcut.relevant)
            let code = Int(event.keyCode)
            if code == kVK_Escape && mods.isEmpty {
                stopRecording()
                return nil
            }
            if mods.intersection(Shortcut.holdable).isEmpty && !KeyNames.isFunctionKey(code) {
                message = "Use at least one of ⌃ ⌥ ⌘ (or an F-key), so normal typing isn't blocked."
                return nil
            }
            let sc = Shortcut(keyCode: code, modifiers: mods.rawValue)
            if settings.shortcuts.contains(sc) {
                message = "\(sc.displayName) is already in the list."
            } else {
                settings.add(sc)
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        settings.isRecording = false
    }

    // MARK: Actions

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            message = "Launch at login failed: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}

private struct MacOSBadge: View {
    var body: some View {
        Text("macOS")
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
            .foregroundStyle(.secondary)
            .help("Set up in System Settings → Keyboard")
    }
}
