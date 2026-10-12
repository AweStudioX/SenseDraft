import AppKit
import SenseDraftCore

@MainActor
final class SenseDraftAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let settings = AppSettings()
    private lazy var settingsWindow = SettingsWindow(settings: settings,
        onSaveShortcuts: { [weak self] in self?.saveShortcuts() },
        onBeginShortcutRecording: { [weak self] in self?.hotkeys?.unregister() },
        onEndShortcutRecording: { [weak self] in self?.resumeShortcuts() })
    private let review = ReviewPanel()
    private var hotkeys: GlobalHotkeys?
    private var activeHotkeys: HotkeySettings?
    private var captured: CapturedInput?
    private var captureTask: Task<Void, Never>?
    private var replaceTask: Task<Void, Never>?
    private var isReplacing = false
    private var session: AnalysisSession?
    private var requestTask: Task<Void, Never>?
    private var keyboardLayoutObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        review.model.onRegenerate = { [weak self] in self?.regenerate() }
        review.model.onCopy = { [weak self] in self?.copyEnglish() }
        review.model.onClose = { [weak self] in self?.review.close() }
        review.onDismiss = { [weak self] in self?.discardSession() }
        keyboardLayoutObserver = NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshShortcutLabels() }
        }
        saveShortcuts()
        if !UserDefaults.standard.bool(forKey: "onboardingShown") {
            UserDefaults.standard.set(true, forKey: "onboardingShown")
            settingsWindow.show(tab: .permissions)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        requestTask?.cancel()
        hotkeys?.unregister()
        if let keyboardLayoutObserver { NotificationCenter.default.removeObserver(keyboardLayoutObserver) }
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "SD"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "SenseDraft Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SenseDraft", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() { settingsWindow.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func saveShortcuts() {
        do {
            let proposed = try HotkeySettings(analyze: settings.analyzeShortcut, replace: settings.replaceShortcut)
            if let hotkeys {
                do { try hotkeys.register(proposed) }
                catch {
                    if let activeHotkeys { try? hotkeys.register(activeHotkeys) }
                    throw error
                }
            } else {
                hotkeys = try GlobalHotkeys(settings: proposed, onAnalyze: { [weak self] pid in self?.analyze(frontmostPID: pid) }, onReplace: { [weak self] in self?.replace() })
            }
            activeHotkeys = proposed
            UserDefaults.standard.set(try JSONEncoder().encode(proposed), forKey: "hotkeys")
            settings.shortcutMessage = "Shortcuts saved."
            review.model.replaceShortcutText = ShortcutLabel.describe(proposed.replace)
        } catch {
            if let activeHotkeys {
                settings.analyzeShortcut = activeHotkeys.analyze
                settings.replaceShortcut = activeHotkeys.replace
            }
            settings.shortcutMessage = "Shortcut unavailable or duplicated: \(error)"
        }
    }

    private func resumeShortcuts() {
        guard let hotkeys, let activeHotkeys else { return }
        do { try hotkeys.register(activeHotkeys) }
        catch { settings.shortcutMessage = "Could not reactivate shortcuts: \(error)" }
    }

    private func refreshShortcutLabels() {
        settings.shortcutDisplayRevision += 1
        if let activeHotkeys {
            review.model.replaceShortcutText = ShortcutLabel.describe(activeHotkeys.replace)
        }
    }

    private func analyze(frontmostPID: pid_t?) {
        guard !isReplacing else { return }
        discardSession()
        review.model.message = ""
        do {
            presentCaptured(.accessibility(try AccessibilityField.captureFocused(frontmostPID: frontmostPID)))
        } catch AccessibilityError.permissionDenied {
            review.close()
            settingsWindow.show(tab: .permissions)
            settings.message = "Grant Accessibility access in the Permissions tab, then try again."
        } catch AccessibilityError.noFocusedField, AccessibilityError.unsupportedRead,
                AccessibilityError.unavailable {
            guard let frontmostPID else { showCaptureError(AccessibilityError.noFocusedField); return }
            captureTask = Task { [weak self] in
                do {
                    let field = try await KeyboardField.capture(frontmostPID: frontmostPID)
                    guard !Task.isCancelled else { return }
                    self?.presentCaptured(.keyboard(field))
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.showCaptureError(error)
                }
            }
        } catch {
            showCaptureError(error)
        }
    }

    private func presentCaptured(_ field: CapturedInput) {
        captured = field
        review.model.captureFailed = false
        review.model.source = field.source
        review.model.english = ""
        review.model.chinese = ""
        review.model.ambiguity = nil
        review.model.reason = nil
        review.model.richTextRisk = field.richTextRisk
        review.model.allowFormattingLoss = false
        review.model.providerLabel = settings.provider == .chatGPTPlan ? "Using ChatGPT plan" : "Using OpenAI API Key"
        review.model.captureNotice = field.usedKeyboardFallback
            ? "Keyboard capture: caret may move to the end. Return to the original field before Replace."
            : ""
        review.model.message = "Analyzing…"
        review.show(near: field.bounds)
        requestAnalysis(chineseIntent: nil)
    }

    private func showCaptureError(_ error: Error) {
        review.model.captureFailed = true
        review.model.source = ""
        review.model.english = ""
        review.model.chinese = ""
        review.model.message = captureErrorMessage(error)
        review.show()
    }

    private func regenerate() {
        requestAnalysis(chineseIntent: review.model.chinese)
    }

    private func requestAnalysis(chineseIntent: String?) {
        guard let field = captured else { return }
        let selectedProvider = settings.provider
        let selectedModel = settings.model
        let selectedPlanModel = settings.planModel
        requestTask?.cancel()
        review.model.isReady = false
        review.model.captureFailed = false
        review.model.reason = nil
        do {
            let input = try AnalysisInput(source: field.source, locale: settings.locale, chineseIntent: chineseIntent)
            let newSession = AnalysisSession(snapshot: TargetSnapshot(appID: field.appID, elementID: String(field.pid), source: field.source))
            session = newSession
            review.model.isLoading = true
            review.model.message = "Analyzing…"
            requestTask = Task { [weak self] in
                do {
                    guard let self else { return }
                    let provider: any LanguageService
                    switch selectedProvider {
                    case .apiKey:
                        guard let key = try APIKeyStore.load(), !key.isEmpty else {
                            self.settingsWindow.show(tab: .ai)
                            throw OpenAIProviderError.missingKey
                        }
                        provider = OpenAIProvider(key: key, model: selectedModel)
                    case .chatGPTPlan:
                        guard let account = try await ChatGPTAuth.validAccount() else {
                            self.settingsWindow.show(tab: .ai)
                            throw ChatGPTAuthError.missingPlanPermission
                        }
                        guard !selectedPlanModel.isEmpty else {
                            self.settingsWindow.show(tab: .ai)
                            throw ChatGPTPlanError.noModels
                        }
                        provider = ChatGPTPlanProvider(token: account.accessToken, model: selectedPlanModel)
                    }
                    let result = try await provider.analyze(input)
                    guard !Task.isCancelled, self.session?.generation == newSession.generation else { return }
                    self.review.model.english = result.english
                    self.review.model.chinese = result.chineseMeaning
                    self.review.model.ambiguity = result.ambiguity
                    self.review.model.reason = result.reason
                    self.review.model.worthChanging = result.worthChanging
                    self.review.model.isReady = true
                    self.review.model.message = result.worthChanging
                        ? (field.usedKeyboardFallback
                            ? "Return to the original field, then press your Replace shortcut."
                            : "Review the meaning, then press your Replace shortcut.")
                        : "Already natural — no change suggested."
                    self.review.model.isLoading = false
                } catch {
                    guard let self, !Task.isCancelled, self.session?.generation == newSession.generation else { return }
                    self.review.model.message = self.analysisErrorMessage(error)
                    self.review.model.isLoading = false
                }
            }
        } catch {
            review.model.message = "Could not analyze this input: \(error)"
        }
    }

    private func replace() {
        guard !isReplacing else { return }
        guard let field = captured, let session,
              review.model.isReady, !review.model.isLoading else { return }
        guard !review.model.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              review.model.english != field.source else {
            review.model.message = "No changed English to replace."
            return
        }
        if field.richTextRisk && !review.model.allowFormattingLoss {
            review.model.message = "This editor has formatting. Confirm the formatting warning or copy the English."
            review.show(near: field.bounds)
            return
        }
        review.model.isLoading = true
        isReplacing = true
        replaceTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.review.model.isLoading = false
                self.isReplacing = false
                self.replaceTask = nil
            }
            do {
                guard session.snapshot.source == field.source else { throw AccessibilityError.stale }
                try await field.replaceIfUnchanged(with: self.review.model.english)
                guard !Task.isCancelled else { return }
                self.review.model.message = "Replaced the original input."
                self.review.model.isReady = false
                self.captured = nil
                self.session = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.review.model.message = self.replaceErrorMessage(error)
                self.review.show(near: field.bounds)
            }
        }
    }

    private func copyEnglish() {
        guard review.model.isReady, !review.model.english.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(review.model.english, forType: .string)
        review.model.message = "English copied."
    }

    private func analysisErrorMessage(_ error: Error) -> String {
        if case OpenAIProviderError.missingKey = error {
            return "Add an OpenAI API key in Settings → AI."
        }
        if case ChatGPTAuthError.missingPlanPermission = error {
            return "Connect an eligible ChatGPT account in Settings → AI."
        }
        if case ChatGPTPlanError.noModels = error {
            return "Choose an available ChatGPT model in Settings → AI."
        }
        if case OpenAIProviderError.httpStatus(401) = error {
            return "OpenAI rejected this API key. Check it in Settings → AI."
        }
        if case OpenAIProviderError.httpStatus(429) = error {
            return "OpenAI API rate or usage limit reached. Check your API account."
        }
        if case ChatGPTPlanError.httpStatus(let status, let code) = error {
            if code == "subscription_sharing_user_not_eligible" {
                return "This ChatGPT account or workspace is not eligible for plan usage."
            }
            if code == "subscription_sharing_usage_limit_exceeded" {
                return "ChatGPT plan usage limit reached. Review usage in Settings → AI."
            }
            if code == "subscription_sharing_usage_unavailable" {
                return "ChatGPT usage is temporarily unavailable. Try again later."
            }
            return "ChatGPT request was rejected (HTTP \(status)\(code.map { ", \($0)" } ?? "")). Check your account in Settings → AI."
        }
        if case StreamDecoderError.failed(let code) = error,
           code == "subscription_sharing_usage_limit_exceeded" || code == "subscription_sharing_usage_unavailable" {
            return "ChatGPT plan usage is unavailable or at its limit. Review ChatGPT usage in Settings → AI."
        }
        if case StreamDecoderError.incomplete = error {
            return "ChatGPT stopped before finishing this analysis. Try again."
        }
        if case StreamDecoderError.interrupted = error {
            return "The ChatGPT response ended before completion. Try again."
        }
        if case StreamDecoderError.invalidEvent = error {
            return "ChatGPT returned an unreadable response event. Try again."
        }
        if case ChatGPTPlanError.invalidResponse = error {
            return "ChatGPT returned an unreadable result. Try again or use an API key in Settings → AI."
        }
        return "Analysis failed: \(error)"
    }

    private func discardSession() {
        captureTask?.cancel()
        captureTask = nil
        replaceTask?.cancel()
        replaceTask = nil
        requestTask?.cancel()
        requestTask = nil
        captured = nil
        session = nil
        review.model.isReady = false
        review.model.isLoading = false
        review.model.source = ""
        review.model.english = ""
        review.model.chinese = ""
        review.model.message = ""
        review.model.worthChanging = true
        review.model.reason = nil
        review.model.ambiguity = nil
        review.model.richTextRisk = false
        review.model.allowFormattingLoss = false
        review.model.providerLabel = ""
        review.model.captureNotice = ""
    }

    private func captureErrorMessage(_ error: Error) -> String {
        switch error {
        case KeyboardFieldError.unsupportedFocus:
            "The focused control is not an editable text field. No text was sent."
        case KeyboardFieldError.clipboardUnavailable:
            "Could not safely preserve the clipboard for this editor. No text was sent."
        case KeyboardFieldError.clipboardChanged:
            "The clipboard changed during capture. Analyze again. No text was sent."
        case KeyboardFieldError.copyFailed:
            "This editor did not provide text through Copy. No text was sent."
        case KeyboardFieldError.tooLong:
            "This editor contains more than 100 KB of text. Narrow the input before analyzing."
        case KeyboardFieldError.stale:
            "The active editor changed during capture. Focus the input and press Analyze again."
        case KeyboardFieldError.noTarget:
            "Could not identify the active editor window. No text was sent."
        case KeyboardFieldError.eventFailed:
            "Could not send the editor's Copy shortcut. Release the shortcut keys and try again."
        case AccessibilityError.unsupportedRead:
            "This editor does not expose its text through macOS Accessibility. No text was sent. Try a standard text field."
        case FieldError.protected: "Protected fields cannot be analyzed."
        case FieldError.empty: "Type English in the focused field, then press Analyze."
        case FieldError.nonEnglish: "This version analyzes English input only."
        case FieldError.notEditable, FieldError.unsupportedRole: "The focused control is not a supported editable text field."
        case AccessibilityError.noFocusedField: "Focus an editable text field, then press Analyze."
        default: "Could not read this input field: \(error)"
        }
    }

    private func replaceErrorMessage(_ error: Error) -> String {
        switch error {
        case KeyboardFieldError.stale:
            "Return to the original input field and press Replace. Its text and window must still match."
        case KeyboardFieldError.writeUnverified:
            "Could not verify the keyboard replacement. Check the original field before any retry; the English remains available to copy."
        case KeyboardFieldError.clipboardChanged:
            "The clipboard changed during replacement. Check the original field before retrying."
        case AccessibilityError.stale: "The original input or focus changed. Analyze again before replacing."
        case AccessibilityError.unsupportedWrite: "This editor does not support direct replacement. Copy the English instead."
        default: "Replacement could not be verified. Copy the English or check the original field before retrying."
        }
    }
}

@main
@MainActor
enum SenseDraftMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = SenseDraftAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
