import AppKit
import Carbon
import SenseDraftCore
import SwiftUI
import OSLog

private enum AISettingsError: LocalizedError {
    case blankKey
    var errorDescription: String? { "Enter a nonempty API key." }
}

enum AIConnectionCheck: Equatable {
    case checking
    case succeeded
    case failed(String)
}

enum AISaveFeedback: Equatable {
    case idle
    case saved
    case failed(String)
}

enum AIProviderChoice: String, CaseIterable, Identifiable {
    case apiKey = "API Key"
    case chatGPTPlan = "ChatGPT plan"
    case deepSeek = "DeepSeek"
    case kimi = "Kimi"
    var id: String { rawValue }

    var title: String { self == .apiKey ? "OpenAI API" : rawValue }
    var keychainService: String? {
        switch self {
        case .apiKey: "com.sensedraft.mac.openai"
        case .deepSeek: "com.sensedraft.mac.deepseek"
        case .kimi: "com.sensedraft.mac.kimi"
        case .chatGPTPlan: nil
        }
    }
}
enum SettingsTab: Hashable, CaseIterable {
    case general, ai, writing, history, shortcuts, permissions

    var title: String {
        switch self {
        case .general: "Home"
        case .history: "History"
        case .ai: "AI Services"
        case .writing: "Writing"
        case .shortcuts: "Shortcuts"
        case .permissions: "Permissions"
        }
    }

