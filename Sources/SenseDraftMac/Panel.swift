import AppKit
import SenseDraftCore
import SwiftUI

struct ReviewCandidate: Identifiable {
    let id = UUID()
    let provider: String
    var english: String
    var chinese: String
    let generatedChinese: String
    let ambiguity: String?
    let reason: String?
    let worthChanging: Bool

    init(provider: String, result: AnalysisResult) {
        self.provider = provider
        english = result.english
        chinese = result.chineseMeaning
        generatedChinese = result.chineseMeaning
        ambiguity = result.ambiguity
        reason = result.reason
        worthChanging = result.worthChanging
    }
}

@MainActor
final class ReviewModel: ObservableObject {
    private let preferredProviderKey = "preferredReviewProvider"
    @Published var source = ""
    @Published var targetLocale = LanguageChoice.defaultTarget.rawValue
    @Published var referenceLocale = LanguageChoice.defaultReference.rawValue
    @Published var english = ""
    @Published var chinese = ""
    @Published var lastGeneratedChinese = ""
    private var confirmedChineseIntent: String?
    @Published var ambiguity: String?
    @Published var reason: String?
    @Published var worthChanging = true
    @Published var isReady = false
    @Published var captureFailed = false
    @Published var richTextRisk = false
    @Published var replaceShortcutText = "⌥⌘↩"
    @Published var candidates: [ReviewCandidate] = []
    @Published private(set) var revealedProviders: Set<String> = []
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
    var onLanguagesChanged: (() -> Void)?

    var targetLanguage: LanguageChoice { LanguageChoice(rawValue: targetLocale) ?? .defaultTarget }
    var referenceLanguage: LanguageChoice { LanguageChoice(rawValue: referenceLocale) ?? .defaultReference }

    func changeTargetLanguage(to locale: String) {
        guard targetLocale != locale, LanguageChoice(rawValue: locale) != nil else { return }
        targetLocale = locale
        onLanguagesChanged?()
    }

    func changeReferenceLanguage(to locale: String) {
        guard referenceLocale != locale, LanguageChoice(rawValue: locale) != nil else { return }
        referenceLocale = locale
        onLanguagesChanged?()
    }

    var hasReplacement: Bool {
        isReady && isSelectedResultRevealed
            && !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && english != source
    }

    var isSelectedResultRevealed: Bool {
        candidates.indices.contains(selectedCandidateIndex)
            && revealedProviders.contains(candidates[selectedCandidateIndex].provider)
    }

