import AppKit
import ApplicationServices
import SenseDraftCore

enum KeyboardFieldError: Error {
    case noTarget
    case unsupportedFocus
    case clipboardUnavailable
    case clipboardChanged
    case copyFailed
    case tooLong
    case eventFailed
    case stale
    case writeUnverified
}

/// A shortcut-only fallback for editors whose text is absent from Accessibility.
/// It uses the editor's own Select All / Copy / Paste commands and never observes
/// typing between shortcuts.
@MainActor
struct KeyboardField {
    let pid: pid_t
    let appID: String
    let window: AXUIElement
    let focusedElement: AXUIElement?
    let windowTitle: String?
    let source: String
    let bounds: CGRect?
    let selection: AXValue?

    static func capture(frontmostPID: pid_t) async throws -> KeyboardField {
        guard AXIsProcessTrusted() else { throw AccessibilityError.permissionDenied }
        guard frontmostPID != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID,
              let appID = NSRunningApplication(processIdentifier: frontmostPID)?.bundleIdentifier,
              let window = focusedWindow(of: frontmostPID) else { throw KeyboardFieldError.noTarget }
        let focused = focusedElement(of: frontmostPID)
        if let focused, !CFEqual(focused, window) {
            let subrole = try? AccessibilityField.stringValue(focused, kAXSubroleAttribute)
            guard subrole != kAXSecureTextFieldSubrole else { throw FieldError.protected }
            let role = try? AccessibilityField.stringValue(focused, kAXRoleAttribute)
            guard role == kAXTextFieldRole || role == kAXTextAreaRole else {
                throw KeyboardFieldError.unsupportedFocus
            }
        }
        let title = try? AccessibilityField.stringValue(window, kAXTitleAttribute)
        let selection = selectedRange(of: focused)
        let provisional = KeyboardField(pid: frontmostPID, appID: appID, window: window,
                                        focusedElement: focused, windowTitle: title, source: "",
                                        bounds: AccessibilityField.bounds(of: window), selection: selection)
        try await KeyboardEvent.waitForShortcutRelease()
        try provisional.checkTarget()
        let clipboard = try ClipboardSnapshot.capture()
        let previousChangeCount = NSPasteboard.general.changeCount
        do {
            let copied = try await provisional.selectAllAndCopy()
            guard clipboard.restore(ifCurrent: copied.changeCount) else {
                throw KeyboardFieldError.clipboardChanged
            }
            provisional.restoreSelection()
            try FieldPolicy.validate(role: kAXTextAreaRole, protected: false, editable: true, value: copied.text)
            return KeyboardField(pid: frontmostPID, appID: appID, window: window,
                                 focusedElement: focused, windowTitle: title, source: copied.text,
                                 bounds: provisional.bounds, selection: selection)
        } catch {
            let currentChangeCount = NSPasteboard.general.changeCount
            if currentChangeCount == previousChangeCount + 1 {
                _ = clipboard.restore(ifCurrent: currentChangeCount)
            }
            if (try? provisional.checkTarget()) != nil { provisional.restoreSelection() }
            throw error
        }
    }

    func replaceIfUnchanged(with replacement: String) async throws {
        try await KeyboardEvent.waitForShortcutRelease()
        try checkTarget()
        let clipboard = try ClipboardSnapshot.capture()
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        var ownedChangeCount: Int?
        var didPaste = false
        defer {
            if let ownedChangeCount {
                _ = clipboard.restore(ifCurrent: ownedChangeCount)
            } else if pasteboard.changeCount == previousChangeCount + 1 {
                _ = clipboard.restore(ifCurrent: pasteboard.changeCount)
            }
            if (try? checkTarget(allowTitleChange: didPaste)) != nil {
                restoreSelection(afterReplacement: didPaste)
            }
        }
        let copied = try await selectAllAndCopy()
        ownedChangeCount = copied.changeCount
        guard copied.text == source else { throw KeyboardFieldError.stale }
        try checkTarget()
        guard pasteboard.changeCount == copied.changeCount else { throw KeyboardFieldError.clipboardChanged }
        pasteboard.clearContents()
        ownedChangeCount = pasteboard.changeCount
        guard pasteboard.setString(replacement, forType: .string) else {
            throw KeyboardFieldError.clipboardUnavailable
        }
        ownedChangeCount = pasteboard.changeCount
        try KeyboardEvent.press(key: 9, command: true) // Paste into the selected source.
        didPaste = true
        try await Task.sleep(for: .milliseconds(120))
        try checkTarget(allowTitleChange: true)
        let verification = try await selectAllAndCopy(allowTitleChange: true)
        ownedChangeCount = verification.changeCount
        guard verification.text == replacement else { throw KeyboardFieldError.writeUnverified }
    }