    var icon: String {
        switch self {
        case .general: "house"
        case .history: "clock.arrow.circlepath"
        case .ai: "sparkles"
        case .writing: "textformat"
        case .shortcuts: "keyboard"
        case .permissions: "hand.raised"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private static let connectionLogger = Logger(subsystem: "com.kaaaaai.SenseDraft", category: "ai-connection")
    @Published var selectedTab: SettingsTab = .general
    @Published var enabledProviders: Set<AIProviderChoice>
    @Published var resultProviders: Set<AIProviderChoice>
    @Published var model: String
    @Published var deepSeekModel: String
    @Published var kimiModel: String
    @Published var kimiRegion: KimiAPIRegion
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
    @Published var historyEnabled: Bool {
        didSet { UserDefaults.standard.set(historyEnabled, forKey: "historyEnabled") }
    }
    @Published var historyRetention: HistoryRetention {
        didSet { UserDefaults.standard.set(historyRetention.rawValue, forKey: "historyRetention") }
    }
    @Published var writingPreferences: WritingPreferences
    @Published var analyzeShortcut: Shortcut
    @Published var replaceShortcut: Shortcut
    @Published var apiKeyDraft = ""
    @Published var hasAPIKey: Bool
    @Published var deepSeekKeyDraft = ""
    @Published var kimiKeyDraft = ""
    @Published var hasDeepSeekKey = false
    @Published var hasKimiKey = false
    @Published var message = ""
    @Published var aiSaveFeedback: AISaveFeedback = .idle
    @Published var connectionChecks: [AIProviderChoice: AIConnectionCheck] = [:]
    private var connectionTasks: [AIProviderChoice: Task<Void, Never>] = [:]
    private let credentialCache = ProviderCredentialCache(loader: ProviderKeyStore.load)
    @Published var shortcutMessage = ""
    @Published var shortcutDisplayRevision = 0

    init() {
        let defaults = UserDefaults.standard
        let initialEnabled: Set<AIProviderChoice>
        if let saved = defaults.stringArray(forKey: "enabledAIProviders") {
            initialEnabled = Set(saved.compactMap(AIProviderChoice.init(rawValue:)))
        } else {
            initialEnabled = [AIProviderChoice(rawValue: defaults.string(forKey: "aiProvider") ?? "API Key") ?? .apiKey]
        }
        enabledProviders = initialEnabled
        if let saved = defaults.stringArray(forKey: "resultAIProviders") {
            resultProviders = Set(saved.compactMap(AIProviderChoice.init(rawValue:)))
        } else {
            let previousLimit = min(4, max(1, defaults.object(forKey: "aiResultLimit") as? Int ?? 1))
            resultProviders = Set(AIProviderChoice.allCases.filter { initialEnabled.contains($0) }.prefix(previousLimit))
        }
        model = defaults.string(forKey: "model") ?? "gpt-6.1-sol"
        deepSeekModel = defaults.string(forKey: "deepSeekModel") ?? "deepseek-flash"
        kimiModel = defaults.string(forKey: "kimiModel") ?? "kimi-k2.6"
        kimiRegion = KimiAPIRegion(rawValue: defaults.string(forKey: "kimiAPIRegion") ?? "") ?? .china
        planModel = defaults.string(forKey: "planModel") ?? ""
        locale = defaults.string(forKey: "locale") ?? "en-US"
        allowFormattingLoss = defaults.bool(forKey: "allowFormattingLoss")
        historyEnabled = defaults.bool(forKey: "historyEnabled")
        historyRetention = HistoryRetention(rawValue: defaults.string(forKey: "historyRetention") ?? "") ?? .unlimited
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
                (try? ProviderKeyStore.contains(service: "com.sensedraft.mac.openai")) == true
            }.value
        }
        Task {
            let stored = await Task.detached(priority: .utility) {
                ((try? ProviderKeyStore.contains(service: "com.sensedraft.mac.deepseek")) == true,
                 (try? ProviderKeyStore.contains(service: "com.sensedraft.mac.kimi")) == true)
            }.value
            hasDeepSeekKey = stored.0
            hasKimiKey = stored.1
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
            let drafts = [apiKeyDraft, deepSeekKeyDraft, kimiKeyDraft]
            if drafts.contains(where: { !$0.isEmpty && $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                throw AISettingsError.blankKey
            }
            try saveKeyDraft(&apiKeyDraft, hasKey: &hasAPIKey, service: "com.sensedraft.mac.openai")
            try saveKeyDraft(&deepSeekKeyDraft, hasKey: &hasDeepSeekKey, service: "com.sensedraft.mac.deepseek")
            try saveKeyDraft(&kimiKeyDraft, hasKey: &hasKimiKey, service: "com.sensedraft.mac.kimi")
            UserDefaults.standard.set(model, forKey: "model")
            UserDefaults.standard.set(deepSeekModel, forKey: "deepSeekModel")
            UserDefaults.standard.set(kimiModel, forKey: "kimiModel")
            UserDefaults.standard.set(kimiRegion.rawValue, forKey: "kimiAPIRegion")
            UserDefaults.standard.set(planModel, forKey: "planModel")
            UserDefaults.standard.set(locale, forKey: "locale")
            UserDefaults.standard.set(AIProviderChoice.allCases.filter { enabledProviders.contains($0) }.map(\.rawValue), forKey: "enabledAIProviders")
            UserDefaults.standard.set(AIProviderChoice.allCases.filter { resultProviders.contains($0) }.map(\.rawValue), forKey: "resultAIProviders")
            message = "AI settings saved."
            aiSaveFeedback = .saved
        } catch {
            message = "Could not save AI settings: \(error.localizedDescription)"
            aiSaveFeedback = .failed(error.localizedDescription)
        }
    }

    private func saveKeyDraft(_ draft: inout String, hasKey: inout Bool, service: String) throws {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            try ProviderKeyStore.save(trimmed, service: service)
            credentialCache.recordSave(trimmed, service: service)
            draft = ""
            hasKey = true
        }
    }

    func removeKey(for provider: AIProviderChoice) {
        guard let service = provider.keychainService else { return }
        do {
            try ProviderKeyStore.remove(service: service)
            credentialCache.remove(service: service)
            invalidateConnection(for: provider)
            switch provider {
            case .apiKey: hasAPIKey = false; apiKeyDraft = ""
            case .deepSeek: hasDeepSeekKey = false; deepSeekKeyDraft = ""
            case .kimi: hasKimiKey = false; kimiKeyDraft = ""
            case .chatGPTPlan: break
            }
            message = "API key removed."
        } catch {
            message = "Could not remove the API key: \(error)"
        }
    }

