import Foundation

public enum WritingStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case natural
    case casual
    case professional

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .natural: "Natural"
        case .casual: "Casual"
        case .professional: "Professional"
        }
    }
}

public enum OpeningCase: String, CaseIterable, Codable, Identifiable, Sendable {
    case matchInput
    case lowercase
    case standard

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .matchInput: "Match input"
        case .lowercase: "Lowercase"
        case .standard: "Standard"
        }
    }
}

public struct WritingPreferences: Codable, Equatable, Sendable {
    public var style: WritingStyle
    public var openingCase: OpeningCase
    public var customInstruction: String
    public var useNaturalAbbreviations: Bool

    public init(style: WritingStyle = .natural,
                openingCase: OpeningCase = .matchInput,
                customInstruction: String = "",
                useNaturalAbbreviations: Bool = false) {
        self.style = style
        self.openingCase = openingCase
        self.customInstruction = String(customInstruction.prefix(240))
        self.useNaturalAbbreviations = useNaturalAbbreviations
    }

    private enum CodingKeys: String, CodingKey {
        case style, openingCase, customInstruction, useNaturalAbbreviations
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(style: try values.decode(WritingStyle.self, forKey: .style),
                  openingCase: try values.decode(OpeningCase.self, forKey: .openingCase),
                  customInstruction: try values.decode(String.self, forKey: .customInstruction),
                  useNaturalAbbreviations: try values.decodeIfPresent(Bool.self, forKey: .useNaturalAbbreviations) ?? false)
    }
}

public enum AnalysisError: Error, Equatable {
    case blankSource
    case blankEnglish
    case blankMeaning
    case inconsistentNoChange
}

public struct AnalysisInput: Equatable, Sendable {
    public let source: String
    public let locale: String
    public let chineseIntent: String?
    public let preferences: WritingPreferences

    public var containsChinese: Bool {
        source.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x9FFF, 0xF900...0xFAFF: true
            default: false
            }
        }
    }

    public init(source: String, locale: String, chineseIntent: String?,
                preferences: WritingPreferences = WritingPreferences()) throws {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalysisError.blankSource
        }
        self.source = source
        self.locale = locale
        self.chineseIntent = chineseIntent
        self.preferences = preferences
    }
}

public struct AnalysisResult: Equatable, Sendable {
    public let english: String
    public let chineseMeaning: String
    public let ambiguity: String?
    public let worthChanging: Bool
    public let reason: String?

    public init(english: String, chineseMeaning: String, ambiguity: String?, worthChanging: Bool = true, reason: String? = nil, source: String? = nil) throws {
        guard !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalysisError.blankEnglish
        }
        guard !chineseMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalysisError.blankMeaning
        }
        if !worthChanging, let source, english != source { throw AnalysisError.inconsistentNoChange }
        self.english = english
        self.chineseMeaning = chineseMeaning
        self.ambiguity = ambiguity?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.worthChanging = worthChanging
        self.reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
