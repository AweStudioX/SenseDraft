import AppKit
import SenseDraftCore
import SwiftUI

struct ReviewCandidate: Identifiable {
    let id = UUID()
    let provider: String
    var english: String
    var chinese: String
    let ambiguity: String?
    let reason: String?
    let worthChanging: Bool

    init(provider: String, result: AnalysisResult) {
        self.provider = provider
        english = result.english
        chinese = result.chineseMeaning
        ambiguity = result.ambiguity
        reason = result.reason
        worthChanging = result.worthChanging
    }
}

@MainActor
final class ReviewModel: ObservableObject {
    private let preferredProviderKey = "preferredReviewProvider"
    @Published var source = ""
    @Published var english = ""
    @Published var chinese = ""
    @Published var lastGeneratedChinese = ""
    @Published var ambiguity: String?
    @Published var reason: String?
    @Published var worthChanging = true
    @Published var isReady = false
    @Published var captureFailed = false
    @Published var richTextRisk = false
    @Published var replaceShortcutText = "⌥⌘↩"
    @Published var providerLabel = ""
    @Published var candidates: [ReviewCandidate] = []
    @Published var selectedCandidateIndex = 0
    @Published var providerNames: [String] = []
    @Published var providerErrors: [String: String] = [:]
    private var selectedThisRequest = false
    @Published var captureNotice = ""
    @Published var usedKeyboardFallback = false
    @Published var canRestoreFocus = false
    @Published var message = ""
    @Published var isLoading = false
    @Published var isReplacing = false
    var onRegenerate: (() -> Void)?
    var onCopyCandidate: ((String) -> Void)?
    var onReplace: (() -> Void)?
    var onSelectCandidate: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onClose: (() -> Void)?

    var hasReplacement: Bool {
        isReady && !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && english != source
    }

    var canReplaceFromPanel: Bool {
        hasReplacement && !isReplacing && (!usedKeyboardFallback || canRestoreFocus)
    }

    func beginResults(providers: [String]) {
        providerNames = providers
        providerErrors = [:]
        candidates = []
        selectedCandidateIndex = 0
        selectedThisRequest = false
        isReady = false
    }

    func receive(_ candidate: ReviewCandidate) {
        guard providerNames.contains(candidate.provider) else { return }
        let currentProvider = candidates.indices.contains(selectedCandidateIndex)
            ? candidates[selectedCandidateIndex].provider : nil
        candidates.append(candidate)
        candidates.sort {
            (providerNames.firstIndex(of: $0.provider) ?? .max) <
            (providerNames.firstIndex(of: $1.provider) ?? .max)
        }
        let preferred = UserDefaults.standard.string(forKey: preferredProviderKey)
        if !selectedThisRequest, let index = candidates.firstIndex(where: { $0.provider == preferred }) {
            selectedCandidateIndex = index
        } else if let currentProvider,
                  let index = candidates.firstIndex(where: { $0.provider == currentProvider }) {
            selectedCandidateIndex = index
        } else {
            selectedCandidateIndex = candidates.firstIndex(where: { $0.provider == candidate.provider }) ?? 0
        }
        loadCandidate(at: selectedCandidateIndex)
    }

    func fail(provider: String, message: String) {
        providerErrors[provider] = message
    }

    func editEnglish(_ value: String, for provider: String) {
        guard let index = candidates.firstIndex(where: { $0.provider == provider }) else { return }
        candidates[index].english = value
        if index == selectedCandidateIndex { english = value }
    }

    func editChinese(_ value: String, for provider: String) {
        guard let index = candidates.firstIndex(where: { $0.provider == provider }) else { return }
        candidates[index].chinese = value
        if index == selectedCandidateIndex { chinese = value }
    }

    func selectCandidate(at index: Int) {
        guard candidates.indices.contains(index) else { return }
        selectedCandidateIndex = index
        selectedThisRequest = true
        UserDefaults.standard.set(candidates[index].provider, forKey: preferredProviderKey)
        loadCandidate(at: index)
        onSelectCandidate?()
    }

    @discardableResult
    func moveSelection(by offset: Int) -> Bool {
        let next = selectedCandidateIndex + offset
        guard candidates.indices.contains(next), next != selectedCandidateIndex else { return false }
        selectCandidate(at: next)
        return true
    }

    @discardableResult
    func replaceFromPanel() -> Bool {
        guard canReplaceFromPanel, let onReplace else { return false }
        onReplace()
        return true
    }

    private func loadCandidate(at index: Int) {
        let candidate = candidates[index]
        english = candidate.english
        chinese = candidate.chinese
        lastGeneratedChinese = candidate.chinese
        ambiguity = candidate.ambiguity
        reason = candidate.reason
        worthChanging = candidate.worthChanging
        providerLabel = candidate.provider
        isReady = true
    }
}

