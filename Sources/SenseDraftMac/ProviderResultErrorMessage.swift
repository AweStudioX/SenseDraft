import Foundation
import SenseDraftCore

enum ProviderResultErrorMessage {
    static func describe(_ error: Error, provider: String) -> String {
        if let error = error as? AnalysisError {
            switch error {
            case .inconsistentNoChange:
                return "The service marked this as unchanged but returned different English. Try Regenerate."
            case .blankSource, .blankEnglish, .blankMeaning:
                return "The service returned an incomplete result. Try Regenerate."
            }
        }
        if let error = error as? ChatCompletionsProviderError {
            switch error {
            case .missingKey:
                return "Add a \(provider) API key in Settings → AI Services."
            case let .httpStatus(status, type, _):
                return ProviderHTTPStatusMessage.forConnectionCheck(status,
                    kimiErrorType: provider == "Kimi" ? type : nil)
            case .incomplete:
                return "\(provider) returned an incomplete result. Try Regenerate."
            case .invalidResponse:
                return "\(provider) returned an unreadable result. Try Regenerate."
            }
        }
        if let error = error as? OpenAIProviderError {
            switch error {
            case .missingKey:
                return "Add an OpenAI API key in Settings → AI Services."
            case let .httpStatus(status):
                return ProviderHTTPStatusMessage.forConnectionCheck(status)
            case .incomplete:
                return "OpenAI returned an incomplete result. Try Regenerate."
            case .invalidResponse:
                return "OpenAI returned an unreadable result. Try Regenerate."
            }
        }
        if error is URLError {
            return "Could not reach \(provider). Check your connection and try Regenerate."
        }
        return "\(provider) analysis failed. Try Regenerate."
    }
}
