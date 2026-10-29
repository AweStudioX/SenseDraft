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
    @State private var selectedEntryID: UUID?
    @State private var confirmingClear = false

    private var visibleEntries: [HistoryEntry] {
        history.entries.filter { entry in
            (filter == .all || entry.replaced) &&
            (search.isEmpty || [entry.source, entry.english, entry.chinese]
                .contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("History").font(.title2.bold())
                    Text("Encrypted on this Mac · \(history.entries.count) saved")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Save history", isOn: $settings.historyEnabled)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    TextField("Search history", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Search history")
                        .padding(12)
                    Picker("Filter", selection: $filter) {
                        ForEach(HistoryFilter.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    Divider()
                    if visibleEntries.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(history.entries.isEmpty ? "Your history starts here" : "No matching history")
                                .font(.callout.weight(.medium))
                            if history.entries.isEmpty {
                                Text(settings.historyEnabled
                                     ? "The next analysis will appear here."
                                     : "Turn on Save history to keep future suggestions.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(20)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(visibleEntries) { entry in
                                    Button { selectedEntryID = entry.id } label: {
                                        historyRow(entry)
                                    }
                                    .buttonStyle(.plain)
                                    .background(selectedEntryID == entry.id ? Color.accentColor.opacity(0.15) : .clear,
                                                in: RoundedRectangle(cornerRadius: 9))
                                }
                            }
                            .padding(8)
                        }
                    }
                }
                .frame(width: 258)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()
                if let selected = history.entries.first(where: { $0.id == selectedEntryID }) {
                    HistoryDetailView(entry: selected, history: history) { selectedEntryID = nil }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("Select an analysis").font(.title3.weight(.semibold))
                        Text("Its English, meaning, and original text appear here.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack {
                if let errorMessage = history.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Picker("Keep history for", selection: $settings.historyRetention) {
                    ForEach(HistoryRetention.allCases) { option in Text(option.title).tag(option) }
                }
                .frame(width: 175)
                Button("Clear all", role: .destructive) { confirmingClear = true }
                    .disabled(history.entries.isEmpty && history.errorMessage == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .confirmationDialog("Delete all saved history?", isPresented: $confirmingClear) {
            Button("Delete all history", role: .destructive) {
                history.clear()
                selectedEntryID = nil
            }
        } message: {
            Text("This removes every saved analysis from this Mac.")
        }
        .navigationTitle("History")
        .onAppear {
            history.pruneExpired()
            selectedEntryID = visibleEntries.first?.id
        }
        .onChange(of: settings.historyRetention) { _, value in history.setRetention(value) }
        .onChange(of: visibleEntries.map(\.id)) { _, ids in
            if let selectedEntryID, ids.contains(selectedEntryID) { return }
            selectedEntryID = ids.first
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.replaced ? "checkmark.circle.fill" : "sparkles")
                .font(.title3)
                .foregroundStyle(entry.replaced ? Color.green : Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.english)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.source.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption)
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
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistoryDetailView: View {
    let entry: HistoryEntry
    @ObservedObject var history: HistoryStore
    let onDelete: () -> Void
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Delete this history entry?", isPresented: $confirmingDelete) {
            Button("Delete entry", role: .destructive) {
                if history.remove(entry.id) { onDelete() }
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
