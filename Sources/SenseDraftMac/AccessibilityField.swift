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
    static func captureFocused(frontmostPID: pid_t?) throws -> CapturedField {
        guard AXIsProcessTrusted() else { throw AccessibilityError.permissionDenied }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard frontmostPID != ownPID else { throw AccessibilityError.noFocusedField }
        let element: AXUIElement?
        if let frontmostPID {
            // Electron editors can expose focus on their application AX object
            // even when the system-wide focused element is temporarily absent.
            element = focusedElement(of: AXUIElementCreateApplication(frontmostPID))
                ?? focusedElement(of: AXUIElementCreateSystemWide())
        } else {
            element = focusedElement(of: AXUIElementCreateSystemWide())
        }
        guard let element else {
            throw AccessibilityError.noFocusedField
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let appID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
            throw AccessibilityError.unavailable
        }
        guard pid != ownPID, frontmostPID == nil || pid == frontmostPID else {
            throw AccessibilityError.noFocusedField
        }
        let role = try stringValue(element, kAXRoleAttribute)
        let subrole = try? stringValue(element, kAXSubroleAttribute)
        guard subrole != kAXSecureTextFieldSubrole else { throw FieldError.protected }
        guard role == kAXTextFieldRole || role == kAXTextAreaRole else {
            throw AccessibilityError.unsupportedRead(appID)
        }
        let source: String
        do { source = try fullText(of: element) }
        catch { throw AccessibilityError.unsupportedRead(appID) }
        let editable = isSettable(element, kAXValueAttribute) ||
            (isSettable(element, kAXSelectedTextRangeAttribute) && isSettable(element, kAXSelectedTextAttribute))
        guard editable else { throw AccessibilityError.unsupportedRead(appID) }
        try FieldPolicy.validate(role: role, protected: subrole == kAXSecureTextFieldSubrole, editable: editable, value: source)
        return CapturedField(element: element, pid: pid, appID: appID, source: source,
                             bounds: bounds(of: element), richTextRisk: hasMixedFormatting(element, source: source))
    }

    private static func focusedElement(of parent: AXUIElement) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXFocusedUIElementAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    static func stringValue(_ element: AXUIElement, _ key: String) throws -> String {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &raw) == .success,
              let value = raw as? String else {
            throw AccessibilityError.unavailable
        }
        return value
    }

    static func fullText(of element: AXUIElement) throws -> String {
        if let value = try? stringValue(element, kAXValueAttribute), !value.isEmpty { return value }
        var rawCount: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &rawCount) == .success,
              let count = rawCount as? NSNumber, count.intValue >= 0, count.intValue <= 100_000 else {
            return try stringValue(element, kAXValueAttribute)
        }
        var range = CFRange(location: 0, length: count.intValue)
        guard let parameter = AXValueCreate(.cfRange, &range) else { throw AccessibilityError.unavailable }
        var rawText: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element,
                                                         kAXStringForRangeParameterizedAttribute as CFString,
                                                         parameter, &rawText) == .success,
              let text = rawText as? String else {
            return try stringValue(element, kAXValueAttribute)
        }
        return text
    }

    static func isSettable(_ element: AXUIElement, _ key: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, key as CFString, &settable) == .success && settable.boolValue
    }

    static func bounds(of element: AXUIElement) -> CGRect? {
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
        let currentSource = try AccessibilityField.fullText(of: element)
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

        if AccessibilityField.isSettable(element, kAXValueAttribute) {
            guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, replacement as CFString) == .success else {
                throw AccessibilityError.writeFailed
            }
        } else if AccessibilityField.isSettable(element, kAXSelectedTextRangeAttribute),
                  AccessibilityField.isSettable(element, kAXSelectedTextAttribute) {
            var range = CFRange(location: 0, length: (source as NSString).length)
            guard let value = AXValueCreate(.cfRange, &range),
                  AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success,
                  AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFString) == .success else {
                throw AccessibilityError.writeFailed
            }
        } else {
            throw AccessibilityError.unsupportedWrite
        }
        guard try AccessibilityField.fullText(of: element) == replacement else {
            throw AccessibilityError.writeFailed
        }
    }
}