    func invalidateConnection(for provider: AIProviderChoice) {
        connectionTasks[provider]?.cancel()
        connectionChecks[provider] = nil
        aiSaveFeedback = .idle
    }

    func checkConnection(for provider: AIProviderChoice) {
        connectionTasks[provider]?.cancel()
        connectionChecks[provider] = .checking
        connectionTasks[provider] = Task {
            do {
                let service: any LanguageService
                switch provider {
                case .apiKey:
                    guard let key = try keyForCheck(apiKeyDraft, service: "com.sensedraft.mac.openai") else {
                        throw AISettingsError.blankKey
                    }
                    service = OpenAIProvider(key: key, model: model)
                case .deepSeek:
                    guard let key = try keyForCheck(deepSeekKeyDraft, service: "com.sensedraft.mac.deepseek") else {
                        throw AISettingsError.blankKey
                    }
                    service = ChatCompletionsProvider(service: .deepSeek, key: key, model: deepSeekModel)
                case .kimi:
                    guard let key = try keyForCheck(kimiKeyDraft, service: "com.sensedraft.mac.kimi") else {
                        throw AISettingsError.blankKey
                    }
                    service = ChatCompletionsProvider(service: .kimi(kimiRegion), key: key, model: kimiModel)
                case .chatGPTPlan:
                    guard let account = try await ChatGPTAuth.validAccount(), !planModel.isEmpty else {
                        connectionChecks[provider] = .failed("Connect ChatGPT and select a model first.")
                        return
                    }
                    service = ChatGPTPlanProvider(token: account.accessToken, model: planModel)
                }
                let input = try AnalysisInput(source: "This is a connection check.", locale: "en-US", chineseIntent: nil)
                _ = try await service.analyze(input)
                guard !Task.isCancelled else { return }
                connectionChecks[provider] = .succeeded
            } catch {
                guard !Task.isCancelled else { return }
                connectionChecks[provider] = .failed(connectionErrorMessage(error))
            }
        }
    }

