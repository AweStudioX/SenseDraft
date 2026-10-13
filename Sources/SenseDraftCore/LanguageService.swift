import Foundation

public protocol LanguageService: Sendable {
    func analyze(_ input: AnalysisInput) async throws -> AnalysisResult
}

public enum AnalysisPrompt {
    public static func instructions(for input: AnalysisInput) -> String {
        let base = input.containsChinese ? """
        Translate the Chinese source into natural, idiomatic \(input.locale) English. If the source mixes Chinese and English, retain the meaning of both. Set worthChanging to true because the source contains Chinese. Preserve intended meaning, names, numbers, commitments, and uncertainty. Do not invent facts or strengthen promises. Return the English, a faithful Chinese interpretation of the English so the user can check its meaning, an ambiguity note only when the source can reasonably mean different things, and a brief reason for the wording choice. When context is missing, avoid guessing details.
        """ : """
        Decide whether a change is worth suggesting. If the source is already natural, clear \(input.locale) English, set worthChanging to false and return the original English exactly. Otherwise set worthChanging to true and improve grammar, clarity, tone, or idiomatic phrasing only where the gain is meaningful. Prefer expressions people actually use in \(input.locale) English over stiff or translated-sounding wording. Preserve intended meaning, names, numbers, commitments, and uncertainty. Do not invent facts or strengthen promises. Return the English, a faithful Chinese interpretation of it, an ambiguity note only when the source can reasonably mean different things, and a brief reason for the decision.
        """
        let style: String
        switch input.preferences.style {
        case .natural:
            style = "Use natural, idiomatic everyday wording without sounding overly formal or slangy."
        case .casual:
            style = "Use concise, conversational wording suitable for a friendly chat; avoid stiff formality."
        case .professional:
            style = "Use clear, warm workplace wording without sounding ceremonial or verbose."
        }
        let capitalization: String
        switch input.preferences.openingCase {
        case .matchInput:
            capitalization = input.containsChinese
                ? "Use standard capitalization for the suggested English."
                : "Match the source's opening capitalization style. If the source starts lowercase, keep the suggested English lowercase when stylistically appropriate; still capitalize proper names and the pronoun I."
        case .lowercase:
            capitalization = "Start the suggested English with a lowercase letter when grammatically possible, even if the source starts uppercase. Still capitalize proper names and the pronoun I."
        case .standard:
            capitalization = "Use standard capitalization for the suggested English."
        }
        var instructions = base + "\n" + style + " " + capitalization
        instructions += "\nPreserve intentional abbreviations and shorthand already present in the source, such as 'pls', when their meaning is clear and they fit the context. Do not expand them solely to sound more formal. Do not add emphasis or details that are absent from the source."
        if input.preferences.useNaturalAbbreviations {
            instructions += "\nYou may use common, unambiguous English contractions and chat abbreviations only when they fit the source's tone and locale. Keep the sentence natural and readable; avoid obscure slang, ambiguous abbreviations, and forced shortening."
        }
        let custom = input.preferences.customInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            instructions += "\nUser writing preference (apply only when consistent with the original meaning and facts): \(custom)"
        }
        if let chinese = input.chineseIntent?.trimmingCharacters(in: .whitespacesAndNewlines), !chinese.isEmpty {
            instructions += "\nTreat this authoritative Chinese intention as the intended meaning: \(chinese). Where it conflicts with the original source, follow the Chinese intention."
        }
        return instructions
    }
}
