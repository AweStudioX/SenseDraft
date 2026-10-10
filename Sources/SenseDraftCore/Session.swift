import Foundation

public struct TargetSnapshot: Equatable, Sendable {
    public let appID: String
    public let elementID: String
    public let source: String

    public init(appID: String, elementID: String, source: String) {
        self.appID = appID
        self.elementID = elementID
        self.source = source
    }
}

public struct AnalysisSession: Sendable {
    public let snapshot: TargetSnapshot
    public let generation: UUID

    public init(snapshot: TargetSnapshot, generation: UUID = UUID()) {
        self.snapshot = snapshot
        self.generation = generation
    }

    public func canReplace(currentAppID: String, currentElementID: String, currentValue: String) -> Bool {
        snapshot.appID == currentAppID
            && snapshot.elementID == currentElementID
            && snapshot.source == currentValue
    }

    public func accepts(result: AnalysisResult, for responseGeneration: UUID) -> Bool {
        generation == responseGeneration
    }
}