    var replacementUnavailableReason: String? {
        guard isReady, isSelectedResultRevealed else { return nil }
        if english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Selected suggestion is empty. Enter text to enable Replace."
        }
        if english == source {
            return "Selected suggestion matches the original. Edit it to enable Replace."
        }
        return nil
    }

    var canReplaceFromPanel: Bool {
        hasReplacement && !isReplacing && (!usedKeyboardFallback || canRestoreFocus)
    }

    var canRegenerate: Bool { !isLoading && !source.isEmpty }

    var editedChineseIntent: String? {
        let edited = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !edited.isEmpty else { return nil }
        return edited == lastGeneratedChinese ? confirmedChineseIntent : edited
    }

    func resetChineseIntent() {
        confirmedChineseIntent = nil
    }

    var regenerateTitle: String {
        editedChineseIntent == nil ? "Regenerate" : "Regenerate from meaning check"
    }

    func beginResults(providers: [String]) {
        providerNames = providers
        providerErrors = [:]
        candidates = []
        revealedProviders = []
        selectedCandidateIndex = 0
        selectedThisRequest = false
        isReady = false
    }

    func receive(_ candidate: ReviewCandidate, deferReveal: Bool = false) {
        guard providerNames.contains(candidate.provider) else { return }
        if !deferReveal { revealedProviders.insert(candidate.provider) }
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

    func revealPendingResults() {
        let providers = Set(candidates.map(\.provider))
        guard !providers.isSubset(of: revealedProviders) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            revealedProviders.formUnion(providers)
        }
    }

    func copySelectedSuggestion() {
        guard isSelectedResultRevealed, candidates.indices.contains(selectedCandidateIndex) else { return }
        onCopyCandidate?(candidates[selectedCandidateIndex].provider)
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
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            confirmedChineseIntent = nil
        }
        if index != selectedCandidateIndex {
            selectCandidate(at: index)
        } else {
            selectedThisRequest = true
            chinese = value
        }
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

    @discardableResult
    func regenerateFromPanel() -> Bool {
        guard canRegenerate, let onRegenerate else { return false }
        confirmedChineseIntent = editedChineseIntent
        onRegenerate()
        return true
    }

    private func loadCandidate(at index: Int) {
        let candidate = candidates[index]
        english = candidate.english
        chinese = candidate.chinese
        lastGeneratedChinese = candidate.generatedChinese
        ambiguity = candidate.ambiguity
        reason = candidate.reason
        worthChanging = candidate.worthChanging
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
    private var hoverPanel: NSPanel?
    private var hoverAction: ReviewHoverAction?
    private var hoveredActionID: String?
    private var hoverPointer: CGPoint?
    private var hoveringSidecar = false
    private var pendingHoverShow: Task<Void, Never>?
    private var pendingHoverHide: Task<Void, Never>?
    private var measuredContentHeight: CGFloat?
    private var userResized = false
    private var automaticResizeGeneration = 0
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
        super.init()
        let hostingView = NSHostingView(rootView: ReviewView(
            model: model, history: history,
            onContentHeightChange: { [weak self] height in self?.contentHeightChanged(height) },
            onHoverAction: { [weak self] action, hovering in
                self?.updateHover(action, hovering: hovering)
            }))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.center()
        panel.delegate = self
        panel.onMoveSelection = { [weak self] offset in
            self?.model.moveSelection(by: offset) ?? false
        }
        panel.onReturn = { [weak self] in
            self?.model.replaceFromPanel() ?? false
        }
        panel.onRegenerate = { [weak self] in
            _ = self?.model.regenerateFromPanel()
        }
    }

    func prepareForNewCapture() {
        measuredContentHeight = nil
        userResized = false
    }

    func show(near fieldBounds: CGRect? = nil) {
        let wasVisible = panel.isVisible
        positioning = true
        defer { positioning = false }
        let providerCount = max(1, model.providerNames.count)
        let sourceHeight = ReviewEditorHeight.calculate(
            text: model.source, width: 580, minimum: 28, maximum: 100, verticalInset: 4) + 14
        let loadingHeight = 48 + sourceHeight + (model.captureNotice.isEmpty ? 0 : 28)
            + 35 + CGFloat(providerCount) * 105 + 70
        let preferredHeight: CGFloat = model.captureFailed ? 210 :
            (measuredContentHeight ?? loadingHeight)
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
        positionHoverPanel()
        if let measuredContentHeight, !model.candidates.isEmpty {
            contentHeightChanged(measuredContentHeight)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        hideHoverPanel()
        panel.close()
    }

    func hideForReplacement() {
        hideHoverPanel()
        panel.orderOut(nil)
    }

    private func updateHover(_ action: ReviewHoverAction?, hovering: Bool) {
        guard let action else {
            hideHoverPanel()
            return
        }
        pendingHoverShow?.cancel()
        pendingHoverHide?.cancel()
        if hovering {
            hoveredActionID = action.id
            hoverPointer = NSEvent.mouseLocation
            if hoverPanel?.isVisible == true {
                showHoverPanel(for: action)
            } else {
                pendingHoverShow = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(180))
                    guard let self, !Task.isCancelled,
                          self.hoveredActionID == action.id else { return }
                    self.showHoverPanel(for: action)
                }
            }
        } else if hoveredActionID == action.id {
            hoveredActionID = nil
            scheduleHoverHide()
        }
    }

    private func showHoverPanel(for action: ReviewHoverAction) {
        guard panel.isVisible else { return }
        if hoverPanel == nil {
            let sidecar = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 140),
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
            sidecar.isOpaque = false
            sidecar.backgroundColor = .clear
            sidecar.hasShadow = true
            sidecar.hidesOnDeactivate = false
            sidecar.isReleasedWhenClosed = false
            sidecar.acceptsMouseMovedEvents = true
            hoverPanel = sidecar
            panel.addChildWindow(sidecar, ordered: .above)
        }
        guard let hoverPanel else { return }
        if hoverAction != action {
            let hostingView = NSHostingView(rootView: ReviewActionCard(
                title: action.title, detail: action.detail, shortcuts: action.shortcuts)
                .onHover { [weak self] hovering in
                    guard let self else { return }
                    self.hoveringSidecar = hovering
                    self.pendingHoverHide?.cancel()
                    if !hovering && self.hoveredActionID == nil { self.scheduleHoverHide() }
                })
            hostingView.sizingOptions = [.intrinsicContentSize]
            hoverPanel.contentView = hostingView
            let height = min(max(hostingView.fittingSize.height, 88), 240)
            hoverPanel.setContentSize(NSSize(width: 280, height: height))
            hoverAction = action
        }
        positionHoverPanel()
        hoverPanel.orderFront(nil)
    }

    private func scheduleHoverHide() {
        pendingHoverHide?.cancel()
        pendingHoverHide = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled,
                  self.hoveredActionID == nil, !self.hoveringSidecar else { return }
            self.hideHoverPanel()
        }
    }

    private func hideHoverPanel() {
        pendingHoverShow?.cancel()
        pendingHoverHide?.cancel()
        hoveredActionID = nil
        hoverPointer = nil
        hoveringSidecar = false
        hoverPanel?.orderOut(nil)
    }

    private func positionHoverPanel() {
        guard let hoverPanel, let hoverPointer,
              hoverPanel.isVisible || hoverAction != nil else { return }
        let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        let origin = ReviewHoverPlacement.origin(review: panel.frame,
                                                 pointer: hoverPointer,
                                                 sidecar: hoverPanel.frame.size,
                                                 visible: visibleFrame)
        hoverPanel.setFrameOrigin(origin)
    }

    private func contentHeightChanged(_ height: CGFloat) {
        guard height.isFinite else { return }
        measuredContentHeight = height
        guard panel.isVisible else { return }
        guard !userResized, !model.captureFailed else {
            model.revealPendingResults()
            return
        }
        let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        let desiredContentHeight = min(max(340, height), visibleFrame.height * 0.88)
        let contentHeight = panel.contentRect(forFrameRect: panel.frame).height
        guard abs(contentHeight - desiredContentHeight) > 3 else {
            if !positioning { model.revealPendingResults() }
            return
        }
        let frameHeight = panel.frame.height + desiredContentHeight - contentHeight
        let oldFrame = panel.frame
        let target = PanelPlacement.clamp(
            CGPoint(x: oldFrame.minX, y: oldFrame.maxY - frameHeight),
            panelSize: CGSize(width: oldFrame.width, height: frameHeight),
            visibleFrame: visibleFrame)
        let targetFrame = CGRect(origin: target, size: CGSize(width: oldFrame.width, height: frameHeight))
        automaticResizeGeneration += 1
        let generation = automaticResizeGeneration
        positioning = true
        lastAutomaticOrigin = target
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.36
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.08, 0.32, 1)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.automaticResizeGeneration == generation else { return }
                self.positioning = false
                self.model.revealPendingResults()
            }
        }
    }


    func windowWillClose(_ notification: Notification) {
        hideHoverPanel()
        onDismiss?()
    }

    func windowDidMove(_ notification: Notification) {
        positionHoverPanel()
        guard !positioning, panel.isVisible else { return }
        let origin = panel.frame.origin
        if let lastAutomaticOrigin,
           abs(origin.x - lastAutomaticOrigin.x) < 1,
           abs(origin.y - lastAutomaticOrigin.y) < 1 { return }
        UserDefaults.standard.set(Double(origin.x), forKey: savedXKey)
        UserDefaults.standard.set(Double(origin.y), forKey: savedYKey)
    }

    func windowDidResize(_ notification: Notification) {
        positionHoverPanel()
        guard panel.isVisible, !positioning else { return }
        userResized = true
    }

    private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let rect = a.intersection(b)
        return rect.isNull ? 0 : rect.width * rect.height
    }
}