    private func selectAllAndCopy(allowTitleChange: Bool = false) async throws -> (text: String, changeCount: Int) {
        try checkTarget(allowTitleChange: allowTitleChange)
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        try KeyboardEvent.press(key: 0, command: true) // Select All
        try await Task.sleep(for: .milliseconds(35))
        try checkTarget(allowTitleChange: allowTitleChange)
        try KeyboardEvent.press(key: 8, command: true) // Copy
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(35))
            try checkTarget(allowTitleChange: allowTitleChange)
            if pasteboard.changeCount != previousChangeCount {
                guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
                    throw KeyboardFieldError.copyFailed
                }
                guard text.utf8.count <= 100_000 else { throw KeyboardFieldError.tooLong }
                return (text, pasteboard.changeCount)
            }
        }
        throw KeyboardFieldError.copyFailed
    }

    private func restoreSelection(afterReplacement: Bool = false) {
        if !afterReplacement, let focusedElement, let selection,
           AXUIElementSetAttributeValue(focusedElement,
                                        kAXSelectedTextRangeAttribute as CFString, selection) == .success {
            return
        }
        // All text remains intact; where AX does not expose a selection range,
        // collapse Select All to a caret at the end instead of leaving it armed.
        try? KeyboardEvent.press(key: 124, command: false)
    }

    private func checkTarget(allowTitleChange: Bool = false) throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let currentWindow = Self.focusedWindow(of: pid), CFEqual(currentWindow, window),
              (allowTitleChange || (try? AccessibilityField.stringValue(currentWindow, kAXTitleAttribute)) == windowTitle) else {
            throw KeyboardFieldError.stale
        }
        let currentFocused = Self.focusedElement(of: pid)
        if let focusedElement {
            guard let currentFocused, CFEqual(currentFocused, focusedElement) else {
                throw KeyboardFieldError.stale
            }
        } else if currentFocused != nil {
            throw KeyboardFieldError.stale
        }
    }

    private static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        attributeElement(of: AXUIElementCreateApplication(pid), name: kAXFocusedWindowAttribute)
    }

    private static func focusedElement(of pid: pid_t) -> AXUIElement? {
        attributeElement(of: AXUIElementCreateApplication(pid), name: kAXFocusedUIElementAttribute)
    }

    private static func attributeElement(of parent: AXUIElement, name: String) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, name as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private static func selectedRange(of element: AXUIElement?) -> AXValue? {
        guard let element else { return nil }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXSelectedTextRangeAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        return (raw as! AXValue)
    }
}

@MainActor
struct ClipboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    static func capture(from pasteboard: NSPasteboard = .general) throws -> ClipboardSnapshot {
        let initialChangeCount = pasteboard.changeCount
        var total = 0
        let items = try (pasteboard.pasteboardItems ?? []).map { item in
            let probe = NSPasteboardItem()
            return try item.types.map { type -> (NSPasteboard.PasteboardType, Data) in
                guard let data = item.data(forType: type) else { throw KeyboardFieldError.clipboardUnavailable }
                total += data.count
                guard total <= 32_000_000 else { throw KeyboardFieldError.clipboardUnavailable }
                guard probe.setData(data, forType: type) else { throw KeyboardFieldError.clipboardUnavailable }
                return (type, data)
            }
        }
        guard pasteboard.changeCount == initialChangeCount else { throw KeyboardFieldError.clipboardChanged }
        let snapshot = ClipboardSnapshot(items: items)
        guard snapshot.canRestore else { throw KeyboardFieldError.clipboardUnavailable }
        return snapshot
    }

    func restore(to pasteboard: NSPasteboard = .general, ifCurrent expectedChangeCount: Int) -> Bool {
        guard pasteboard.changeCount == expectedChangeCount,
              let restored = restoredItems() else { return false }
        pasteboard.clearContents()
        return restored.isEmpty || pasteboard.writeObjects(restored)
    }

    private var canRestore: Bool {
        guard let restored = restoredItems() else { return false }
        guard !restored.isEmpty else { return true }
        let probe = NSPasteboard.withUniqueName()
        defer { probe.releaseGlobally() }
        return probe.writeObjects(restored)
    }

    private func restoredItems() -> [NSPasteboardItem]? {
        var restored: [NSPasteboardItem] = []
        for representations in items {
            let item = NSPasteboardItem()
            for (type, data) in representations { guard item.setData(data, forType: type) else { return nil } }
            restored.append(item)
        }
        return restored
    }
}

private enum KeyboardEvent {
    static func waitForShortcutRelease() async throws {
        let shortcutModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        for _ in 0..<20 {
            let held = CGEventSource.flagsState(.combinedSessionState).intersection(shortcutModifiers)
            if held.isEmpty { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw KeyboardFieldError.eventFailed
    }

    static func press(key: CGKeyCode, command: Bool) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else {
            throw KeyboardFieldError.eventFailed
        }
        if command {
            down.flags = .maskCommand
            up.flags = .maskCommand
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

@MainActor
enum CapturedInput {
    case accessibility(CapturedField)
    case keyboard(KeyboardField)

    var source: String {
        switch self {
        case .accessibility(let field): field.source
        case .keyboard(let field): field.source
        }
    }

    var appID: String {
        switch self {
        case .accessibility(let field): field.appID
        case .keyboard(let field): field.appID
        }
    }

    var pid: pid_t {
        switch self {
        case .accessibility(let field): field.pid
        case .keyboard(let field): field.pid
        }
    }

    var bounds: CGRect? {
        switch self {
        case .accessibility(let field): field.bounds
        case .keyboard(let field): field.bounds
        }
    }

    var richTextRisk: Bool {
        switch self {
        case .accessibility(let field): field.richTextRisk
        case .keyboard: true
        }
    }

    var usedKeyboardFallback: Bool {
        if case .keyboard = self { return true }
        return false
    }

    func replaceIfUnchanged(with replacement: String) async throws {
        switch self {
        case .accessibility(let field): try field.replaceIfUnchanged(with: replacement)
        case .keyboard(let field): try await field.replaceIfUnchanged(with: replacement)
        }
    }
}
