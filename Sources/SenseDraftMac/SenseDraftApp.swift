import AppKit
import SenseDraftCore

@MainActor
final class SenseDraftAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let settings = AppSettings()
    private lazy var history = HistoryStore(retention: settings.historyRetention)
    private lazy var settingsWindow = SettingsWindow(settings: settings, history: history,
        onSaveShortcuts: { [weak self] in self?.saveShortcuts() },
        onBeginShortcutRecording: { [weak self] in self?.hotkeys?.unregister() },
        onEndShortcutRecording: { [weak self] in self?.resumeShortcuts() })
    private lazy var review = ReviewPanel(history: history)
    private var hotkeys: GlobalHotkeys?
    private var activeHotkeys: HotkeySettings?
    private var captured: CapturedInput?
    private var captureTask: Task<Void, Never>?
    private var replaceTask: Task<Void, Never>?
    private var isReplacing = false
    private var session: AnalysisSession?
    private var historyID: UUID?
    private var requestTask: Task<Void, Never>?
    private var keyboardLayoutObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ReplacementDiagnostics.ready()
        settings.refreshStoredCredentials()
        setupMenuBar()
        review.model.onRegenerate = { [weak self] in self?.regenerate() }
        review.model.onCopyCandidate = { [weak self] in self?.copyEnglish(from: $0) }
        review.model.onReplace = { [weak self] in self?.replace() }
        review.model.onSelectCandidate = { [weak self] in self?.selectedCandidateChanged() }
        review.model.onOpenHistory = { [weak self] in self?.settingsWindow.show(tab: .history) }
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
        if let icon = menuBarIcon() {
            item.button?.image = icon
            item.button?.imagePosition = .imageOnly
        } else {
            item.button?.title = "SD"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "SenseDraft Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "History…", action: #selector(openHistory), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SenseDraft", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func menuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "StatusBar", withExtension: "png"),
              let source = NSImage(contentsOf: url) else { return nil }
        let size = NSSize(width: 18, height: 18)
        // The supplied artwork has generous transparent padding. Its subject is
        // centered within this square; fit that square to the menu bar glyph.
        let artwork = NSRect(x: 264, y: 252, width: 830, height: 830)
        let icon = NSImage(size: size, flipped: false) { destination in
            source.draw(in: destination, from: artwork, operation: .sourceOver, fraction: 1)
            return true
        }
        icon.isTemplate = true
        return icon
    }

    @objc private func openSettings() { settingsWindow.show() }
    @objc private func openHistory() { settingsWindow.show(tab: .history) }
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
        historyID = UUID()
        review.model.captureFailed = false
        review.model.source = field.source
        review.model.english = ""
        review.model.chinese = ""
        review.model.ambiguity = nil
        review.model.reason = nil
        review.model.lastGeneratedChinese = ""
        review.model.richTextRisk = field.richTextRisk
        review.model.providerLabel = "Comparing AI results"
        switch field {
        case .keyboard:
            review.model.captureNotice = "Keyboard capture: caret may move to the end. Return to the original field before Replace."
        case .accessibility where field.usedKeyboardFallback:
            review.model.captureNotice = "This editor uses keyboard replacement. SenseDraft will refocus the original input before replacing."
        default:
            review.model.captureNotice = ""
        }
        review.model.usedKeyboardFallback = field.usedKeyboardFallback
        if case .accessibility = field { review.model.canRestoreFocus = true }
        else { review.model.canRestoreFocus = false }
        review.model.message = "Analyzing…"
        requestAnalysis(chineseIntent: nil)
        review.show(near: field.bounds)
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
        let editedChinese = review.model.chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        let chineseIntent = editedChinese != review.model.lastGeneratedChinese ? editedChinese : nil
        requestAnalysis(chineseIntent: chineseIntent)
    }

    private func requestAnalysis(chineseIntent: String?) {
        guard let field = captured else { return }
        requestTask?.cancel()
        review.model.isReady = false
        review.model.captureFailed = false
        review.model.reason = nil
        review.model.beginResults(providers: AIProviderChoice.allCases.compactMap { choice in
            guard settings.enabledProviders.contains(choice), settings.resultProviders.contains(choice) else { return nil }
            switch choice {
            case .apiKey: return "OpenAI"
            case .chatGPTPlan: return "ChatGPT plan"
            case .deepSeek: return "DeepSeek"
            case .kimi: return "Kimi"
            }
        })
        do {
            let input = try AnalysisInput(source: field.source, locale: settings.locale,
                                          chineseIntent: chineseIntent, preferences: settings.writingPreferences)
            let newSession = AnalysisSession(snapshot: TargetSnapshot(appID: field.appID, elementID: String(field.pid), source: field.source))
            session = newSession
            review.model.isLoading = true
            review.model.message = "Analyzing…"
            requestTask = Task { [weak self] in
                do {
                    guard let self else { return }
                    let services = try await self.configuredServices()
                    guard !Task.isCancelled, self.session?.generation == newSession.generation else { return }
                    guard !services.isEmpty else {
                        self.settingsWindow.show(tab: .ai)
                        self.review.model.message = "Enable and configure an AI source, then turn on Show in results in Settings → AI Services."
                        self.review.model.isLoading = false
                        return
                    }
                    self.review.model.beginResults(providers: services.map(\.0))
                    await withTaskGroup(of: (String, AnalysisResult?, String?).self) { group in
                        for item in services {
                            group.addTask {
                                do {
                                    return (item.0, try await item.1.analyze(input), nil)
                                } catch {
                                    return (item.0, nil, ProviderResultErrorMessage.describe(error, provider: item.0))
                                }
                            }
                        }
                        for await (label, result, error) in group {
                            guard !Task.isCancelled,
                                  self.session?.generation == newSession.generation else { continue }
                            if let result {
                                self.review.model.receive(ReviewCandidate(provider: label, result: result))
                                self.review.model.message = ""
                                self.recordSelectedCandidate()
                            } else if let error {
                                self.review.model.fail(provider: label, message: error)
                            }
                        }
                    }
                    guard !Task.isCancelled, self.session?.generation == newSession.generation else { return }
                    let candidates = self.review.model.candidates
                    let failures = self.review.model.providerErrors
                    self.review.model.message = candidates.isEmpty ?
                        "AI analysis failed. Check each service result above." :
                        !failures.isEmpty ? "Some AI results failed; available results can still be used." :
                        self.review.model.worthChanging
                        ? (field.usedKeyboardFallback && !self.review.model.canRestoreFocus
                            ? "Return to the original field, then press your Replace shortcut."
                            : "")
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

    private func configuredServices() async throws -> [(String, any LanguageService)] {
        var services: [(String, any LanguageService)] = []
        for choice in AIProviderChoice.allCases
            where settings.enabledProviders.contains(choice) && settings.resultProviders.contains(choice) {
            switch choice {
            case .apiKey:
                if let key = try settings.storedKey(service: "com.sensedraft.mac.openai"), !key.isEmpty {
                    services.append(("OpenAI", OpenAIProvider(key: key, model: settings.model)))
                }
            case .chatGPTPlan:
                if let account = try? await ChatGPTAuth.validAccount(), !settings.planModel.isEmpty {
                    services.append(("ChatGPT plan", ChatGPTPlanProvider(token: account.accessToken, model: settings.planModel)))
                }
            case .deepSeek:
                if let key = try settings.storedKey(service: "com.sensedraft.mac.deepseek"), !key.isEmpty {
                    services.append(("DeepSeek", ChatCompletionsProvider(service: .deepSeek, key: key, model: settings.deepSeekModel)))
                }
            case .kimi:
                if let key = try settings.storedKey(service: "com.sensedraft.mac.kimi"), !key.isEmpty {
                    services.append(("Kimi", ChatCompletionsProvider(service: .kimi(settings.kimiRegion), key: key, model: settings.kimiModel)))
                }
            }
        }
        return services
    }

    private func selectedCandidateChanged() {
        review.model.message = review.model.worthChanging ? "" : "Already natural — no change suggested."
        recordSelectedCandidate()
    }

    private func recordSelectedCandidate() {
        guard settings.historyEnabled, let historyID, let field = captured,
              review.model.candidates.indices.contains(review.model.selectedCandidateIndex) else { return }
        let selected = review.model.candidates[review.model.selectedCandidateIndex]
        history.record(HistoryEntry(id: historyID, source: field.source,
            english: review.model.english, chinese: review.model.chinese,
            reason: selected.reason, ambiguity: selected.ambiguity,
            provider: selected.provider))
    }

    private func replace() {
        guard !isReplacing else { return }
        guard let field = captured, let session,
              review.model.isReady else { return }
        guard !review.model.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              review.model.english != field.source else {
            review.model.message = "No changed English to replace."
            return
        }
        if field.richTextRisk && !settings.allowFormattingLoss {
            review.model.message = "This editor has formatting. Enable formatting loss in Settings → Home or copy the English."
            review.show(near: field.bounds)
            return
        }
        review.model.isLoading = true
        review.model.isReplacing = true
        isReplacing = true
        requestTask?.cancel()
        ReplacementDiagnostics.begin(route: field.usedKeyboardFallback ? "keyboard" : "accessibility")
        replaceTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.review.model.isLoading = false
                self.review.model.isReplacing = false
                self.isReplacing = false
                self.replaceTask = nil
            }
            do {
                guard session.snapshot.source == field.source else { throw AccessibilityError.stale }
                if field.usedKeyboardFallback {
                    guard KeyboardField.isActiveTarget(field.pid)
                        || KeyboardField.isActiveTarget(ProcessInfo.processInfo.processIdentifier) else {
                        throw KeyboardFieldError.notFrontmost
                    }
                    self.review.hideForReplacement()
                    ReplacementDiagnostics.stage("panelHidden")
                }
                try await field.replaceIfUnchanged(with: self.review.model.english)
                guard !Task.isCancelled else { return }
                ReplacementDiagnostics.stage("writeVerified")
                if let historyID = self.historyID {
                    self.history.markReplaced(historyID, english: self.review.model.english)
                }
                self.review.model.message = "Replaced the original input."
                self.review.model.isReady = false
                self.captured = nil
                self.session = nil
                self.review.close()
                ReplacementDiagnostics.finish()
            } catch {
                guard !Task.isCancelled else { return }
                ReplacementDiagnostics.finish(error: error)
                for provider in self.review.model.providerNames
                    where !self.review.model.candidates.contains(where: { $0.provider == provider })
                    && self.review.model.providerErrors[provider] == nil {
                    self.review.model.fail(provider: provider, message: "Analysis stopped after Replace was pressed.")
                }
                self.review.model.message = self.replaceErrorMessage(error)
                self.review.show(near: field.bounds)
            }
        }
    }

    private func copyEnglish(from provider: String) {
        guard let english = review.model.candidates.first(where: { $0.provider == provider })?.english,
              !english.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(english, forType: .string)
        review.model.message = "English copied."
    }

    private func analysisErrorMessage(_ error: Error) -> String {
        if case OpenAIProviderError.missingKey = error {
            return "Add an OpenAI API key in Settings → AI Services."
        }
        if case ChatGPTAuthError.missingPlanPermission = error {
            return "Connect an eligible ChatGPT account in Settings → AI Services."
        }
        if case ChatGPTPlanError.noModels = error {
            return "Choose an available ChatGPT model in Settings → AI Services."
        }
        if case OpenAIProviderError.httpStatus(401) = error {
            return "OpenAI rejected this API key. Check it in Settings → AI Services."
        }
        if case OpenAIProviderError.httpStatus(429) = error {
            return "OpenAI API rate or usage limit reached. Check your API account."
        }
        if case ChatGPTPlanError.httpStatus(let status, let code) = error {
            if code == "subscription_sharing_user_not_eligible" {
                return "This ChatGPT account or workspace is not eligible for plan usage."
            }
            if code == "subscription_sharing_usage_limit_exceeded" {
                return "ChatGPT plan usage limit reached. Review usage in Settings → AI Services."
            }
            if code == "subscription_sharing_usage_unavailable" {
                return "ChatGPT usage is temporarily unavailable. Try again later."
            }
            return "ChatGPT request was rejected (HTTP \(status)\(code.map { ", \($0)" } ?? "")). Check your account in Settings → AI Services."
        }
        if case StreamDecoderError.failed(let code) = error,
           code == "subscription_sharing_usage_limit_exceeded" || code == "subscription_sharing_usage_unavailable" {
            return "ChatGPT plan usage is unavailable or at its limit. Review ChatGPT usage in Settings → AI Services."
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
            return "ChatGPT returned an unreadable result. Try again or use an API key in Settings → AI Services."
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
        historyID = nil
        review.model.isReady = false
        review.model.isLoading = false
        review.model.source = ""
        review.model.english = ""
        review.model.chinese = ""
        review.model.lastGeneratedChinese = ""
        review.model.message = ""
        review.model.worthChanging = true
        review.model.reason = nil
        review.model.ambiguity = nil
        review.model.richTextRisk = false
        review.model.providerLabel = ""
        review.model.beginResults(providers: [])
        review.model.isReplacing = false
        review.model.captureNotice = ""
        review.model.usedKeyboardFallback = false
        review.model.canRestoreFocus = false
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
        case KeyboardFieldError.windowUnavailable:
            "Could not identify this editor's window through Accessibility. Focus its input and try Analyze again. No text was sent."
        case KeyboardFieldError.eventFailed:
            "Could not send the editor's Copy shortcut. Release the shortcut keys and try again."
        case AccessibilityError.unsupportedRead:
            "This editor does not expose its text through macOS Accessibility. No text was sent. Try a standard text field."
        case FieldError.protected: "Protected fields cannot be analyzed."
        case FieldError.empty: "Type English in the focused field, then press Analyze."
        case FieldError.nonEnglish: "This version supports English and Chinese input."
        case FieldError.notEditable, FieldError.unsupportedRole: "The focused control is not a supported editable text field."
        case AccessibilityError.noFocusedField: "Focus an editable text field, then press Analyze."
        default: "Could not read this input field: \(error)"
        }
    }

    private func replaceErrorMessage(_ error: Error) -> String {
        switch error {
        case KeyboardFieldError.stale:
            "Return to the original input field and press Replace. Its text and window must still match."
        case KeyboardFieldError.focusRestoreFailed:
            "Could not restore focus to the original editor. No keyboard replacement was sent."
        case KeyboardFieldError.windowChanged:
            "The active editor window changed before replacement. No keyboard replacement was sent."
        case KeyboardFieldError.focusedFieldChanged:
            "The focused input changed before replacement. No keyboard replacement was sent."
        case KeyboardFieldError.sourceChanged:
            "The draft text changed before replacement. No replacement was sent."
        case KeyboardFieldError.noTarget, KeyboardFieldError.unsupportedFocus:
            "Could not identify the original editor. Focus its text field and press Replace again."
        case KeyboardFieldError.notFrontmost:
            "The original app was not frontmost when Replace ran. Click its input field, then press Replace again."
        case KeyboardFieldError.windowUnavailable:
            "The editor did not expose a focused or main window for replacement. Copy the English instead."
        case KeyboardFieldError.clipboardUnavailable:
            "Could not safely preserve the clipboard for replacement. Copy the English or simplify the clipboard contents before retrying."
        case KeyboardFieldError.copyFailed:
            "The editor did not provide its current text through Copy. The original text was not replaced."
        case KeyboardFieldError.tooLong:
            "The editor text is too long to verify safely. The original text was not replaced."
        case KeyboardFieldError.eventFailed:
            "Could not send the editor's keyboard command. The original text may be unchanged; check it before retrying."
        case KeyboardFieldError.eventCreationFailed:
            "macOS could not create a keyboard event for replacement. Check Accessibility permission for the current SenseDraft build."
        case KeyboardFieldError.writeUnverified:
            "Could not verify the keyboard replacement. Check the original field before any retry; the English remains available to copy."
        case KeyboardFieldError.clipboardChanged:
            "The clipboard changed during replacement. Check the original field before retrying."
        case AccessibilityError.permissionDenied:
            "Accessibility access is required to verify the original editor before replacement."
        case AccessibilityError.stale: "The original input or focus changed. Analyze again before replacing."
        case AccessibilityError.writeUnverified:
            "The editor accepted the replacement, but its updated text could not be confirmed. Check the original field before retrying."
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
