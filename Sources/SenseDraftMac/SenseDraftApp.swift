import AppKit
import SenseDraftCore

@MainActor
final class SenseDraftAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let settings = AppSettings()
    private lazy var settingsWindow = SettingsWindow(settings: settings) { [weak self] in self?.saveShortcuts() }
    private let review = ReviewPanel()
    private var hotkeys: GlobalHotkeys?
    private var activeHotkeys: HotkeySettings?
    private var captured: CapturedField?
    private var session: AnalysisSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        review.model.onRegenerate = { [weak self] in self?.regenerate() }
        review.model.onCopy = { [weak self] in self?.copyEnglish() }
        review.model.onClose = { [weak self] in self?.review.close() }
        saveShortcuts()
        if !UserDefaults.standard.bool(forKey: "onboardingShown") {
            UserDefaults.standard.set(true, forKey: "onboardingShown")
            settingsWindow.show(permissions: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys?.unregister()
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
                hotkeys = try GlobalHotkeys(settings: proposed, onAnalyze: { [weak self] in self?.analyze() }, onReplace: { [weak self] in self?.replace() })
            }
            activeHotkeys = proposed
            UserDefaults.standard.set(try JSONEncoder().encode(proposed), forKey: "hotkeys")
            settings.shortcutMessage = "Shortcuts saved."
        } catch {
            if let activeHotkeys {
                settings.analyzeShortcut = activeHotkeys.analyze
                settings.replaceShortcut = activeHotkeys.replace
            }
            settings.shortcutMessage = "Shortcut unavailable or duplicated: \(error)"
        }
    }

    private func analyze() {
        do {
            let field = try AccessibilityField.captureFocused()
            captured = field
            review.model.source = field.source
            review.model.english = ""
            review.model.chinese = ""
            review.model.ambiguity = nil
            review.model.message = "Analyzing…"
            review.show()
            requestAnalysis(chineseIntent: nil)
        } catch AccessibilityError.permissionDenied {
            settingsWindow.show()
            PermissionGuide.request()
            settings.message = "Grant Accessibility access in the Permissions tab, then try again."
        } catch {
            review.model.message = "Could not read this input field: \(error)"
            review.show()
        }
    }

    private func regenerate() {
        requestAnalysis(chineseIntent: review.model.chinese)
    }

    private func requestAnalysis(chineseIntent: String?) {
        guard let field = captured else { return }
        do {
            let input = try AnalysisInput(source: field.source, locale: settings.locale, chineseIntent: chineseIntent)
            let newSession = AnalysisSession(snapshot: TargetSnapshot(appID: field.appID, elementID: String(field.pid), source: field.source))
            session = newSession
            review.model.isLoading = true
            review.model.message = "Analyzing…"
            Task { [weak self] in
                do {
                    guard let self else { return }
                    let provider: any LanguageService
                    switch self.settings.provider {
                    case .apiKey:
                        guard let key = try APIKeyStore.load(), !key.isEmpty else {
                            self.settingsWindow.show()
                            throw OpenAIProviderError.missingKey
                        }
                        provider = OpenAIProvider(key: key, model: self.settings.model)
                    case .chatGPTPlan:
                        guard let account = try await ChatGPTAuth.validAccount() else {
                            self.settingsWindow.show()
                            throw ChatGPTAuthError.missingPlanPermission
                        }
                        guard !self.settings.planModel.isEmpty else {
                            self.settingsWindow.show()
                            throw ChatGPTPlanError.noModels
                        }
                        provider = ChatGPTPlanProvider(token: account.accessToken, model: self.settings.planModel)
                    }
                    let result = try await provider.analyze(input)
                    guard self.session?.generation == newSession.generation else { return }
                    self.review.model.english = result.english
                    self.review.model.chinese = result.chineseMeaning
                    self.review.model.ambiguity = result.ambiguity
                    self.review.model.message = "Review the meaning, then press your Replace shortcut."
                    self.review.model.isLoading = false
                } catch {
                    guard let self, self.session?.generation == newSession.generation else { return }
                    self.review.model.message = self.analysisErrorMessage(error)
                    self.review.model.isLoading = false
                }
            }
        } catch {
            review.model.message = "Could not analyze this input: \(error)"
        }
    }

    private func replace() {
        guard let field = captured, let session,
              !review.model.isLoading,
              !review.model.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            guard session.snapshot.source == field.source else { throw AccessibilityError.stale }
            try field.replaceIfUnchanged(with: review.model.english)
            review.model.message = "Replaced the original input."
            captured = nil
            self.session = nil
        } catch {
            review.model.message = "Input changed or replacement failed. Original text was not retried: \(error)"
            review.show()
        }
    }

    private func copyEnglish() {
        guard !review.model.english.isEmpty else { return }
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
        if case StreamDecoderError.failed(let code) = error,
           code == "subscription_sharing_usage_limit_exceeded" || code == "subscription_sharing_usage_unavailable" {
            return "ChatGPT plan usage is unavailable or at its limit. Review ChatGPT usage in Settings → AI."
        }
        return "Analysis failed: \(error)"
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
