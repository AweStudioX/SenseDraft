import AppKit
import ApplicationServices
import SenseDraftCore

enum AccessibilityError: Error {
    case permissionDenied
    case noFocusedField
    case unavailable
    case unsupportedRead(String)
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
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            throw AccessibilityError.noFocusedField
        }
        let element = raw as! AXUIElement
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let appID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
            throw AccessibilityError.unavailable
        }
        guard pid != ProcessInfo.processInfo.processIdentifier else { throw AccessibilityError.noFocusedField }
        let role = try stringValue(element, kAXRoleAttribute)
        let subrole = try? stringValue(element, kAXSubroleAttribute)
        guard subrole != kAXSecureTextFieldSubrole else { throw FieldError.protected }
        guard role == kAXTextFieldRole || role == kAXTextAreaRole else {
            throw AccessibilityError.unsupportedRead(appID)
        }
        let source: String
        do { source = try stringValue(element, kAXValueAttribute) }
        catch { throw AccessibilityError.unsupportedRead(appID) }
        var settable: DarwinBoolean = false
        let editable = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
        try FieldPolicy.validate(role: role, protected: subrole == kAXSecureTextFieldSubrole, editable: editable, value: source)
        return CapturedField(element: element, pid: pid, appID: appID, source: source,
                             bounds: bounds(of: element), richTextRisk: hasMixedFormatting(element, source: source))
    }

    static func stringValue(_ element: AXUIElement, _ key: String) throws -> String {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &raw) == .success,
              let value = raw as? String else {
            throw AccessibilityError.unavailable
        }
        return value
    }

    private static func bounds(of element: AXUIElement) -> CGRect? {
        var positionRaw: CFTypeRef?
        var sizeRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRaw) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRaw) == .success,
              let positionRaw, let sizeRaw,
              CFGetTypeID(positionRaw) == AXValueGetTypeID(), CFGetTypeID(sizeRaw) == AXValueGetTypeID() else { return nil }
        let position = positionRaw as! AXValue
        let size = sizeRaw as! AXValue
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private static func hasMixedFormatting(_ element: AXUIElement, source: String) -> Bool {
        var range = CFRange(location: 0, length: (source as NSString).length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return false }
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXAttributedStringForRangeParameterizedAttribute as CFString, parameter, &raw) == .success,
              let attributed = raw as? NSAttributedString, attributed.length > 0 else { return false }
        let initial = NSDictionary(dictionary: attributed.attributes(at: 0, effectiveRange: nil))
        var varied = false
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, _, stop in
            if !NSDictionary(dictionary: attributes).isEqual(initial) {
                varied = true
                stop.pointee = true
            }
        }
        return varied
    }
}

@MainActor
struct CapturedField {
    let element: AXUIElement
    let pid: pid_t
    let appID: String
    let source: String
    let bounds: CGRect?
    let richTextRisk: Bool

    func replaceIfUnchanged(with replacement: String) throws {
        var targetPID: pid_t = 0
        guard AXUIElementGetPid(element, &targetPID) == .success, targetPID == pid else {
            throw AccessibilityError.stale
        }
        let currentSource = try AccessibilityField.stringValue(element, kAXValueAttribute)
        guard currentSource == source else { throw AccessibilityError.stale }

        let system = AXUIElementCreateSystemWide()
        var rawFocused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &rawFocused) == .success,
              let rawFocused, CFGetTypeID(rawFocused) == AXUIElementGetTypeID() else { throw AccessibilityError.stale }
        let focused = rawFocused as! AXUIElement
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success else { throw AccessibilityError.stale }
        if focusedPID != ProcessInfo.processInfo.processIdentifier && !CFEqual(focused, element) {
            throw AccessibilityError.stale
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