@MainActor
final class ReviewPanel: NSObject, NSWindowDelegate {
    let model = ReviewModel()
    private let panel: EscapeClosingPanel
    private let history: HistoryStore
    private let savedXKey = "reviewPanelManualX"
    private let savedYKey = "reviewPanelManualY"
    private var positioning = false
    private var lastAutomaticOrigin: CGPoint?
    var onDismiss: (() -> Void)?

    init(history: HistoryStore) {
        self.history = history
        panel = EscapeClosingPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 440),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        panel.title = "SenseDraft"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 500, height: 340)
        let hostingView = NSHostingView(rootView: ReviewView(model: model, history: history))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.center()
        super.init()
        panel.delegate = self
        panel.onMoveSelection = { [weak self] offset in
            self?.model.moveSelection(by: offset) ?? false
        }
        panel.onReturn = { [weak self] in
            self?.model.replaceFromPanel() ?? false
        }
    }

    func show(near fieldBounds: CGRect? = nil) {
        let wasVisible = panel.isVisible
        positioning = true
        defer { positioning = false }
        let preferredHeight: CGFloat = model.captureFailed ? 210 :
            CGFloat(180 + 260 * max(1, model.providerNames.count))
        panel.minSize = NSSize(width: 500, height: model.captureFailed ? 210 : 340)
        if !wasVisible {
            let visibleHeight = NSScreen.main?.visibleFrame.height ?? preferredHeight
            panel.setContentSize(NSSize(width: 620, height: min(preferredHeight, visibleHeight * 0.88)))
        }
        let screens = NSScreen.screens
        let primaryTop = screens.first?.frame.maxY ?? 0
        let cocoaField = fieldBounds.map {
            CGRect(x: $0.minX, y: primaryTop - $0.maxY, width: $0.width, height: $0.height)
        }
        let fieldScreen = cocoaField.flatMap { field -> NSScreen? in
            guard let screen = screens.max(by: {
                intersectionArea($0.frame, field) < intersectionArea($1.frame, field)
            }), intersectionArea(screen.frame, field) > 0 else { return nil }
            return screen
        } ?? NSScreen.main ?? screens.first
        let savedOrigin: CGPoint? = {
            guard UserDefaults.standard.object(forKey: savedXKey) != nil,
                  UserDefaults.standard.object(forKey: savedYKey) != nil else { return nil }
            return CGPoint(x: UserDefaults.standard.double(forKey: savedXKey),
                           y: UserDefaults.standard.double(forKey: savedYKey))
        }()
        if let savedOrigin, let savedScreen = screens.first(where: { $0.frame.contains(savedOrigin) }) ?? fieldScreen {
            let origin = PanelPlacement.clamp(savedOrigin, panelSize: panel.frame.size,
                                              visibleFrame: savedScreen.visibleFrame)
            panel.setFrameOrigin(origin)
            lastAutomaticOrigin = origin
        } else if let cocoaField, let fieldScreen {
            let origin = PanelPlacement.origin(panelSize: panel.frame.size, fieldRect: cocoaField,
                                               visibleFrame: fieldScreen.visibleFrame)
            panel.setFrameOrigin(origin)
            lastAutomaticOrigin = origin
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { panel.close() }

    func hideForReplacement() { panel.orderOut(nil) }


    func windowWillClose(_ notification: Notification) { onDismiss?() }

    func windowDidMove(_ notification: Notification) {
        guard !positioning, panel.isVisible else { return }
        let origin = panel.frame.origin
        if let lastAutomaticOrigin,
           abs(origin.x - lastAutomaticOrigin.x) < 1,
           abs(origin.y - lastAutomaticOrigin.y) < 1 { return }
        UserDefaults.standard.set(Double(origin.x), forKey: savedXKey)
        UserDefaults.standard.set(Double(origin.y), forKey: savedYKey)
    }

    private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let rect = a.intersection(b)
        return rect.isNull ? 0 : rect.width * rect.height
    }
}

private final class EscapeClosingPanel: NSPanel {
    var onMoveSelection: ((Int) -> Bool)?
    var onReturn: (() -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           !(firstResponder is NSTextView),
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            if (event.keyCode == 125 || event.keyCode == 126),
               onMoveSelection?(event.keyCode == 125 ? 1 : -1) == true { return }
            if (event.keyCode == 36 || event.keyCode == 76), onReturn?() == true { return }
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) { close() }
}