enum ReviewHoverPlacement {
    static func origin(review: CGRect, pointer: CGPoint, sidecar: CGSize, visible: CGRect,
                       gap: CGFloat = 8) -> CGPoint {
        let right = review.maxX + gap
        let left = review.minX - gap - sidecar.width
        let x: CGFloat
        let rightFits = right + sidecar.width <= visible.maxX
        let leftFits = left >= visible.minX
        if pointer.x >= review.midX && rightFits {
            x = right
        } else if pointer.x < review.midX && leftFits {
            x = left
        } else if rightFits {
            x = right
        } else if leftFits {
            x = left
        } else {
            x = min(max(pointer.x - sidecar.width / 2, visible.minX),
                    visible.maxX - sidecar.width)
        }
        let above = review.maxY + gap
        let below = review.minY - gap - sidecar.height
        let aboveFits = above + sidecar.height <= visible.maxY
        let belowFits = below >= visible.minY
        let desiredY: CGFloat
        if !rightFits && !leftFits && pointer.y >= review.midY && aboveFits {
            desiredY = above
        } else if !rightFits && !leftFits && pointer.y < review.midY && belowFits {
            desiredY = below
        } else if !rightFits && !leftFits && aboveFits {
            desiredY = above
        } else if !rightFits && !leftFits && belowFits {
            desiredY = below
        } else {
            desiredY = pointer.y >= review.midY
                ? pointer.y - sidecar.height : pointer.y
        }
        let y = min(max(desiredY, visible.minY),
                    visible.maxY - sidecar.height)
        return CGPoint(x: x, y: y)
    }
}

