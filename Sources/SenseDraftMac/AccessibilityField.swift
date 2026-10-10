import AppKit
import ApplicationServices
import SenseDraftCore

enum AccessibilityError: Error {
    case permissionDenied
    case noFocusedField
    case unavailable
    case stale
    case unsupportedWrite
    case writeFailed
}

@MainActor
struct AccessibilityField {
    static func captureFocused() throws -> CapturedField {
        guard AXIsProcessTrusted() else { throw AccessibilityError.permissionDenied }
        let system = AXUIElementCreateSystemWide()
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &raw) == .success,
              let element = raw as! AXUIElement? else {
            throw AccessibilityError.noFocusedField
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let appID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
            throw AccessibilityError.unavailable
        }
        let role = try stringValue(element, kAXRoleAttribute)
        let subrole = try? stringValue(element, kAXSubroleAttribute)
        let source = try stringValue(element, kAXValueAttribute)
        var settable: DarwinBoolean = false
        let editable = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
        try FieldPolicy.validate(role: role, protected: subrole == kAXSecureTextFieldSubrole, editable: editable, value: source)
        return CapturedField(element: element, pid: pid, appID: appID, source: source)
    }

    static func stringValue(_ element: AXUIElement, _ key: String) throws -> String {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &raw) == .success,
              let value = raw as? String else {
            throw AccessibilityError.unavailable
        }
        return value
    }
}

@MainActor
struct CapturedField {
    let element: AXUIElement
    let pid: pid_t
    let appID: String
    let source: String

    func replaceIfUnchanged(with replacement: String) throws {
        var targetPID: pid_t = 0
        guard AXUIElementGetPid(element, &targetPID) == .success, targetPID == pid else {
            throw AccessibilityError.stale
        }
        let currentSource = try AccessibilityField.stringValue(element, kAXValueAttribute)
        guard currentSource == source else { throw AccessibilityError.stale }

        let system = AXUIElementCreateSystemWide()
        var rawFocused: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &rawFocused) == .success,
           let focused = rawFocused as! AXUIElement? {
            var focusedPID: pid_t = 0
            if AXUIElementGetPid(focused, &focusedPID) == .success,
               focusedPID != ProcessInfo.processInfo.processIdentifier,
               !CFEqual(focused, element) {
                throw AccessibilityError.stale
            }
        }

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue else {
            throw AccessibilityError.unsupportedWrite
        }
        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, replacement as CFString) == .success else {
            throw AccessibilityError.writeFailed
        }
        guard try AccessibilityField.stringValue(element, kAXValueAttribute) == replacement else {
            throw AccessibilityError.writeFailed
        }
    }
}