private struct ReviewView: View {
    @ObservedObject var model: ReviewModel
    @ObservedObject var history: HistoryStore
    @State private var showingHistory = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.captureFailed {
                captureError
            } else {
                sourceSection
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                sectionLabel("AI RESULTS", icon: "square.stack")
                                Spacer()
                                if model.candidates.count > 1 {
                                    Text("↑↓ to select")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ForEach(model.providerNames, id: \.self) { provider in
                                resultCard(for: provider)
                                    .id(provider)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: model.selectedCandidateIndex) { _, index in
                        guard model.candidates.indices.contains(index) else { return }
                        withAnimation {
                            scrollProxy.scrollTo(model.candidates[index].provider, anchor: .center)
                        }
                    }
                }
                footer
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
        .tint(.blue)
        .onExitCommand { model.onClose?() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.quote")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("Review suggestion").font(.headline)
                Text(model.providerLabel.isEmpty ? "English, with meaning checked" : model.providerLabel)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showingHistory.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .help("History")
            .accessibilityLabel("History")
            .popover(isPresented: $showingHistory, arrowEdge: .trailing) {
                HistoryQuickView(history: history) {
                    showingHistory = false
                    model.onOpenHistory?()
                }
            }
            if model.isLoading { ProgressView().controlSize(.small) }
            else {
                Text(model.captureFailed ? "Input unavailable" : (model.isReady ? (model.hasReplacement ? "Ready" : "No change") : "Waiting"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(model.captureFailed ? Color.orange : Color.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var captureError: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Could not read the focused editor", systemImage: "text.badge.xmark")
                .font(.headline)
            Text(model.message).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Close") { model.onClose?() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("ORIGINAL", icon: "text.alignleft")
            ScrollView {
                Text(model.source)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .id(model.source)
            .frame(minHeight: 28, maxHeight: 72)
            .padding(9)
            .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            if !model.captureNotice.isEmpty {
                Label(model.captureNotice, systemImage: "keyboard")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func resultCard(for provider: String) -> some View {
        let index = model.candidates.firstIndex(where: { $0.provider == provider })
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                ProviderIcon(name: provider, size: 20)
                Text(provider).font(.callout.weight(.semibold))
                Spacer()
                if let index {
                    Button("Copy English") { model.onCopyCandidate?(provider) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        model.selectCandidate(at: index)
                    } label: {
                        Label(index == model.selectedCandidateIndex ? "Selected for Replace" : "Use for Replace",
                              systemImage: index == model.selectedCandidateIndex ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == model.selectedCandidateIndex ? Color.accentColor : Color.secondary)
                    .font(.caption)
                } else if model.providerErrors[provider] == nil {
                    ProgressView().controlSize(.small)
                }
            }
            if let index {
                let candidate = model.candidates[index]
                Text("ENGLISH").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                editor(text: Binding(
                    get: { model.candidates.first(where: { $0.provider == provider })?.english ?? "" },
                    set: { model.editEnglish($0, for: provider) }),
                    height: 66, enabled: model.isReady && !model.isReplacing)
                    .accessibilityLabel("\(provider) English")
                if let reason = candidate.reason, !reason.isEmpty {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("CHINESE MEANING").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                editor(text: Binding(
                    get: { model.candidates.first(where: { $0.provider == provider })?.chinese ?? "" },
                    set: { model.editChinese($0, for: provider) }),
                    height: 54, enabled: model.isReady && !model.isReplacing)
                    .accessibilityLabel("\(provider) Chinese meaning")
                if let ambiguity = candidate.ambiguity, !ambiguity.isEmpty {
                    Label(ambiguity, systemImage: "questionmark.bubble")
                        .font(.caption).foregroundStyle(.orange)
                }
            } else if let error = model.providerErrors[provider] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.12))
                    .frame(height: 22).frame(maxWidth: 280, alignment: .leading)
                    .redacted(reason: .placeholder)
                RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.08))
                    .frame(height: 18).frame(maxWidth: 180, alignment: .leading)
                    .redacted(reason: .placeholder)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.05))
                .onTapGesture {
                    if let index { model.selectCandidate(at: index) }
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(index == model.selectedCandidateIndex ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.12)))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.richTextRisk {
                Text("Replacing here may remove text formatting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !model.message.isEmpty && model.message != "Already natural — no change suggested." {
                Text(model.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("Regenerate") { model.onRegenerate?() }
                    .disabled(model.isLoading || model.source.isEmpty)
                Spacer()
                if model.hasReplacement {
                    if model.usedKeyboardFallback && !model.canRestoreFocus {
                        Text("Return to editor · \(model.replaceShortcutText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button { model.replaceFromPanel() } label: {
                            Label("Replace", systemImage: "return")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isReplacing)
                        Text("↩ or \(model.replaceShortcutText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Esc to close")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }

    private func editor(text: Binding<String>, height: CGFloat, enabled: Bool) -> some View {
        TextEditor(text: text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(5)
            .frame(height: height)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(nsColor: .separatorColor)))
            .disabled(!enabled)
    }
}
