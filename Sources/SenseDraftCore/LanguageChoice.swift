public enum LanguageChoice: String, CaseIterable, Identifiable, Sendable {
    case englishUS = "en-US"
    case englishUK = "en-GB"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case french = "fr-FR"
    case german = "de-DE"
    case spanish = "es-ES"
    case portuguese = "pt-BR"
    case italian = "it-IT"
    case russian = "ru-RU"

    public static let defaultTarget: Self = .englishUS
    public static let defaultReference: Self = .chineseSimplified
    public static let primaryTargets: [Self] = [
        .englishUS, .englishUK, .chineseSimplified, .japanese, .korean, .spanish
    ]
    public static let primaryReferences: [Self] = [
        .chineseSimplified, .englishUS, .englishUK, .japanese, .korean, .spanish
    ]
    public static var moreTargets: [Self] {
        allCases.filter { !primaryTargets.contains($0) }
    }
    public static var moreReferences: [Self] {
        allCases.filter { !primaryReferences.contains($0) }
    }
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .englishUS: "English (US)"
        case .englishUK: "English (UK)"
        case .chineseSimplified: "简体中文"
        case .chineseTraditional: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .portuguese: "Português (Brasil)"
        case .italian: "Italiano"
        case .russian: "Русский"
        }
    }

    public var promptName: String {
        switch self {
        case .englishUS: "US English"
        case .englishUK: "UK English"
        case .chineseSimplified: "Simplified Chinese"
        case .chineseTraditional: "Traditional Chinese"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .french: "French"
        case .german: "German"
        case .spanish: "Spanish"
        case .portuguese: "Brazilian Portuguese"
        case .italian: "Italian"
        case .russian: "Russian"
        }
    }

    public var isEnglish: Bool { self == .englishUS || self == .englishUK }
}
