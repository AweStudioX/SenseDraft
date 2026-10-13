import AppKit
import ApplicationServices
import SenseDraftCore

enum KeyboardFieldError: Error {
    case noTarget
    case notFrontmost
    case windowUnavailable
    case unsupportedFocus
    case clipboardUnavailable
    case clipboardChanged
    case copyFailed
    case tooLong
    case eventFailed
    case eventCreationFailed
    case stale
    case focusRestoreFailed
    case windowChanged
    case focusedFieldChanged
    case sourceChanged
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

    static func capture(frontmostPID: pid_t, expectedElement: AXUIElement? = nil) async throws -> KeyboardField {
        guard AXIsProcessTrusted() else { throw AccessibilityError.permissionDenied }
        guard frontmostPID != ProcessInfo.processInfo.processIdentifier,
              isActiveTarget(frontmostPID) else {
            throw KeyboardFieldError.notFrontmost
        }
        guard let appID = NSRunningApplication(processIdentifier: frontmostPID)?.bundleIdentifier else {
            throw KeyboardFieldError.noTarget
        }
        let focused = focusedElement(of: frontmostPID)
        if let expectedElement {
            guard let focused,
                  sameTarget(focused, expectedElement) else { throw KeyboardFieldError.focusedFieldChanged }
        }
        guard let window = resolvedWindow(of: frontmostPID, focusedElement: focused) else {
            throw KeyboardFieldError.windowUnavailable
        }
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
                                        bounds: focused.flatMap(AccessibilityField.bounds(of:))
                                            ?? AccessibilityField.bounds(of: window), selection: selection)
        try provisional.checkTarget()
        let clipboard = try ClipboardSnapshot.capture()
        let previousChangeCount = NSPasteboard.general.changeCount
        do {
            ReplacementDiagnostics.stage("captureCopyBegin")
            let copied = try await provisional.selectAllAndCopy()
            ReplacementDiagnostics.stage("captureCopied")
            guard clipboard.restore(ifCurrent: copied.changeCount) else {
                throw KeyboardFieldError.clipboardChanged
            }
            provisional.restoreSelection()
            ReplacementDiagnostics.stage("captureSelectionRestored")
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

    static func replacementTarget(frontmostPID: pid_t, expectedElement: AXUIElement,
                                  source: String) throws -> KeyboardField {
        guard AXIsProcessTrusted() else { throw AccessibilityError.permissionDenied }
        guard isActiveTarget(frontmostPID),
              let focused = focusedElement(of: frontmostPID),
              sameTarget(focused, expectedElement) else {
            throw KeyboardFieldError.focusedFieldChanged
        }
        guard let appID = NSRunningApplication(processIdentifier: frontmostPID)?.bundleIdentifier,
              let window = resolvedWindow(of: frontmostPID, focusedElement: focused) else {
            throw KeyboardFieldError.windowUnavailable
        }
        let title = try? AccessibilityField.stringValue(window, kAXTitleAttribute)
        return KeyboardField(pid: frontmostPID, appID: appID, window: window,
                             focusedElement: focused, windowTitle: title, source: source,
                             bounds: AccessibilityField.bounds(of: focused),
                             selection: selectedRange(of: focused))
    }

    func replaceIfUnchanged(with replacement: String,
                            sourceFromAccessibility: Bool = false) async throws {
        try checkTarget()
        let clipboard = try ClipboardSnapshot.capture()
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        var ownedChangeCount: Int?
        var didPaste = false
        var selectedAfterPaste = false
        defer {
            if let ownedChangeCount {
                _ = clipboard.restore(ifCurrent: ownedChangeCount)
            } else if pasteboard.changeCount == previousChangeCount + 1 {
                _ = clipboard.restore(ifCurrent: pasteboard.changeCount)
            }
            if (!didPaste || selectedAfterPaste),
               (try? checkTarget(allowTitleChange: didPaste)) != nil {
                restoreSelection(afterReplacement: didPaste)
            }
        }
        ReplacementDiagnostics.stage("sourceCopyBegin")
        let copied = try await selectAllAndCopy()
        ReplacementDiagnostics.stage("sourceCopied")
        ownedChangeCount = copied.changeCount
        let sourceMatches = sourceFromAccessibility
            ? EditorTextEquivalence.matchesAccessibilityAndCopy(accessibility: source,
                                                                copied: copied.text)
            : copied.text == source
        guard sourceMatches else { throw KeyboardFieldError.sourceChanged }
        ReplacementDiagnostics.stage("sourceMatched")
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
        ReplacementDiagnostics.stage("pastePosted")
        // Rich Electron editors may apply Paste asynchronously. Reading their AX
        // value does not disturb the selection or cancel a pending paste event.
        if let focusedElement,
           (try? AccessibilityField.fullText(of: focusedElement)) != nil {
            for attempt in 0..<30 {
                try checkTarget(allowTitleChange: true)
                if let observed = try? AccessibilityField.fullText(of: focusedElement),
                   EditorTextEquivalence.matchesAccessibilityAndCopy(accessibility: observed,
                                                                     copied: replacement) {
                    ReplacementDiagnostics.stage("passiveReadbackMatched")
                    return
                }
                if attempt < 29 { try await Task.sleep(for: .milliseconds(50)) }
            }
        } else {
            // Keyboard-only editors cannot be read passively. Give their paste
            // handler time to finish before Select All / Copy verifies the result.
            try await Task.sleep(for: .milliseconds(400))
            try checkTarget(allowTitleChange: true)
        }
        selectedAfterPaste = true
        ReplacementDiagnostics.stage("fallbackCopyBegin")
        let verification = try await selectAllAndCopy(allowTitleChange: true)
        ownedChangeCount = verification.changeCount
        guard verification.text == replacement else { throw KeyboardFieldError.writeUnverified }
        ReplacementDiagnostics.stage("fallbackCopyMatched")
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
        guard Self.isActiveTarget(pid) else { throw KeyboardFieldError.notFrontmost }
        let currentFocused = Self.focusedElement(of: pid)
        guard let currentWindow = Self.resolvedWindow(of: pid, focusedElement: currentFocused),
              Self.sameTarget(currentWindow, window),
              (allowTitleChange || (try? AccessibilityField.stringValue(currentWindow, kAXTitleAttribute)) == windowTitle) else {
            throw KeyboardFieldError.windowChanged
        }
        if let focusedElement {
            guard let currentFocused, Self.sameTarget(currentFocused, focusedElement) else {
                throw KeyboardFieldError.focusedFieldChanged
            }
        } else if currentFocused != nil {
            throw KeyboardFieldError.focusedFieldChanged
        }
    }

    private static func resolvedWindow(of pid: pid_t, focusedElement: AXUIElement?) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        return attributeElement(of: application, name: kAXFocusedWindowAttribute)
            ?? focusedElement.flatMap { attributeElement(of: $0, name: kAXWindowAttribute) }
            ?? attributeElement(of: application, name: kAXMainWindowAttribute)
    }

