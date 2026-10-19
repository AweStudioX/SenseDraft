import AppKit
import SenseDraftCore
import SwiftUI

private enum HistoryFilter: String, CaseIterable {
    case all = "All"
    case replaced = "Replaced"
}

struct HistoryView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryStore
    @State private var search = ""
    @State private var filter: HistoryFilter = .all
    @State private var selectedEntry: HistoryEntry?
    @State private var confirmingClear = false

    private var visibleEntries: [HistoryEntry] {
        history.entries.filter { entry in
            (filter == .all || entry.replaced) &&
            (search.isEmpty || [entry.source, entry.english, entry.chinese]
                .contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text("History").font(.largeTitle.bold())
                    Spacer()
                    Text("\(history.entries.count) saved")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Save analysis history", isOn: $settings.historyEnabled)
                        .font(.headline)
                    Picker("Keep history for", selection: $settings.historyRetention) {
                        ForEach(HistoryRetention.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Text("Saved only on this Mac and encrypted. Choosing 7 or 30 days removes older entries immediately. No limit keeps entries until you delete them and may use more disk space or load more slowly.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))

                if let errorMessage = history.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        if history.entries.isEmpty {
                            Button("Delete unreadable history", role: .destructive) {
                                confirmingClear = true
                            }
                        }
                    }
                }

                if history.entries.isEmpty {
                    emptyState
                } else {
                    HStack(spacing: 12) {
                        TextField("Search original, English, or meaning", text: $search)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Search history")
                        Picker("Filter", selection: $filter) {
                            ForEach(HistoryFilter.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 180)
                    }

                    if visibleEntries.isEmpty {
                        Text("No matching history")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(visibleEntries) { entry in
                                Button { selectedEntry = entry } label: {
                                    historyRow(entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button("Clear all history", role: .destructive) { confirmingClear = true }
                        .font(.callout)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .confirmationDialog("Delete all saved history?", isPresented: $confirmingClear) {
            Button("Delete all history", role: .destructive) { history.clear() }
        } message: {
            Text("This removes every saved analysis from this Mac.")
        }
        .sheet(item: $selectedEntry) { entry in
            HistoryDetailView(entry: entry, history: history)
        }
        .navigationTitle("History")
        .onAppear { history.pruneExpired() }
        .onChange(of: settings.historyRetention) { _, value in history.setRetention(value) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("Your history starts here")
                .font(.title3.weight(.semibold))
            Text(settings.historyEnabled
                 ? "The next successful analysis will appear here."
                 : "Turn on Save analysis history to keep future suggestions.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: entry.replaced ? "checkmark.circle.fill" : "sparkles")
                .font(.title3)
                .foregroundStyle(entry.replaced ? Color.green : Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.english)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.source.replacingOccurrences(of: "\n", with: " "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(entry.replaced ? "Replaced" : "Analyzed")
                    Text("·")
                    Text(entry.createdAt, style: .date)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct HistoryDetailView: View {
    let entry: HistoryEntry
    @ObservedObject var history: HistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.replaced ? "Replaced suggestion" : "Analysis")
                        .font(.title2.bold())
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(24)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    textSection("ORIGINAL", text: entry.source)
                    textSection("ENGLISH", text: entry.english)
                    textSection("CHINESE MEANING", text: entry.chinese)
                    if let reason = entry.reason, !reason.isEmpty {
                        textSection("WHY", text: reason)
                    }
                    if let ambiguity = entry.ambiguity, !ambiguity.isEmpty {
                        textSection("AMBIGUITY", text: ambiguity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            HStack {
                Button("Copy English") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.english, forType: .string)
                }
                Spacer()
                Button("Delete", role: .destructive) { confirmingDelete = true }
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 480)
        .confirmationDialog("Delete this history entry?", isPresented: $confirmingDelete) {
            Button("Delete entry", role: .destructive) {
                if history.remove(entry.id) { dismiss() }
            }
        }
    }

    private func textSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct HistoryQuickView: View {
    @ObservedObject var history: HistoryStore
    let onManage: () -> Void
    @State private var search = ""
    @State private var selectedID: UUID?

    private var selectedEntry: HistoryEntry? {
        history.entries.first { $0.id == selectedID }
    }

    private var matches: [HistoryEntry] {
        history.entries.filter { entry in
            search.isEmpty || [entry.source, entry.english, entry.chinese]
                .contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if selectedEntry != nil {
                    Button { selectedID = nil } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                } else {
                    Text("History").font(.headline)
                }
                Spacer()
                Button("Manage") { onManage() }
                    .buttonStyle(.borderless)
            }

            if let entry = selectedEntry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        quickSection("ORIGINAL", text: entry.source)
                        quickSection("ENGLISH", text: entry.english)
                        quickSection("CHINESE MEANING", text: entry.chinese)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Copy English") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.english, forType: .string)
                }
            } else if history.entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(history.errorMessage ?? "No saved analyses yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextField("Search history", text: $search)
                    .textFieldStyle(.roundedBorder)
                if matches.isEmpty {
                    Text("No matching history")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(matches) { entry in
                                Button { selectedID = entry.id } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.english)
                                            .font(.callout.weight(.medium))
                                            .lineLimit(2)
                                        Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(9)
                                    .background(Color(nsColor: .controlBackgroundColor),
                                                in: RoundedRectangle(cornerRadius: 9))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 380, height: 420)
        .onAppear { history.pruneExpired() }
    }

    private func quickSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
