import Foundation
import FoundationModels
import SenseDraftCore

enum AppleLocalProviderError: LocalizedError {
    case unavailable
    case unsupportedLanguage
    case contextTooLong

    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple's on-device model is unavailable. Check Apple Intelligence in System Settings."
        case .unsupportedLanguage: "Apple's on-device model does not support one of the selected languages."
        case .contextTooLong: "This text exceeds Apple's on-device context limit. Use a shorter selection or another service."
        }
    }
}

struct AppleLocalProvider: LanguageService {
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    static var availabilityDescription: String {
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return "Ready on this Mac"
            case .unavailable(.deviceNotEligible): return "This Mac does not support Apple Intelligence"
            case .unavailable(.modelNotReady): return "Apple Intelligence model is not ready"
            case .unavailable: return "Apple Intelligence is unavailable"
            }
        }
        return "Requires macOS 26 or later"
    }

    func analyze(_ input: AnalysisInput) async throws -> AnalysisResult {
        guard #available(macOS 26.0, *) else { throw AppleLocalProviderError.unavailable }
        let model = SystemLanguageModel.default
        guard model.isAvailable else { throw AppleLocalProviderError.unavailable }
        guard model.supportsLocale(Locale(identifier: input.locale)),
              model.supportsLocale(Locale(identifier: input.referenceLocale)) else {
            throw AppleLocalProviderError.unsupportedLanguage
        }
        let session = LanguageModelSession(model: model, instructions: AnalysisPrompt.instructions(for: input))
        let response: LanguageModelSession.Response<AppleAnalysisPayload>
        do {
            response = try await session.respond(to: AnalysisPrompt.userMessage(for: input),
                                                    generating: AppleAnalysisPayload.self)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw AppleLocalProviderError.contextTooLong
        }
        let payload = response.content
        return try AnalysisResult(english: payload.english, chineseMeaning: payload.chineseMeaning,
                                  ambiguity: payload.ambiguity, worthChanging: payload.worthChanging,
                                  reason: payload.reason, source: input.source)
    }
}

@available(macOS 26.0, *)
@Generable
private struct AppleAnalysisPayload {
    @Guide(description: "Suggested text in the target language")
    var english: String
    @Guide(description: "Meaning check in the reference language")
    var chineseMeaning: String
    @Guide(description: "Any unresolved ambiguity, or nil")
    var ambiguity: String?
    @Guide(description: "Whether the suggested text meaningfully changes the original")
    var worthChanging: Bool
    @Guide(description: "Brief reason for the change, or nil")
    var reason: String?
}
