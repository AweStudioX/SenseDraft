public struct Shortcut: Equatable, Codable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public extension Shortcut {
    static let defaultAnalyze = Shortcut(keyCode: 14, modifiers: 2304)
    static let defaultReplace = Shortcut(keyCode: 36, modifiers: 2304)
}

public enum HotkeySettingsError: Error {
    case duplicate
    case missingModifier
}

public struct HotkeySettings: Codable, Sendable {
    public let analyze: Shortcut
    public let replace: Shortcut

    public init(analyze: Shortcut, replace: Shortcut) throws {
        guard analyze != replace else { throw HotkeySettingsError.duplicate }
        let required: UInt32 = 256 | 2048 | 4096
        guard analyze.modifiers & required != 0, replace.modifiers & required != 0 else {
            throw HotkeySettingsError.missingModifier
        }
        self.analyze = analyze
        self.replace = replace
    }
}

public extension HotkeySettings {
    static let defaults = try! HotkeySettings(analyze: .defaultAnalyze, replace: .defaultReplace)
}
