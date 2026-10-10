import AppKit
import Carbon

public enum ShortcutLabel {
    public static func describe(_ shortcut: Shortcut) -> String {
        var label = ""
        if shortcut.modifiers & UInt32(controlKey) != 0 { label += "⌃" }
        if shortcut.modifiers & UInt32(optionKey) != 0 { label += "⌥" }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { label += "⇧" }
        if shortcut.modifiers & UInt32(cmdKey) != 0 { label += "⌘" }
        return label + keyName(shortcut.keyCode)
    }

    public static func keyName(_ code: UInt32) -> String {
        if let name = fixedNames[code] { return name }
        guard code <= UInt16.max,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                           timestamp: 0, windowNumber: 0, context: nil,
                                           characters: "", charactersIgnoringModifiers: "",
                                           isARepeat: false, keyCode: UInt16(code)),
              let characters = event.characters(byApplyingModifiers: []),
              !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return "Key \(code)" }
        return characters.uppercased()
    }

    // Non-printable keys use stable names. Key 50 keeps the familiar tilde
    // keycap label; other printable keys use the active macOS keyboard layout.
    private static let fixedNames: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "Space", 50: "~", 51: "⌫", 53: "⎋",
        54: "Right Command", 55: "Command", 56: "Shift", 57: "Caps Lock",
        58: "Option", 59: "Control", 60: "Right Shift", 61: "Right Option",
        62: "Right Control", 63: "Fn",
        64: "F17", 72: "Volume Up", 73: "Volume Down", 74: "Mute",
        79: "F18", 80: "F19", 90: "F20",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
        110: "Menu", 111: "F12", 113: "F15", 114: "Help",
        115: "Home", 116: "Page Up", 117: "⌦", 118: "F4", 119: "End",
        120: "F2", 121: "Page Down", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        65: "Keypad .", 67: "Keypad ×", 69: "Keypad +", 71: "Keypad Clear",
        75: "Keypad /", 76: "Keypad ↩", 78: "Keypad -", 81: "Keypad =",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3",
        86: "Keypad 4", 87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7",
        91: "Keypad 8", 92: "Keypad 9", 95: "Keypad ,",
        102: "英数", 104: "かな"
    ]
}
