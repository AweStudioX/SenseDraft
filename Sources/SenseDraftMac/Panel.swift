import AppKit
import SenseDraftCore
import SwiftUI

@MainActor
final class ReviewModel: ObservableObject {
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
    @Published var captureNotice = ""
    @Published var usedKeyboardFallback = false
    @Published var canRestoreFocus = false
    @Published var message = ""
    @Published var isLoading = false
    var onRegenerate: (() -> Void)?
    var onCopy: (() -> Void)?
    var onReplace: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onClose: (() -> Void)?
}

@MainActor
final class ReviewPanel: NSObject, NSWindowDelegate {
    let model = ReviewModel()
    private let panel: NSPanel
    private let history: HistoryStore
    private let savedXKey = "reviewPanelManualX"
    private let savedYKey = "reviewPanelManualY"
    private var positioning = false
    private var lastAutomaticOrigin: CGPoint?
    var onDismiss: (() -> Void)?

    init(history: HistoryStore) {
        self.history = history
        panel = EscapeClosingPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 410),
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
    }

    func show(near fieldBounds: CGRect? = nil) {
        let wasVisible = panel.isVisible
        positioning = true
        defer { positioning = false }
        let preferredHeight: CGFloat = model.captureFailed ? 210 : 410
        panel.minSize = NSSize(width: 500, height: model.captureFailed ? 210 : 340)
        if !wasVisible {
            let visibleHeight = NSScreen.main?.visibleFrame.height ?? preferredHeight
            panel.setContentSize(NSSize(width: 560, height: min(preferredHeight, visibleHeight)))
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
    override func cancelOperation(_ sender: Any?) { close() }
}

private struct ReviewView: View {
    @ObservedObject var model: ReviewModel
    @ObservedObject var history: HistoryStore
    @State private var showingHistory = false

    private var hasReplacement: Bool {
        model.isReady && !model.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && model.english != model.source
    }

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
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            let extraHeight = max(0, geometry.size.height - 220)
                            suggestionSection(editorHeight: 70 + extraHeight * 0.6)
                            meaningSection(editorHeight: 58 + extraHeight * 0.4)
                            if let ambiguity = model.ambiguity, !ambiguity.isEmpty {
                                Label(ambiguity, systemImage: "questionmark.bubble")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
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
                Text(model.captureFailed ? "Input unavailable" : (model.isReady ? (hasReplacement ? "Ready" : "No change") : "Waiting"))
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
            .frame(height: 36)
            .padding(9)
            .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            if !model.captureNotice.isEmpty {
                Label(model.captureNotice, systemImage: "keyboard")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func suggestionSection(editorHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                sectionLabel("SUGGESTED ENGLISH", icon: "sparkles")
                Spacer()
                Text("Editable").font(.caption2).foregroundStyle(.tertiary)
            }
            editor(text: $model.english, height: editorHeight, enabled: model.isReady && !model.isLoading)
                .accessibilityLabel("Suggested English")
            if let reason = model.reason, !reason.isEmpty {
                Text(reason).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func meaningSection(editorHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                sectionLabel("CHINESE MEANING", icon: "character.book.closed")
                Spacer()
                Text("Edit if needed").font(.caption2).foregroundStyle(.tertiary)
            }
            editor(text: $model.chinese, height: editorHeight, enabled: model.isReady && !model.isLoading)
                .accessibilityLabel("Chinese interpretation")
        }
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
                Button("Copy English") { model.onCopy?() }
                    .disabled(!model.isReady || model.english.isEmpty)
                Spacer()
                if hasReplacement {
                    if model.usedKeyboardFallback && !model.canRestoreFocus {
                        Text("Return to editor · \(model.replaceShortcutText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button { model.onReplace?() } label: {
                            Label("Replace", systemImage: "return")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isLoading)
                        Text(model.replaceShortcutText)
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
