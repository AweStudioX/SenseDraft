import AppKit
import Carbon
import SenseDraftCore
import SwiftUI

enum AIProviderChoice: String, CaseIterable, Identifiable {
    case apiKey = "API Key"
    case chatGPTPlan = "ChatGPT plan"
    var id: String { rawValue }
}
enum SettingsTab: Hashable { case general, ai, shortcuts, permissions }

@MainActor
final class AppSettings: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
    @Published var provider: AIProviderChoice
    @Published var model: String
    @Published var planModel: String
    @Published var planModels: [PlanModel] = []
    @Published var planAccountLabel: String = "Checking account…"
    @Published var connectingPlan = false
    private var connectTask: Task<Void, Never>?
    private var planRefreshTask: Task<Void, Never>?
    @Published var locale: String
    @Published var writingPreferences: WritingPreferences
    @Published var analyzeShortcut: Shortcut
    @Published var replaceShortcut: Shortcut
    @Published var apiKeyDraft = ""
    @Published var hasAPIKey: Bool
    @Published var message = ""
    @Published var shortcutMessage = ""
    @Published var shortcutDisplayRevision = 0

    init() {
        let defaults = UserDefaults.standard
        provider = AIProviderChoice(rawValue: defaults.string(forKey: "aiProvider") ?? "API Key") ?? .apiKey
        model = defaults.string(forKey: "model") ?? "gpt-6.1-sol"
        planModel = defaults.string(forKey: "planModel") ?? ""
        locale = defaults.string(forKey: "locale") ?? "en-US"
        writingPreferences = WritingPreferencesStore.load()
        if let data = defaults.data(forKey: "hotkeys"),
           let settings = try? JSONDecoder().decode(HotkeySettings.self, from: data) {
            analyzeShortcut = settings.analyze
            replaceShortcut = settings.replace
        } else {
            analyzeShortcut = .defaultAnalyze
            replaceShortcut = .defaultReplace
        }
        hasAPIKey = false
    }

    func refreshStoredCredentials() {
        Task {
            hasAPIKey = await Task.detached(priority: .utility) {
                (try? APIKeyStore.load()) != nil
            }.value
        }
        Task {
            planAccountLabel = await Task.detached(priority: .utility) {
                let account = try? PlanAccountStore.load()
                return account?.canUsePlan == true
                    ? (account?.email ?? "Connected ChatGPT account") : "Not connected"
            }.value
        }
    }

    func saveAI() {
        do {
            let trimmedKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKeyDraft.isEmpty && trimmedKey.isEmpty {
                message = "Enter a nonempty API key."
                return
            }
            if !trimmedKey.isEmpty {
                try APIKeyStore.save(trimmedKey)
                apiKeyDraft = ""
                hasAPIKey = true
            }
            UserDefaults.standard.set(model, forKey: "model")
            UserDefaults.standard.set(planModel, forKey: "planModel")
            UserDefaults.standard.set(locale, forKey: "locale")
            UserDefaults.standard.set(provider.rawValue, forKey: "aiProvider")
            message = "AI settings saved."
        } catch {
            message = "Could not save the API key: \(error)"
        }
    }

    func removeAPIKey() {
        do {
            try APIKeyStore.remove()
            hasAPIKey = false
            apiKeyDraft = ""
            message = "API key removed."
        } catch {
            message = "Could not remove the API key: \(error)"
        }
    }

    func restoreDefaultShortcuts() {
        analyzeShortcut = .defaultAnalyze
        replaceShortcut = .defaultReplace
    }

    func connectPlan() {
        guard !connectingPlan else { return }
        connectingPlan = true
        message = "Waiting for ChatGPT authorization in your browser…"
        connectTask = Task {
            defer { connectingPlan = false; connectTask = nil }
            do {
                let account = try await ChatGPTAuth.signIn { [weak self] status in self?.message = status }
                try Task.checkCancellation()
                planAccountLabel = account.email ?? "Connected ChatGPT account"
                provider = .chatGPTPlan
                saveAI()
                message = "ChatGPT connected. Loading available models…"
                do {
                    let models = try await ChatGPTPlanProvider(token: account.accessToken, model: planModel).listModels()
                    try Task.checkCancellation()
                    planModels = models
                    if !models.contains(where: { $0.slug == planModel }) { planModel = models.first?.slug ?? "" }
                    saveAI()
                    message = models.isEmpty ? "Connected, but no models are available for this account." : "ChatGPT plan connected."
                } catch {
                    if !Task.isCancelled { message = "ChatGPT connected, but models could not load: \(error)" }
                }
            } catch {
                if Task.isCancelled {
                    message = "ChatGPT connection cancelled."
                } else if case ChatGPTAuthError.httpStatus(let status, let code) = error {
                    let detail = code.map { " (\($0))" } ?? ""
                    message = "Token exchange failed: HTTP \(status)\(detail). Start ChatGPT sign-in again."
                } else {
                    message = "ChatGPT connection failed: \(error)"
                }
            }
        }
    }

    func cancelPlanConnection() {
        connectTask?.cancel()
    }

    func refreshPlanModels() {
        planRefreshTask?.cancel()
        planRefreshTask = Task {
            do {
                guard let account = try await ChatGPTAuth.validAccount() else { return }
                let models = try await ChatGPTPlanProvider(token: account.accessToken, model: planModel).listModels()
                try Task.checkCancellation()
                planModels = models
                if !planModels.contains(where: { $0.slug == planModel }) { planModel = planModels.first?.slug ?? "" }
            } catch {
                if !Task.isCancelled { message = "Could not load ChatGPT models: \(error)" }
            }
        }
    }

    func disconnectPlan() {
        connectTask?.cancel()
        planRefreshTask?.cancel()
        do {
            try PlanAccountStore.remove()
            planAccountLabel = "Not connected"
            planModels = []
            planModel = ""
            message = "ChatGPT account disconnected."
        } catch {
            message = "Could not disconnect ChatGPT: \(error)"
        }
    }
}