    static func focusedElement(of pid: pid_t) -> AXUIElement? {
        if let element = attributeElement(of: AXUIElementCreateApplication(pid), name: kAXFocusedUIElementAttribute) {
            return element
        }
        let system = AXUIElementCreateSystemWide()
        guard let element = attributeElement(of: system, name: kAXFocusedUIElementAttribute),
              processID(of: element) == pid else { return nil }
        return element
    }

    static func isActiveTarget(_ pid: pid_t) -> Bool {
        let system = AXUIElementCreateSystemWide()
        if let focusedApp = attributeElement(of: system, name: kAXFocusedApplicationAttribute),
           let focusedPID = processID(of: focusedApp) {
            return focusedPID == pid
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    static func sameTarget(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        if CFEqual(lhs, rhs) { return true }
        guard let lhsPID = processID(of: lhs), lhsPID == processID(of: rhs),
              let lhsRole = try? AccessibilityField.stringValue(lhs, kAXRoleAttribute),
              lhsRole == (try? AccessibilityField.stringValue(rhs, kAXRoleAttribute)),
              let first = AccessibilityField.bounds(of: lhs),
              let second = AccessibilityField.bounds(of: rhs) else { return false }
        return abs(first.minX - second.minX) < 3 && abs(first.minY - second.minY) < 3
            && abs(first.width - second.width) < 3 && abs(first.height - second.height) < 3
    }

    private static func processID(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
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
    static func press(key: CGKeyCode, command: Bool) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else {
            throw KeyboardFieldError.eventCreationFailed
        }
        if command {
            down.flags = .maskCommand
            up.flags = .maskCommand
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func click(_ point: CGPoint) throws {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left) else {
            throw KeyboardFieldError.eventCreationFailed
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
        case .accessibility(let field):
            FieldPolicy.needsFormattingConfirmation(capturedWithKeyboard: false,
                                                     hasMixedFormatting: field.richTextRisk)
        case .keyboard:
            FieldPolicy.needsFormattingConfirmation(capturedWithKeyboard: true,
                                                     hasMixedFormatting: false)
        }
    }

    var usedKeyboardFallback: Bool {
        switch self {
        case .accessibility(let field): FieldPolicy.replacementMethod(role: field.role) == .verifiedKeyboard
        case .keyboard: true
        }
    }

    func replaceIfUnchanged(with replacement: String) async throws {
        switch self {
        case .accessibility(let field):
            if FieldPolicy.replacementMethod(role: field.role) == .verifiedKeyboard {
                ReplacementDiagnostics.stage("focusRestoreBegin")
                let focused = try await restoreFocusForKeyboardReplacement(field)
                ReplacementDiagnostics.stage("focusRestored")
                let keyboard = try KeyboardField.replacementTarget(frontmostPID: field.pid,
                                                                   expectedElement: focused,
                                                                   source: field.source)
                ReplacementDiagnostics.stage("replacementTargetReady")
                try await keyboard.replaceIfUnchanged(with: replacement,
                                                      sourceFromAccessibility: true)
            } else {
                try await field.replaceIfUnchanged(with: replacement)
            }
        case .keyboard(let field): try await field.replaceIfUnchanged(with: replacement)
        }
    }

    private func restoreFocusForKeyboardReplacement(_ field: CapturedField) async throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw AccessibilityError.permissionDenied }
        var elementPID: pid_t = 0
        guard AXUIElementGetPid(field.element, &elementPID) == .success,
              elementPID == field.pid else {
            throw KeyboardFieldError.focusRestoreFailed
        }
        if !KeyboardField.isActiveTarget(field.pid) {
            guard let app = NSRunningApplication(processIdentifier: field.pid),
                  app.activate(options: []) else {
                throw KeyboardFieldError.notFrontmost
            }
            ReplacementDiagnostics.stage("targetActivationRequested")
            _ = AXUIElementSetAttributeValue(field.element, kAXFocusedAttribute as CFString,
                                             kCFBooleanTrue)
        }
        for attempt in 0..<8 {
            if KeyboardField.isActiveTarget(field.pid),
               let focused = KeyboardField.focusedElement(of: field.pid),
               matchesCapturedField(focused, field) {
                ReplacementDiagnostics.stage("focusMatchedPassively")
                return focused
            }
            if attempt < 7 { try await Task.sleep(for: .milliseconds(50)) }
        }
        guard let originalBounds = field.bounds,
              KeyboardField.isActiveTarget(field.pid),
              let currentBounds = AccessibilityField.bounds(of: field.element),
              boundsMatch(originalBounds, currentBounds) else {
            throw KeyboardFieldError.focusRestoreFailed
        }
        try KeyboardEvent.click(CGPoint(x: currentBounds.midX, y: currentBounds.midY))
        ReplacementDiagnostics.stage("focusClickPosted")
        for attempt in 0..<20 {
            if KeyboardField.isActiveTarget(field.pid),
               let focused = KeyboardField.focusedElement(of: field.pid),
               matchesCapturedField(focused, field) {
                ReplacementDiagnostics.stage("focusMatchedAfterClick")
                return focused
            }
            if attempt < 19 { try await Task.sleep(for: .milliseconds(50)) }
        }
        throw KeyboardFieldError.focusRestoreFailed
    }

    private func matchesCapturedField(_ focused: AXUIElement, _ field: CapturedField) -> Bool {
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success,
              focusedPID == field.pid,
              (try? AccessibilityField.stringValue(focused, kAXRoleAttribute)) == field.role,
              let currentSource = try? AccessibilityField.fullText(of: focused),
              EditorTextEquivalence.matchesAccessibilityValues(currentSource, field.source) else { return false }
        if CFEqual(focused, field.element) { return true }
        guard let originalBounds = field.bounds,
              let currentBounds = AccessibilityField.bounds(of: focused) else { return false }
        return boundsMatch(originalBounds, currentBounds)
    }

    private func boundsMatch(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) < 3 && abs(first.minY - second.minY) < 3
            && abs(first.width - second.width) < 3 && abs(first.height - second.height) < 3
    }
}
