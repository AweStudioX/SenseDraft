import Foundation

public enum AnalysisError: Error, Equatable {
    case blankSource
    case blankEnglish
    case blankMeaning
}

public struct AnalysisInput: Equatable, Sendable {
    public let source: String
    public let locale: String
    public let chineseIntent: String?

    public init(source: String, locale: String, chineseIntent: String?) throws {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalysisError.blankSource
        }
        self.source = source
        self.locale = locale
        self.chineseIntent = chineseIntent
    }
}

public struct AnalysisResult: Equatable, Sendable {
    public let english: String
    public let chineseMeaning: String
    public let ambiguity: String?

    public init(english: String, chineseMeaning: String, ambiguity: String?) throws {
        guard !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalysisError.blankEnglish
        }
        guard !chineseMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalysisError.blankMeaning
        }
        self.english = english
        self.chineseMeaning = chineseMeaning
        self.ambiguity = ambiguity?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
