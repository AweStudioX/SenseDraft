import AppKit
import Carbon
import SenseDraftCore
import SwiftUI

enum AIProviderChoice: String, CaseIterable, Identifiable {
    case apiKey = "API Key"
    case chatGPTPlan = "ChatGPT plan"
    var id: String { rawValue }
}
enum SettingsTab: Hashable, CaseIterable {
    case general, ai, shortcuts, permissions

    var title: String {
        switch self {
        case .general: "Home"
        case .ai: "AI & Writing"
        case .shortcuts: "Shortcuts"
        case .permissions: "Permissions"
        }
    }

    var icon: String {
        switch self {
        case .general: "house"
        case .ai: "sparkles"
        case .shortcuts: "keyboard"
        case .permissions: "hand.raised"
        }
    }
}

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
    @Published var allowFormattingLoss: Bool {
        didSet { UserDefaults.standard.set(allowFormattingLoss, forKey: "allowFormattingLoss") }
    }
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
        allowFormattingLoss = defaults.bool(forKey: "allowFormattingLoss")
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
private final class SettingsClosingWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "w" {
                (firstResponder as? RecorderView)?.cancelRecording()
                close()
                return
            }
            if event.keyCode == 53 && modifiers.isEmpty && (firstResponder as? RecorderView)?.isRecording != true {
                close()
                return
            }
        }
        super.sendEvent(event)
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
        settings.selectedTab = tab ?? .general
        if window == nil {
            let window = SettingsClosingWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 580), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "SenseDraft Settings"
            window.minSize = NSSize(width: 720, height: 500)
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
        HStack(spacing: 0) {
            sidebar
            Divider()
            Group {
                switch settings.selectedTab {
                case .general: homePage
                case .ai: aiPage
                case .shortcuts: shortcutsPage
                case .permissions: PermissionSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 720, minHeight: 500)
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SENSEDRAFT")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            VStack(spacing: 4) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        settings.selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .contentShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .background(settings.selectedTab == tab ? Color.accentColor.opacity(0.14) : .clear,
                                in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityAddTraits(settings.selectedTab == tab ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
    }

    private var homePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 20) {
                    appLogo
                        .frame(width: 92, height: 92)
                        .accessibilityLabel("SenseDraft app icon")
                    VStack(alignment: .leading, spacing: 7) {
                        Text("SenseDraft")
                            .font(.largeTitle.bold())
                        Text("Write naturally. Keep your meaning.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)

                settingsCard("How it works", icon: "text.quote") {
                    Text("Press Analyze to review a clearer English draft and its Chinese meaning. Replace only when you choose to.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsCard("Replacement", icon: "arrow.uturn.backward") {
                    Toggle("Allow Replace to remove text formatting", isOn: $settings.allowFormattingLoss)
                    Text("Some editors cannot preserve formatting during replacement. This choice is saved for future sessions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .navigationTitle("Home")
    }

    private var appLogo: some View {
        Group {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
               let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "text.quote")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.blue)
                    .padding(20)
            }
        }
    }

    private var aiPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeading("AI & Writing", subtitle: "Choose a provider and shape the English you want to write.")
                settingsCard("AI source", icon: "sparkles") {
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
                }
                settingsCard("Writing preferences", icon: "textformat") {
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
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .navigationTitle("AI & Writing")
    }

    private var shortcutsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeading("Shortcuts", subtitle: "Choose the keys you use to analyze and replace text.")
                settingsCard("Global shortcuts", icon: "keyboard") {
                Text("Click a shortcut box, then press the new key combination. Include Command, Option, or Control.")
                    .font(.callout).foregroundStyle(.secondary)
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
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .navigationTitle("Shortcuts")
    }

    private func pageHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private func settingsCard<Content: View>(_ title: String, icon: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
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
    var isRecording: Bool { recording }

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
            cancelRecording()
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

    func cancelRecording() {
        guard recording else { return }
        recording = false
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
