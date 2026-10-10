import Foundation

public protocol LanguageService: Sendable {
    func analyze(_ input: AnalysisInput) async throws -> AnalysisResult
}

public enum AnalysisPrompt {
    public static func instructions(for input: AnalysisInput) -> String {
        let base = """
        Decide whether a change is worth suggesting. If the source is already natural, clear \(input.locale) English, set worthChanging to false and return the original English exactly. Otherwise set worthChanging to true and improve grammar, clarity, tone, or idiomatic phrasing only where the gain is meaningful. Preserve intended meaning, names, numbers, commitments, and uncertainty. Do not invent facts or strengthen promises. Return the English, a faithful Chinese interpretation of it, an ambiguity note only when the source can reasonably mean different things, and a brief reason for the decision.
        """
        guard let chinese = input.chineseIntent?.trimmingCharacters(in: .whitespacesAndNewlines), !chinese.isEmpty else {
            return base
        }
        return base + "\nTreat this authoritative Chinese intention as the intended meaning: \(chinese). Where it conflicts with the original English, follow the Chinese intention."
    }
}
