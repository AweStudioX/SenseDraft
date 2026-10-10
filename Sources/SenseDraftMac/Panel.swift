import AppKit
import SwiftUI

@MainActor
final class ReviewModel: ObservableObject {
    @Published var source = ""
    @Published var english = ""
    @Published var chinese = ""
    @Published var ambiguity: String?
    @Published var message = ""
    @Published var isLoading = false
    var onRegenerate: (() -> Void)?
    var onCopy: (() -> Void)?
    var onClose: (() -> Void)?
}

@MainActor
final class ReviewPanel {
    let model = ReviewModel()
    private let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 510), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "SenseDraft"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ReviewView(model: model))
        panel.center()
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { panel.close() }
}

private struct ReviewView: View {
    @ObservedObject var model: ReviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SenseDraft").font(.title2.bold())
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
            }
            Text("Original input").font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView {
                Text(model.source).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(height: 70)
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Text("Improved English").font(.caption.bold()).foregroundStyle(.secondary)
            TextEditor(text: $model.english).frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

            Text("Chinese interpretation — edit if the meaning is wrong")
                .font(.caption.bold()).foregroundStyle(.secondary)
            TextEditor(text: $model.chinese).frame(height: 85)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

            if let ambiguity = model.ambiguity, !ambiguity.isEmpty {
                Label(ambiguity, systemImage: "questionmark.bubble")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Text(model.message).font(.callout).foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                Button("Regenerate from Chinese") { model.onRegenerate?() }
                    .disabled(model.isLoading || model.chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Copy English") { model.onCopy?() }
                    .disabled(model.english.isEmpty)
                Spacer()
                Text("Replace: ⌘⌥↩").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .onExitCommand { model.onClose?() }
    }
}