    private func keyForCheck(_ draft: String, service: String) throws -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? try storedKey(service: service) : trimmed
    }

    func storedKey(service: String) throws -> String? {
        try credentialCache.load(service: service)
    }

    private func connectionErrorMessage(_ error: Error) -> String {
        if let error = error as? OpenAIProviderError {
            if case .httpStatus(let code) = error { return ProviderHTTPStatusMessage.forConnectionCheck(code) }
        }
        if let error = error as? ChatCompletionsProviderError {
            if case .httpStatus(let code, let type, let requestID) = error {
                let safeType = type ?? "unknown"
                let safeRequestID = requestID ?? "none"
                Self.connectionLogger.error("chat completions check failed status=\(code) type=\(safeType, privacy: .public) request_id=\(safeRequestID, privacy: .public)")
                return ProviderHTTPStatusMessage.forConnectionCheck(code, kimiErrorType: type)
            }
        }
        if let error = error as? URLError { return error.localizedDescription }
        return "Connection failed. Check the account, model, and network."
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
                enabledProviders.insert(.chatGPTPlan)
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
            if modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "v",
               NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) {
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
    private let history: HistoryStore
    private let onSaveShortcuts: () -> Void
    private let onBeginShortcutRecording: () -> Void
    private let onEndShortcutRecording: () -> Void

    init(settings: AppSettings, history: HistoryStore, onSaveShortcuts: @escaping () -> Void,
         onBeginShortcutRecording: @escaping () -> Void, onEndShortcutRecording: @escaping () -> Void) {
        self.settings = settings
        self.history = history
        self.onSaveShortcuts = onSaveShortcuts
        self.onBeginShortcutRecording = onBeginShortcutRecording
        self.onEndShortcutRecording = onEndShortcutRecording
    }

    func show(tab: SettingsTab? = nil) {
        settings.selectedTab = tab ?? .general
        if window == nil {
            let window = SettingsClosingWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "SenseDraft Settings"
            window.minSize = NSSize(width: 900, height: 580)
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings,
                history: history,
                onSaveShortcuts: onSaveShortcuts, onBeginShortcutRecording: onBeginShortcutRecording,
                onEndShortcutRecording: onEndShortcutRecording))
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if settings.enabledProviders.contains(.chatGPTPlan) { settings.refreshPlanModels() }
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryStore
    let onSaveShortcuts: () -> Void
    let onBeginShortcutRecording: () -> Void
    let onEndShortcutRecording: () -> Void
    @State private var selectedProvider: AIProviderChoice = .apiKey
    @State private var selectedWritingSection = 0
    @State private var selectedShortcutSection = 0

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            Group {
                switch settings.selectedTab {
                case .general: homePage
                case .history: HistoryView(settings: settings, history: history)
                case .ai: aiPage
                case .writing: writingPage
                case .shortcuts: shortcutsPage
                case .permissions: PermissionSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 900, minHeight: 580)
        .onChange(of: settings.enabledProviders) { _, choices in
            settings.aiSaveFeedback = .idle
            if choices.contains(.chatGPTPlan) { settings.refreshPlanModels() }
        }
        .onChange(of: settings.resultProviders) { _, _ in settings.aiSaveFeedback = .idle }
        .onChange(of: settings.model) { _, _ in settings.invalidateConnection(for: .apiKey) }
        .onChange(of: settings.deepSeekModel) { _, _ in settings.invalidateConnection(for: .deepSeek) }
        .onChange(of: settings.kimiModel) { _, _ in settings.invalidateConnection(for: .kimi) }
        .onChange(of: settings.kimiRegion) { _, _ in settings.invalidateConnection(for: .kimi) }
        .onChange(of: settings.planModel) { _, _ in settings.invalidateConnection(for: .chatGPTPlan) }
        .onChange(of: settings.apiKeyDraft) { _, value in
            if !value.isEmpty { settings.invalidateConnection(for: .apiKey) }
        }
        .onChange(of: settings.deepSeekKeyDraft) { _, value in
            if !value.isEmpty { settings.invalidateConnection(for: .deepSeek) }
        }
        .onChange(of: settings.kimiKeyDraft) { _, value in
            if !value.isEmpty { settings.invalidateConnection(for: .kimi) }
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
        VStack(alignment: .leading, spacing: 22) {
            Text("SENSEDRAFT")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 16)
            VStack(alignment: .leading, spacing: 5) {
                sidebarHeading("WRITE")
                sidebarItem(.general)
                sidebarItem(.ai)
                sidebarItem(.writing)
            }
            VStack(alignment: .leading, spacing: 5) {
                sidebarHeading("DATA & APP")
                sidebarItem(.history)
                sidebarItem(.shortcuts)
                sidebarItem(.permissions)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 202)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
    }

    private func sidebarHeading(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 5)
    }

    private func sidebarItem(_ tab: SettingsTab) -> some View {
        Button { settings.selectedTab = tab } label: {
            Label(tab.title, systemImage: tab.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .background(settings.selectedTab == tab ? Color.accentColor.opacity(0.16) : .clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .accessibilityAddTraits(settings.selectedTab == tab ? .isSelected : [])
    }

    private var homePage: some View {
        detailLayout(title: "Home", subtitle: "Write naturally. Keep your meaning.") {
            sectionListHeading("GET STARTED")
            destinationRow("AI Services", icon: "sparkles", detail: "Choose sources") { settings.selectedTab = .ai }
            destinationRow("Writing", icon: "textformat", detail: "Tone and style") { settings.selectedTab = .writing }
            destinationRow("Shortcuts", icon: "keyboard", detail: "Analyze and replace") { settings.selectedTab = .shortcuts }
            destinationRow("Permissions", icon: "hand.raised", detail: "Accessibility") { settings.selectedTab = .permissions }
        } detail: {
            HStack(spacing: 18) {
                appLogo.frame(width: 72, height: 72).accessibilityLabel("SenseDraft app icon")
                VStack(alignment: .leading, spacing: 6) {
                    Text("SenseDraft").font(.title.bold())
                    Text("Review English with its Chinese meaning before replacing the source.")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Setup status").font(.headline)
                Label("\(settings.enabledProviders.count) AI sources enabled", systemImage: "sparkles")
                Label(PermissionGuide.isAuthorized ? "Accessibility access granted" : "Accessibility access needed",
                      systemImage: PermissionGuide.isAuthorized ? "checkmark.circle" : "exclamationmark.circle")
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Replacement").font(.headline)
                Toggle("Allow replacement to remove formatting", isOn: $settings.allowFormattingLoss)
                Text("Some editors cannot preserve formatting. This choice is saved immediately.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            Text("Analyze runs only when you use its shortcut. Replace still checks the original input before writing.")
                .font(.callout).foregroundStyle(.secondary)
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
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Services").font(.title2.bold())
                    Text("Enable sources, then choose which results to compare.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("SOURCES").font(.caption2.weight(.semibold)).tracking(0.8)
                        Spacer()
                        Text("USE").font(.caption2.weight(.semibold)).tracking(0.8)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(AIProviderChoice.allCases.enumerated()), id: \.element.id) { index, choice in
                                aiSourceRow(choice, priority: index + 1)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    Spacer(minLength: 0)
                    Text("Choose which enabled sources appear in results from each service's model settings.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                }
                .frame(width: 258)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .top, spacing: 12) {
                            ProviderIcon(name: selectedProvider.title, size: 42)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedProvider.title).font(.title3.weight(.semibold))
                                Text(providerStatus(selectedProvider))
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        providerDetails(selectedProvider)
                        if selectedProvider == .chatGPTPlan {
                            Text("ChatGPT plan availability depends on the connected account and its usage limits.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 510, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(24)
                }
            }
            HStack(spacing: 12) {
                Group {
                    switch settings.aiSaveFeedback {
                    case .saved:
                        Label("Settings saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed(let reason):
                        Label("Save failed: \(reason)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    case .idle:
                        if !settings.message.isEmpty && settings.message != "AI settings saved." {
                            Text(settings.message).foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.callout.weight(.medium))
                .lineLimit(2)
                Spacer(minLength: 0)
                Button(settings.aiSaveFeedback == .saved ? "Saved" : "Save AI settings") { settings.saveAI() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
        }
        .navigationTitle("AI Services")
    }

    private func aiSourceRow(_ choice: AIProviderChoice, priority: Int) -> some View {
        HStack(spacing: 6) {
            Button { selectedProvider = choice } label: {
                HStack(spacing: 9) {
                    ProviderIcon(name: choice.title, size: 21)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(choice.title).font(.callout.weight(.medium))
                        Text(providerStatus(choice)).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("Use \(choice.title)", isOn: Binding(
                get: { settings.enabledProviders.contains(choice) },
                set: { active in
                    if active { settings.enabledProviders.insert(choice) }
                    else { settings.enabledProviders.remove(choice) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(selectedProvider == choice ? Color.accentColor.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Priority \(priority), \(choice.title)")
    }

    private func providerStatus(_ choice: AIProviderChoice) -> String {
        switch choice {
        case .apiKey: settings.hasAPIKey ? "API key saved" : "Add an API key"
        case .chatGPTPlan: settings.planAccountLabel == "Not connected" ? "Connect an account" : settings.planAccountLabel
        case .deepSeek: settings.hasDeepSeekKey ? "API key saved" : "Add an API key"
        case .kimi: settings.hasKimiKey ? "API key saved" : "Add an API key"
        }
    }

    @ViewBuilder
    private func providerDetails(_ choice: AIProviderChoice) -> some View {
        switch choice {
        case .apiKey:
            VStack(alignment: .leading, spacing: 10) {
                Picker("Model", selection: $settings.model) {
                    Text("GPT-6.1 Sol").tag("gpt-6.1-sol")
                    Text("GPT-6 Luna").tag("gpt-6-luna")
                }
                resultDisplayControl(for: choice)
                keyEntry("OpenAI", draft: $settings.apiKeyDraft, hasKey: settings.hasAPIKey, choice: choice)
            }
        case .deepSeek:
            VStack(alignment: .leading, spacing: 10) {
                Picker("Model", selection: $settings.deepSeekModel) {
                    Text("DeepSeek Flash").tag("deepseek-flash")
                    Text("DeepSeek V4 Pro").tag("deepseek-v4-pro")
                }
                resultDisplayControl(for: choice)
                keyEntry("DeepSeek", draft: $settings.deepSeekKeyDraft, hasKey: settings.hasDeepSeekKey, choice: choice)
            }
        case .kimi:
            VStack(alignment: .leading, spacing: 10) {
                Picker("API region", selection: $settings.kimiRegion) {
                    Text("China · moonshot.cn").tag(KimiAPIRegion.china)
                    Text("Global · moonshot.ai").tag(KimiAPIRegion.global)
                }
                Picker("Model", selection: $settings.kimiModel) {
                    Text("Kimi K2.6 · Fast").tag("kimi-k2.6")
                    Text("Kimi K3").tag("kimi-k3")
                }
                resultDisplayControl(for: choice)
                keyEntry("Kimi", draft: $settings.kimiKeyDraft, hasKey: settings.hasKimiKey, choice: choice)
            }
        case .chatGPTPlan:
            VStack(alignment: .leading, spacing: 10) {
                if !settings.planModels.isEmpty {
                    Picker("Model", selection: $settings.planModel) {
                        ForEach(settings.planModels, id: \.slug) { model in
                            Text(model.displayName).tag(model.slug)
                        }
                    }
                }
                resultDisplayControl(for: choice)
                HStack(spacing: 8) {
                    Button(settings.planAccountLabel == "Not connected" ? "Connect ChatGPT" : "Reconnect") {
                        settings.connectPlan()
                    }
                    .disabled(settings.connectingPlan)
                    if settings.connectingPlan {
                        Button("Cancel") { settings.cancelPlanConnection() }
                    } else if settings.planAccountLabel != "Not connected" {
                        Button("Disconnect") { settings.disconnectPlan() }
                        Button("Refresh models") { settings.refreshPlanModels() }
                    }
                }
                Link("Manage ChatGPT usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                    .font(.caption)
                connectionControl(for: choice, enabled: settings.planAccountLabel != "Not connected" && !settings.planModel.isEmpty)
            }
        }
    }

    private func resultDisplayControl(for choice: AIProviderChoice) -> some View {
        HStack {
            Text("Show in results")
            Spacer()
            Toggle("Show \(choice.title) in results", isOn: Binding(
                get: { settings.resultProviders.contains(choice) },
                set: { visible in
                    if visible { settings.resultProviders.insert(choice) }
                    else { settings.resultProviders.remove(choice) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!settings.enabledProviders.contains(choice))
        }
        .font(.callout)
        .help(settings.enabledProviders.contains(choice)
              ? "Include this service's response when analyzing text"
              : "Enable this source on the left first")
    }

    private func keyEntry(_ name: String, draft: Binding<String>, hasKey: Bool,
                          choice: AIProviderChoice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API key").font(.callout.weight(.medium))
            SecureField(hasKey ? String(repeating: "•", count: 16) : "Enter \(name) API key", text: draft)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(name) API key\(hasKey ? ", saved" : "")")
            HStack {
                Text(draft.wrappedValue.isEmpty
                     ? (hasKey ? "Saved in macOS Keychain · Paste to replace" : "Stored in macOS Keychain after saving")
                     : "New key entered — save to keep it")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                connectionControl(for: choice, enabled: hasKey || !draft.wrappedValue.isEmpty)
                if hasKey {
                    Button("Remove key") { settings.removeKey(for: choice) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
    }

    private func connectionControl(for choice: AIProviderChoice, enabled: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            Button {
                settings.checkConnection(for: choice)
            } label: {
                if settings.connectionChecks[choice] == .checking {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Check connection", systemImage: "checkmark.circle")
                }
            }
            .disabled(!enabled || settings.connectionChecks[choice] == .checking)
            .help("Sends a short sample request to this provider; usage may be billed")
            if let status = settings.connectionChecks[choice] {
                switch status {
                case .checking:
                    Text("Checking…").foregroundStyle(.secondary)
                case .succeeded:
                    Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed(let reason):
                    Label(reason, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                }
            }
        }
        .font(.caption)
    }

    private var writingPage: some View {
        detailLayout(title: "Writing", subtitle: "Control the tone and shape of each suggestion.") {
            sectionListHeading("PREFERENCES")
            selectionRow("Language & style", icon: "textformat", selected: selectedWritingSection == 0) {
                selectedWritingSection = 0
            }
            selectionRow("Extra guidance", icon: "text.quote", selected: selectedWritingSection == 1) {
                selectedWritingSection = 1
            }
        } detail: {
            if selectedWritingSection == 0 {
                Text("Language & style").font(.title3.weight(.semibold))
                Divider()
                Picker("English locale", selection: $settings.locale) {
                    Text("US English").tag("en-US")
                    Text("UK English").tag("en-GB")
                }
                Picker("Tone", selection: $settings.writingPreferences.style) {
                    ForEach(WritingStyle.allCases) { style in Text(style.title).tag(style) }
                }
                .pickerStyle(.segmented)
                Picker("Opening case", selection: $settings.writingPreferences.openingCase) {
                    ForEach(OpeningCase.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented)
                Toggle("Use natural English abbreviations", isOn: $settings.writingPreferences.useNaturalAbbreviations)
                Text("Names, numbers, commitments, and the original meaning remain unchanged.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Extra guidance").font(.title3.weight(.semibold))
                Divider()
                Text("Add a short preference for future analyses and regenerations.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("For example: Keep it short for chat", text: $settings.writingPreferences.customInstruction)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Extra writing guidance")
                Text("Up to 240 characters. The original meaning and facts take priority.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Writing")
        .onChange(of: settings.locale) { _, value in
            UserDefaults.standard.set(value, forKey: "locale")
        }
    }

    private var shortcutsPage: some View {
        VStack(spacing: 0) {
            detailLayout(title: "Shortcuts", subtitle: "Choose the keys used to analyze and replace text.") {
                sectionListHeading("GLOBAL SHORTCUTS")
                selectionRow("Analyze", icon: "sparkles", selected: selectedShortcutSection == 0) {
                    selectedShortcutSection = 0
                }
                selectionRow("Replace", icon: "arrow.uturn.backward", selected: selectedShortcutSection == 1) {
                    selectedShortcutSection = 1
                }
            } detail: {
                Text(selectedShortcutSection == 0 ? "Analyze" : "Replace")
                    .font(.title3.weight(.semibold))
                Divider()
                Text(selectedShortcutSection == 0
                     ? "Read the focused input and show suggestions for review."
                     : "Replace only after the original input has been verified.")
                    .font(.callout).foregroundStyle(.secondary)
                ShortcutCapture(
                    shortcut: selectedShortcutSection == 0 ? $settings.analyzeShortcut : $settings.replaceShortcut,
                    onBegin: onBeginShortcutRecording, onEnd: onEndShortcutRecording
                )
                .frame(width: 210, height: 34)
                .id("\(selectedShortcutSection)-\(settings.shortcutDisplayRevision)")
                Text("Click the box and press a key combination with Command, Option, or Control.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text(settings.shortcutMessage).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Restore defaults") {
                    settings.restoreDefaultShortcuts()
                    onSaveShortcuts()
                }
                Button("Save shortcuts") { onSaveShortcuts() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Shortcuts")
    }

    private func detailLayout<ListContent: View, DetailContent: View>(
        title: String, subtitle: String,
        @ViewBuilder list: () -> ListContent,
        @ViewBuilder detail: () -> DetailContent
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.bold())
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            Divider()
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) { list() }
                        .padding(10)
                }
                .frame(width: 258)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) { detail() }
                        .frame(maxWidth: 510, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(24)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionListHeading(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold)).tracking(0.8)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }

    private func selectionRow(_ title: String, icon: String, selected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .background(selected ? Color.accentColor.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func destinationRow(_ title: String, icon: String, detail: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(detail)
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
