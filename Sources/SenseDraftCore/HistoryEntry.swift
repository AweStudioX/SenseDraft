import Foundation

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let source: String
    public var english: String
    public var chinese: String
    public var reason: String?
    public var ambiguity: String?
    public let provider: String
    public var replaced: Bool

    public init(id: UUID = UUID(), createdAt: Date = Date(), source: String,
                english: String, chinese: String, reason: String? = nil,
                ambiguity: String? = nil, provider: String, replaced: Bool = false) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.english = english
        self.chinese = chinese
        self.reason = reason
        self.ambiguity = ambiguity
        self.provider = provider
        self.replaced = replaced
    }
}

public enum HistoryRetention: String, CaseIterable, Codable, Identifiable, Sendable {
    case sevenDays
    case thirtyDays
    case unlimited

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .unlimited: "No limit"
        }
    }

    fileprivate var days: Int? {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        case .unlimited: nil
        }
    }
}

public enum HistoryLedger {
    public static func prune(_ entries: [HistoryEntry], retention: HistoryRetention,
                             now: Date = Date()) -> [HistoryEntry] {
        let cutoff = retention.days.map { now.addingTimeInterval(-TimeInterval($0) * 86_400) }
        return entries.filter { entry in cutoff.map { entry.createdAt >= $0 } ?? true }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public static func upsert(_ entry: HistoryEntry, into entries: [HistoryEntry],
                              retention: HistoryRetention = .unlimited, now: Date = Date()) -> [HistoryEntry] {
        var revised = entry
        if let existing = entries.first(where: { $0.id == entry.id }) {
            revised = HistoryEntry(id: entry.id, createdAt: existing.createdAt,
                                   source: entry.source, english: entry.english, chinese: entry.chinese,
                                   reason: entry.reason, ambiguity: entry.ambiguity,
                                   provider: entry.provider, replaced: existing.replaced)
        }
        return prune([revised] + entries.filter { $0.id != entry.id }, retention: retention, now: now)
    }

    public static func markReplaced(_ id: UUID, english: String, in entries: [HistoryEntry]) -> [HistoryEntry] {
        entries.map { entry in
            guard entry.id == id else { return entry }
            var revised = entry
            revised.english = english
            revised.replaced = true
            return revised
        }
    }
}