enum ReviewPanelKeyAction: Equatable {
    case regenerate
    case replace
    case moveSelection(Int)

    static func resolve(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isEditing: Bool) -> Self? {
        let relevant = modifiers.intersection([.command, .option, .control, .shift])
        let isReturn = keyCode == 36 || keyCode == 76
        if isReturn && relevant == .command { return .regenerate }
        guard relevant.isEmpty, !isEditing else { return nil }
        if isReturn { return .replace }
        if keyCode == 125 { return .moveSelection(1) }
        if keyCode == 126 { return .moveSelection(-1) }
        return nil
    }
}

private final class EscapeClosingPanel: NSPanel {
    var onMoveSelection: ((Int) -> Bool)?
    var onReturn: (() -> Bool)?
    var onRegenerate: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let action = ReviewPanelKeyAction.resolve(keyCode: event.keyCode,
                                                     modifiers: event.modifierFlags,
                                                     isEditing: firstResponder is NSTextView) {
            switch action {
            case .regenerate:
                onRegenerate?()
                return
            case .replace:
                if onReturn?() == true { return }
            case .moveSelection(let offset):
                if onMoveSelection?(offset) == true { return }
            }
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) { close() }
}

private struct ReviewSectionHeights: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private extension View {
    func reportReviewHeight(_ section: String) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: ReviewSectionHeights.self,
                                       value: [section: geometry.size.height])
            }
        }
    }
}

private struct ReviewHoverAction: Equatable {
    let id: String
    let title: String
    let detail: String
    let shortcuts: [String]
}

