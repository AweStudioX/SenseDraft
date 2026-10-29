public enum ProviderHTTPStatusMessage {
    public static func forConnectionCheck(_ code: Int, kimiErrorType: String? = nil) -> String {
        switch code {
        case 401, 403:
            "HTTP \(code). Check the API key and region."
        case 400, 404:
            "HTTP \(code). Check the model and API region."
        case 429:
            switch kimiErrorType {
            case "exceeded_current_quota_error":
                "HTTP 429. Kimi API balance or quota exhausted; check platform billing and usage."
            case "rate_limit_reached_error":
                "HTTP 429. Kimi rate limit reached; wait and check your account limits."
            case "engine_overloaded_error":
                "HTTP 429. Kimi service is overloaded; try again later."
            default:
                "HTTP 429. Rate limit or quota reached; check usage or try again later."
            }
        case 500...599:
            "HTTP \(code). The provider is temporarily unavailable; try again later."
        default:
            "HTTP \(code). The provider rejected the request."
        }
    }
}
