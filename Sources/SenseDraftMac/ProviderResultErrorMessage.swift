import SenseDraftCore

enum ProviderResultErrorMessage {
    static func describe(_ error: Error, provider: String) -> String {
        if provider == "Kimi",
           case let ChatCompletionsProviderError.httpStatus(status, type, _) = error {
            return ProviderHTTPStatusMessage.forConnectionCheck(status, kimiErrorType: type)
        }
        return String(describing: error)
    }
}