private struct ReviewActionCard: View {
    let title: String
    let detail: String
    let shortcuts: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !shortcuts.isEmpty {
                Divider()
                HStack(spacing: 5) {
                    Text("Shortcut")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    ForEach(shortcuts.indices, id: \.self) { index in
                        if index > 0 {
                            Text("or")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(shortcuts[index])
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color.secondary.opacity(0.18)))
    }
}

private struct ReviewView: View {
    @ObservedObject var model: ReviewModel
    @ObservedObject var history: HistoryStore
    let onContentHeightChange: (CGFloat) -> Void
    let onHoverAction: (ReviewHoverAction?, Bool) -> Void
    @State private var showingHistory = false
    @State private var sourceWidth: CGFloat = 500

    var body: some View {
        GeometryReader { geometry in
            let compact = CGFloat(180 + 230 * max(1, model.providerNames.count)) > geometry.size.height
            VStack(spacing: 0) {
                header.reportReviewHeight("header").zIndex(1)
                if model.captureFailed {
                    captureError
                } else {
                    sourceSection(compact: compact)
                        .padding(.horizontal, 16)
                        .padding(.top, compact ? 4 : 8)
                        .padding(.bottom, compact ? 2 : 4)
                        .reportReviewHeight("source")
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                                HStack {
                                    sectionLabel("RESULTS", icon: "square.stack")
                                    Spacer()
                                }
                                ForEach(model.providerNames, id: \.self) { provider in
                                    resultCard(for: provider, compact: compact)
                                        .id(provider)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, compact ? 6 : 10)
                            .reportReviewHeight("results")
                            .animation(.spring(response: 0.42, dampingFraction: 0.82),
                                       value: model.providerErrors.count)
                        }
                        .onChange(of: model.selectedCandidateIndex) { _, index in
                            guard model.candidates.indices.contains(index) else { return }
                            withAnimation {
                                scrollProxy.scrollTo(model.candidates[index].provider, anchor: .center)
                            }
                        }
                    }
                    footer.reportReviewHeight("footer")
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
        .tint(.blue)
        .onPreferenceChange(ReviewSectionHeights.self) { sections in
            guard !model.captureFailed,
                  let header = sections["header"], let source = sections["source"],
                  let results = sections["results"], let footer = sections["footer"] else { return }
            onContentHeightChange(header + source + results + footer)
        }
        .onExitCommand { model.onClose?() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Review").font(.headline)
            Spacer(minLength: 8)
            languageMenu
            if model.isLoading { ProgressView().controlSize(.small) }
            Button {
                onHoverAction(nil, false)
                showingHistory.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .onHover { hovering in
                onHoverAction(ReviewHoverAction(id: "history", title: "History",
                                                detail: "Browse and copy earlier suggestions",
                                                shortcuts: []), hovering)
            }
            .accessibilityLabel("History")
            .accessibilityHint("Open review history")
            .popover(isPresented: $showingHistory, arrowEdge: .trailing) {
                HistoryQuickView(history: history) {
                    showingHistory = false
                    model.onOpenHistory?()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 5)
    }

    private var languageMenu: some View {
        Menu {
            Menu("Write in") {
                if !LanguageChoice.primaryTargets.contains(model.targetLanguage) {
                    Button {
                        model.changeTargetLanguage(to: model.targetLocale)
                    } label: {
                        Label(model.targetLanguage.title, systemImage: "checkmark")
                    }
                    Divider()
                }
                ForEach(LanguageChoice.primaryTargets) { language in
                    Button {
                        model.changeTargetLanguage(to: language.rawValue)
                    } label: {
                        if language == model.targetLanguage {
                            Label(language.title, systemImage: "checkmark")
                        } else {
                            Text(language.title)
                        }
                    }
                }
                Divider()
                Menu("More languages…") {
                    ForEach(LanguageChoice.moreTargets.filter { $0 != model.targetLanguage }) { language in
                        Button(language.title) { model.changeTargetLanguage(to: language.rawValue) }
                    }
                }
            }
            Menu("Check meaning in") {
                if !LanguageChoice.primaryReferences.contains(model.referenceLanguage) {
                    Button {
                        model.changeReferenceLanguage(to: model.referenceLocale)
                    } label: {
                        Label(model.referenceLanguage.title, systemImage: "checkmark")
                    }
                    Divider()
                }
                ForEach(LanguageChoice.primaryReferences) { language in
                    Button {
                        model.changeReferenceLanguage(to: language.rawValue)
                    } label: {
                        if language == model.referenceLanguage {
                            Label(language.title, systemImage: "checkmark")
                        } else {
                            Text(language.title)
                        }
                    }
                }
                Divider()
                Menu("More languages…") {
                    ForEach(LanguageChoice.moreReferences.filter { $0 != model.referenceLanguage }) { language in
                        Button(language.title) { model.changeReferenceLanguage(to: language.rawValue) }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "globe")
                Text("Write \(model.targetLanguage.title) · Check \(model.referenceLanguage.title)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .tint(.primary)
        .onHover { hovering in
            onHoverAction(ReviewHoverAction(id: "languages", title: "Languages",
                                            detail: "Choose the writing and meaning-check languages. Changing either regenerates the results.",
                                            shortcuts: []), hovering)
        }
        .accessibilityLabel("Write in \(model.targetLanguage.title), check meaning in \(model.referenceLanguage.title)")
        .accessibilityHint("Changing languages regenerates the results")
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

    private func sourceSection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            ScrollView {
                Text(model.source)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .id(model.source)
            .frame(height: ReviewEditorHeight.calculate(
                text: model.source, width: sourceWidth,
                minimum: compact ? 28 : 54, maximum: compact ? 100 : 140,
                verticalInset: 4))
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { sourceWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, newWidth in sourceWidth = newWidth }
                }
            }
            .padding(compact ? 7 : 9)
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.secondary.opacity(0.09))
                    .overlay(alignment: .bottomTrailing) {
                        Text("ORIGINAL")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(Color.secondary.opacity(0.12))
                            .padding(.trailing, 8)
                            .padding(.bottom, 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
            }
            if !model.captureNotice.isEmpty {
                Label(model.captureNotice, systemImage: "keyboard")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func resultCard(for provider: String, compact: Bool) -> some View {
        let index = model.candidates.firstIndex(where: { $0.provider == provider })
        VStack(alignment: .leading, spacing: compact ? 5 : 9) {
            HStack(spacing: 8) {
                ProviderIcon(name: provider, size: 20)
                Text(provider).font(.callout.weight(.semibold))
                if let index, model.revealedProviders.contains(provider),
                   index != model.selectedCandidateIndex,
                   let ambiguity = model.candidates[index].ambiguity, !ambiguity.isEmpty {
                    Image(systemName: "questionmark.bubble")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help(ambiguity)
                        .accessibilityLabel("Possible ambiguity: \(ambiguity)")
                }
                Spacer()
                if let index, model.revealedProviders.contains(provider) {
                    Button {
                        model.selectCandidate(at: index)
                    } label: {
                        Image(systemName: index == model.selectedCandidateIndex
                              ? "checkmark.circle.fill" : "circle")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == model.selectedCandidateIndex ? Color.blue : Color.secondary)
                    .onHover { hovering in
                        onHoverAction(ReviewHoverAction(
                            id: "result:\(provider)",
                            title: index == model.selectedCandidateIndex ? "Selected result" : "Select result",
                            detail: "Use \(provider) for Replace. Arrow keys switch results outside text fields.",
                            shortcuts: ["↑", "↓"]), hovering)
                    }
                    .accessibilityLabel(index == model.selectedCandidateIndex
                                        ? "\(provider) selected for Replace" : "Select \(provider) for Replace")
                    .accessibilityHint("Up and down arrows switch results outside text fields")
                } else if model.providerErrors[provider] == nil {
                    ProgressView().controlSize(.small)
                }
            }
            if let index {
                let candidate = model.candidates[index]
                let revealed = model.revealedProviders.contains(provider)
                VStack(alignment: .leading, spacing: compact ? 5 : 9) {
                    ReviewTextEditor(text: Binding(
                        get: { model.candidates.first(where: { $0.provider == provider })?.english ?? "" },
                        set: { model.editEnglish($0, for: provider) }),
                        minimumHeight: compact ? 44 : 66, maximumHeight: compact ? 120 : 160,
                        enabled: revealed && model.isReady && !model.isReplacing)
                        .accessibilityLabel("\(provider) suggestion in \(model.targetLanguage.title)")
                        .simultaneousGesture(TapGesture().onEnded {
                            if revealed && index != model.selectedCandidateIndex { model.selectCandidate(at: index) }
                        })
                    if index == model.selectedCandidateIndex,
                       let reason = candidate.reason, !reason.isEmpty {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ReviewTextEditor(text: Binding(
                        get: { model.candidates.first(where: { $0.provider == provider })?.chinese ?? "" },
                        set: { model.editChinese($0, for: provider) }),
                        minimumHeight: compact ? 40 : 54, maximumHeight: compact ? 120 : 160,
                        enabled: revealed && model.isReady && !model.isReplacing)
                        .accessibilityLabel("\(provider) meaning check in \(model.referenceLanguage.title)")
                        .simultaneousGesture(TapGesture().onEnded {
                            if revealed && index != model.selectedCandidateIndex { model.selectCandidate(at: index) }
                        })
                    if index == model.selectedCandidateIndex,
                       let ambiguity = candidate.ambiguity, !ambiguity.isEmpty {
                        Label(ambiguity, systemImage: "questionmark.bubble")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .opacity(revealed ? 1 : 0)
                .allowsHitTesting(revealed)
                .overlay(alignment: .topLeading) {
                    if !revealed { pendingPlaceholder }
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
                pendingPlaceholder
            }
        }
        .padding(compact ? 9 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.05))
                .onTapGesture {
                    if let index, model.revealedProviders.contains(provider),
                       index != model.selectedCandidateIndex { model.selectCandidate(at: index) }
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(index == model.selectedCandidateIndex ? Color.blue.opacity(0.65) : Color.secondary.opacity(0.12)))
    }

    private var pendingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.12))
                .frame(height: 22).frame(maxWidth: 280, alignment: .leading)
            RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.08))
                .frame(height: 18).frame(maxWidth: 180, alignment: .leading)
        }
        .transition(.opacity)
        .accessibilityHidden(true)
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
            if let reason = model.replacementUnavailableReason {
                Label(reason, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(model.regenerateTitle) { model.regenerateFromPanel() }
                    .disabled(!model.canRegenerate)
                    .onHover { hovering in
                        onHoverAction(ReviewHoverAction(id: "regenerate", title: model.regenerateTitle,
                                                        detail: "Request fresh suggestions using the current meaning check.",
                                                        shortcuts: ["⌘↩"]), hovering)
                    }
                    .accessibilityHint("Command Return")
                if model.isSelectedResultRevealed {
                    Button { model.copySelectedSuggestion() } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .onHover { hovering in
                        onHoverAction(ReviewHoverAction(id: "copy", title: "Copy suggestion",
                                                        detail: "Copy the selected result in \(model.targetLanguage.title).",
                                                        shortcuts: []), hovering)
                    }
                    .accessibilityHint("Copy the selected suggestion")
                }
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
                        .onHover { hovering in
                            onHoverAction(ReviewHoverAction(
                                id: "replace", title: "Replace",
                                detail: model.usedKeyboardFallback
                                    ? "Refocus the original input and replace its text. Return works outside text fields."
                                    : "Replace the original input with the selected suggestion. Return works outside text fields.",
                                shortcuts: ["↩", model.replaceShortcutText]), hovering)
                        }
                        .accessibilityHint("Return outside text fields or \(model.replaceShortcutText)")
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

}
