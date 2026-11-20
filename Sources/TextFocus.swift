import AppKit
import ApplicationServices

/// Asks the Accessibility API whether the user is currently typing somewhere.
enum TextFocus {
    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    private static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        // Never block the keyboard hook for long if an app is unresponsive.
        AXUIElementSetMessagingTimeout(element, 0.15)
        return element
    }()

    static func isTextInputFocused() -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return false }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)

        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           let role = role as? String, textRoles.contains(role) {
            return true
        }
        // Rich editors (web pages, custom text views) expose an editable text selection.
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable) == .success
            && settable.boolValue
    }
}
