import AppKit
import Carbon
import Foundation
import SenseDraftCore

enum HotkeyRegistrationError: Error {
    case eventHandler(OSStatus)
    case analyze(OSStatus)
    case replace(OSStatus)
}

@MainActor
final class GlobalHotkeys {
    private var handlerRef: EventHandlerRef?
    private var analyzeRef: EventHotKeyRef?
    private var replaceRef: EventHotKeyRef?
    private var pressedIDs: Set<UInt32> = []
    private var pendingAnalyzePID: pid_t?
    private let onAnalyze: (pid_t?) -> Void
    private let onReplace: () -> Void

    init(settings: HotkeySettings, onAnalyze: @escaping (pid_t?) -> Void, onReplace: @escaping () -> Void) throws {
        self.onAnalyze = onAnalyze
        self.onReplace = onReplace
        try register(settings)
    }

    func register(_ settings: HotkeySettings) throws {
        unregister()
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = eventTypes.withUnsafeMutableBufferPointer { buffer in
            InstallEventHandler(GetApplicationEventTarget(), Self.eventHandler, buffer.count,
                                buffer.baseAddress, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        }
        guard status == noErr else { throw HotkeyRegistrationError.eventHandler(status) }

        let analyzeID = EventHotKeyID(signature: OSType(0x53445246), id: 1)
        let analyzeStatus = RegisterEventHotKey(settings.analyze.keyCode, settings.analyze.modifiers, analyzeID, GetApplicationEventTarget(), 0, &analyzeRef)
        guard analyzeStatus == noErr else {
            unregister()
            throw HotkeyRegistrationError.analyze(analyzeStatus)
        }
        let replaceID = EventHotKeyID(signature: OSType(0x53445246), id: 2)
        let replaceStatus = RegisterEventHotKey(settings.replace.keyCode, settings.replace.modifiers, replaceID, GetApplicationEventTarget(), 0, &replaceRef)
        guard replaceStatus == noErr else {
            unregister()
            throw HotkeyRegistrationError.replace(replaceStatus)
        }
    }

    func unregister() {
        if let analyzeRef { UnregisterEventHotKey(analyzeRef) }
        if let replaceRef { UnregisterEventHotKey(replaceRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        analyzeRef = nil
        replaceRef = nil
        handlerRef = nil
        pressedIDs.removeAll()
        pendingAnalyzePID = nil
    }

    private func fire(id: UInt32, kind: UInt32) {
        if kind == UInt32(kEventHotKeyPressed) {
            pressedIDs.insert(id)
            if id == 1 { pendingAnalyzePID = NSWorkspace.shared.frontmostApplication?.processIdentifier }
        } else if kind == UInt32(kEventHotKeyReleased), pressedIDs.remove(id) != nil {
            if id == 1 {
                onAnalyze(pendingAnalyzePID)
                pendingAnalyzePID = nil
            } else if id == 2 {
                onReplace()
            }
        }
    }

    private static let eventHandler: EventHandlerUPP = { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
        guard status == noErr else { return status }
        let instance = Unmanaged<GlobalHotkeys>.fromOpaque(context).takeUnretainedValue()
        let id = hotkeyID.id
        let kind = GetEventKind(event)
        // The Carbon application event target runs on the main event loop. Capture
        // focus before returning to it, while the source app still owns focus.
        if Thread.isMainThread {
            MainActor.assumeIsolated { instance.fire(id: id, kind: kind) }
        } else {
            DispatchQueue.main.async { @MainActor in instance.fire(id: id, kind: kind) }
        }
        return noErr
    }
}