@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    private let settings: AppSettings
    private let onSaveShortcuts: () -> Void
    private let onBeginShortcutRecording: () -> Void
    private let onEndShortcutRecording: () -> Void

    init(settings: AppSettings, onSaveShortcuts: @escaping () -> Void,
         onBeginShortcutRecording: @escaping () -> Void, onEndShortcutRecording: @escaping () -> Void) {
        self.settings = settings
        self.onSaveShortcuts = onSaveShortcuts
        self.onBeginShortcutRecording = onBeginShortcutRecording
        self.onEndShortcutRecording = onEndShortcutRecording
    }

    func show(tab: SettingsTab? = nil) {
        if let tab { settings.selectedTab = tab }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 430), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "SenseDraft Settings"
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings,
                onSaveShortcuts: onSaveShortcuts, onBeginShortcutRecording: onBeginShortcutRecording,
                onEndShortcutRecording: onEndShortcutRecording))
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if settings.provider == .chatGPTPlan { settings.refreshPlanModels() }
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onSaveShortcuts: () -> Void
    let onBeginShortcutRecording: () -> Void
    let onEndShortcutRecording: () -> Void

    var body: some View {
        TabView(selection: $settings.selectedTab) {
            VStack(alignment: .leading, spacing: 16) {
                Text("SenseDraft improves English while checking its meaning in Chinese.")
                    .font(.title3)
                Text("Analyze and Replace each use a global shortcut. No text selection is needed, and typing alone never sends a request.")
                Spacer()
            }
            .padding(24)
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(SettingsTab.general)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                Picker("AI source", selection: $settings.provider) {
                    ForEach(AIProviderChoice.allCases) { choice in Text(choice.rawValue).tag(choice) }
                }.pickerStyle(.segmented)
                if !settings.message.isEmpty {
                    Text(settings.message).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker("English locale", selection: $settings.locale) {
                    Text("US English").tag("en-US")
                    Text("UK English").tag("en-GB")
                }
                if settings.provider == .apiKey {
                    Picker("Model", selection: $settings.model) {
                        Text("GPT-6.1 Sol").tag("gpt-6.1-sol")
                        Text("GPT-6 Luna").tag("gpt-6-luna")
                    }
                    SecureField(settings.hasAPIKey ? "API key saved in Keychain — enter to replace" : "OpenAI API key", text: $settings.apiKeyDraft)
                    if settings.hasAPIKey { Button("Remove API key") { settings.removeAPIKey() } }
                } else {
                    Text("Use eligible requests with your ChatGPT Plus or Pro plan or available credits.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Account: \(settings.planAccountLabel)")
                    HStack {
                        Button(settings.planAccountLabel == "Not connected" ? "Continue with ChatGPT" : "Reconnect ChatGPT") { settings.connectPlan() }
                            .disabled(settings.connectingPlan)
                        if settings.connectingPlan {
                            Button("Cancel sign-in") { settings.cancelPlanConnection() }
                        }
                        if settings.planAccountLabel != "Not connected" {
                            Button("Disconnect") { settings.disconnectPlan() }
                                .disabled(settings.connectingPlan)
                        }
                    }
                    if !settings.planModels.isEmpty {
                        Picker("Model", selection: $settings.planModel) {
                            ForEach(settings.planModels, id: \.slug) { model in Text(model.displayName).tag(model.slug) }
                        }
                    }
                    if settings.planAccountLabel != "Not connected" {
                        Button("Refresh models") { settings.refreshPlanModels() }
                    }
                    Link("Manage ChatGPT usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                }
                Button("Save AI settings") { settings.saveAI() }
                Divider().padding(.vertical, 4)
                Text("Writing preferences").font(.headline)
                Text("Applied to the next analysis or regeneration.")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("Tone", selection: $settings.writingPreferences.style) {
                    ForEach(WritingStyle.allCases) { style in Text(style.title).tag(style) }
                }
                .pickerStyle(.segmented)
                Picker("Opening case", selection: $settings.writingPreferences.openingCase) {
                    ForEach(OpeningCase.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented)
                Text("Lowercase keeps the opening casual when grammar allows; names and “I” stay capitalized.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Use natural English abbreviations", isOn: $settings.writingPreferences.useNaturalAbbreviations)
                Text("When appropriate, use common contractions and chat shorthand. Existing clear abbreviations are preserved either way.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("Optional guidance, e.g. shorter and more local", text: $settings.writingPreferences.customInstruction)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Extra writing guidance")
                Text("The original meaning, names, and facts still take priority.")
                    .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .tabItem { Label("AI", systemImage: "sparkles") }
            .tag(SettingsTab.ai)

            VStack(alignment: .leading, spacing: 16) {
                Text("Click a shortcut box, then press the new key combination. Include Command, Option, or Control.")
                HStack { Text("Analyze").frame(width: 90, alignment: .leading); ShortcutCapture(shortcut: $settings.analyzeShortcut, onBegin: onBeginShortcutRecording, onEnd: onEndShortcutRecording).frame(width: 190, height: 30).id(settings.shortcutDisplayRevision) }
                HStack { Text("Replace").frame(width: 90, alignment: .leading); ShortcutCapture(shortcut: $settings.replaceShortcut, onBegin: onBeginShortcutRecording, onEnd: onEndShortcutRecording).frame(width: 190, height: 30).id(settings.shortcutDisplayRevision) }
                HStack {
                    Button("Save shortcuts") { onSaveShortcuts() }
                    Button("Restore defaults") {
                        settings.restoreDefaultShortcuts()
                        onSaveShortcuts()
                    }
                }
                Text(settings.shortcutMessage).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(24)
            .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            .tag(SettingsTab.shortcuts)

            PermissionSettingsView()
                .tabItem { Label("Permissions", systemImage: "hand.raised") }
                .tag(SettingsTab.permissions)
        }
        .frame(minWidth: 600, minHeight: 430)
        .onChange(of: settings.provider) { _, choice in
            if choice == .chatGPTPlan { settings.refreshPlanModels() }
        }
        .onChange(of: settings.writingPreferences) { _, value in
            if value.customInstruction.count > 240 {
                settings.writingPreferences.customInstruction = String(value.customInstruction.prefix(240))
            } else {
                WritingPreferencesStore.save(value)
            }
        }
    }
}

private struct ShortcutCapture: NSViewRepresentable {
    @Binding var shortcut: Shortcut
    let onBegin: () -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onChange = { shortcut = $0 }
        view.onBegin = onBegin
        view.onEnd = onEnd
        view.shortcut = shortcut
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Record shortcut")
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.shortcut = shortcut
        view.onBegin = onBegin
        view.onEnd = onEnd
        view.setAccessibilityValue(ShortcutLabel.describe(shortcut))
    }
}

private final class RecorderView: NSView {
    var shortcut = Shortcut(keyCode: 0, modifiers: 0) { didSet { needsDisplay = true } }
    var onChange: ((Shortcut) -> Void)?
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    private var recording = false

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 190, height: 30) }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    override func accessibilityPerformPress() -> Bool {
        beginRecording()
        return true
    }

    private func beginRecording() {
        window?.makeFirstResponder(self)
        if !recording { onBegin?() }
        recording = true
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        if recording { recording = false; onEnd?(); needsDisplay = true }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            recording = false
            onEnd?()
            needsDisplay = true
            return
        }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else { NSSound.beep(); return }
        recording = false
        onChange?(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
        onEnd?()
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        outline.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        outline.lineWidth = recording ? 2 : 1
        outline.stroke()
        let title = recording ? "Press shortcut…" : ShortcutLabel.describe(shortcut)
        (title as NSString).draw(in: bounds.insetBy(dx: 10, dy: 5), withAttributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 13)])
    }
}
