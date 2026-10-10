import Foundation

public protocol LanguageService: Sendable {
    func analyze(_ input: AnalysisInput) async throws -> AnalysisResult
}

public enum AnalysisPrompt {
    public static func instructions(for input: AnalysisInput) -> String {
        let base = """
        Improve the source as natural \(input.locale) English. Preserve its intended meaning, names, numbers, commitments, and uncertainty. Do not invent facts or strengthen promises. Return improved English, a faithful Chinese interpretation of that English, and an ambiguity note only when the source can reasonably mean different things.
        """
        guard let chinese = input.chineseIntent?.trimmingCharacters(in: .whitespacesAndNewlines), !chinese.isEmpty else {
            return base
        }
        return base + "\nTreat this authoritative Chinese intention as the intended meaning: \(chinese). Where it conflicts with the original English, follow the Chinese intention."
    }
}
