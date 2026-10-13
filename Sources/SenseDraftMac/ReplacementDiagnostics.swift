import Foundation
import OSLog

/// Replacement trace for diagnosing editor integration without recording text,
/// clipboard contents, prompts, account details, or window titles.
@MainActor
enum ReplacementDiagnostics {
    private static let logger = Logger(subsystem: "com.kaaaaai.SenseDraft", category: "replacement")
    private static var activeAttempt: String?
    private static var lastStage = "idle"

    static func ready() {
        logger.notice("replacement diagnostics ready")
    }

    static func begin(route: String) {
        activeAttempt = String(UUID().uuidString.prefix(8))
        lastStage = "begin"
        logger.notice("attempt=\(activeAttempt ?? "none", privacy: .public) stage=begin route=\(route, privacy: .public)")
    }

    static func stage(_ name: String) {
        guard let activeAttempt else { return }
        lastStage = name
        logger.notice("attempt=\(activeAttempt, privacy: .public) stage=\(name, privacy: .public)")
    }

    static func finish(error: Error? = nil) {
        guard let activeAttempt else { return }
        if let error {
            let code = (error is KeyboardFieldError || error is AccessibilityError)
                ? String(describing: error) : String(describing: type(of: error))
            logger.error("attempt=\(activeAttempt, privacy: .public) stage=\(lastStage, privacy: .public) outcome=failed code=\(code, privacy: .public)")
        } else {
            logger.notice("attempt=\(activeAttempt, privacy: .public) outcome=verified")
        }
        self.activeAttempt = nil
        lastStage = "idle"
    }
}
