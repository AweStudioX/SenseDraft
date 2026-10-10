import AppKit
import Carbon
import SenseDraftCore
import SwiftUI

enum AIProviderChoice: String, CaseIterable, Identifiable {
    case apiKey = "API Key"
    case chatGPTPlan = "ChatGPT plan"
    var id: String { rawValue }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var provider: AIProviderChoice
    @Published var model: String
    @Published var planModel: String
    @Published var planModels: [PlanModel] = []
    @Published var planAccountLabel: String = "Not connected"
    @Published var connectingPlan = false
    @Published var locale: String
    @Published var analyzeShortcut: Shortcut
    @Published var replaceShortcut: Shortcut
    @Published var apiKeyDraft = ""
    @Published var hasAPIKey: Bool
    @Published var message = ""
    @Published var shortcutMessage = ""

    init() {
        let defaults = UserDefaults.standard
        provider = AIProviderChoice(rawValue: defaults.string(forKey: "aiProvider") ?? "API Key") ?? .apiKey
        model = defaults.string(forKey: "model") ?? "gpt-6.1-sol"
        planModel = defaults.string(forKey: "planModel") ?? ""
        locale = defaults.string(forKey: "locale") ?? "en-US"
        if let data = defaults.data(forKey: "hotkeys"),
           let settings = try? JSONDecoder().decode(HotkeySettings.self, from: data) {
            analyzeShortcut = settings.analyze
            replaceShortcut = settings.replace
        } else {
            analyzeShortcut = .defaultAnalyze
            replaceShortcut = .defaultReplace
        }
        hasAPIKey = (try? APIKeyStore.load()) != nil
        if let account = try? PlanAccountStore.load(), account.canUsePlan {
            planAccountLabel = account.email ?? "Connected ChatGPT account"
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
        Task {
            defer { connectingPlan = false }
            do {
                let account = try await ChatGPTAuth.signIn()
                planAccountLabel = account.email ?? "Connected ChatGPT account"
                let models = try await ChatGPTPlanProvider(token: account.accessToken, model: planModel).listModels()
                planModels = models
                if !models.contains(where: { $0.slug == planModel }) { planModel = models.first?.slug ?? "" }
                provider = .chatGPTPlan
                saveAI()
                message = models.isEmpty ? "Connected, but no models are available for this account." : "ChatGPT plan connected."
            } catch {
                message = "ChatGPT connection failed: \(error)"
            }
        }
    }

    func refreshPlanModels() {
        Task {
            do {
                guard let account = try await ChatGPTAuth.validAccount() else { return }
                planModels = try await ChatGPTPlanProvider(token: account.accessToken, model: planModel).listModels()
                if !planModels.contains(where: { $0.slug == planModel }) { planModel = planModels.first?.slug ?? "" }
            } catch {
                message = "Could not load ChatGPT models: \(error)"
            }
        }
    }

    func disconnectPlan() {
        do {
            try PlanAccountStore.remove()
            UserDefaults.standard.removeObject(forKey: "chatgptClientID")
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

    init(settings: AppSettings, onSaveShortcuts: @escaping () -> Void) {
        self.settings = settings
        self.onSaveShortcuts = onSaveShortcuts
    }

    func show(permissions: Bool = false) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 430), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "SenseDraft Settings"
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings, onSaveShortcuts: onSaveShortcuts, initialTab: permissions ? .permissions : .general))
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if settings.provider == .chatGPTPlan { settings.refreshPlanModels() }
    }
}

private struct SettingsView: View {
    enum Tab: Hashable { case general, ai, shortcuts, permissions }
    @ObservedObject var settings: AppSettings
    let onSaveShortcuts: () -> Void
    @State private var tab: Tab

    init(settings: AppSettings, onSaveShortcuts: @escaping () -> Void, initialTab: Tab) {
        self.settings = settings
        self.onSaveShortcuts = onSaveShortcuts
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $tab) {
            VStack(alignment: .leading, spacing: 16) {
                Text("SenseDraft improves English while checking its meaning in Chinese.")
                    .font(.title3)
                Text("Analyze and Replace each use a global shortcut. No text selection is needed, and typing alone never sends a request.")
                Spacer()
            }
            .padding(24)
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(Tab.general)

            VStack(alignment: .leading, spacing: 16) {
                Picker("AI source", selection: $settings.provider) {
                    ForEach(AIProviderChoice.allCases) { choice in Text(choice.rawValue).tag(choice) }
                }.pickerStyle(.segmented)
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
                        if settings.planAccountLabel != "Not connected" {
                            Button("Disconnect") { settings.disconnectPlan() }
                        }
                    }
                    if !settings.planModels.isEmpty {
                        Picker("Model", selection: $settings.planModel) {
                            ForEach(settings.planModels, id: \.slug) { model in Text(model.displayName).tag(model.slug) }
                        }
                    }
                    Link("Manage ChatGPT usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                }
                Button("Save AI settings") { settings.saveAI() }
                Text(settings.message).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(24)
            .tabItem { Label("AI", systemImage: "sparkles") }
            .tag(Tab.ai)

            VStack(alignment: .leading, spacing: 16) {
                Text("Click a shortcut box, then press the new key combination. Include Command, Option, or Control.")
                HStack { Text("Analyze").frame(width: 90, alignment: .leading); ShortcutCapture(shortcut: $settings.analyzeShortcut).frame(width: 190, height: 30) }
                HStack { Text("Replace").frame(width: 90, alignment: .leading); ShortcutCapture(shortcut: $settings.replaceShortcut).frame(width: 190, height: 30) }
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
            .tag(Tab.shortcuts)

            PermissionSettingsView()
                .tabItem { Label("Permissions", systemImage: "hand.raised") }
                .tag(Tab.permissions)
        }
        .frame(minWidth: 600, minHeight: 430)
        .onChange(of: settings.provider) { _, choice in
            if choice == .chatGPTPlan { settings.refreshPlanModels() }
        }
    }
}

private struct ShortcutCapture: NSViewRepresentable {
    @Binding var shortcut: Shortcut

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onChange = { shortcut = $0 }
        view.shortcut = shortcut
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Record shortcut")
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.shortcut = shortcut
        view.setAccessibilityValue(ShortcutLabel.describe(shortcut))
    }
}

private final class RecorderView: NSView {
    var shortcut = Shortcut(keyCode: 0, modifiers: 0) { didSet { needsDisplay = true } }
    var onChange: ((Shortcut) -> Void)?
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
        recording = true
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else { NSSound.beep(); return }
        recording = false
        onChange?(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
        needsDisplay = true
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

enum ShortcutLabel {
    static func describe(_ shortcut: Shortcut) -> String {
        var label = ""
        if shortcut.modifiers & UInt32(controlKey) != 0 { label += "⌃" }
        if shortcut.modifiers & UInt32(optionKey) != 0 { label += "⌥" }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { label += "⇧" }
        if shortcut.modifiers & UInt32(cmdKey) != 0 { label += "⌘" }
        if shortcut.keyCode == 36 { return label + "↩" }
        if shortcut.keyCode == 14 { return label + "E" }
        return label + "Key \(shortcut.keyCode)"
    }
}
