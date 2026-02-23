import Foundation

public struct StudentChecklistRowState: Identifiable, Equatable {
    public var id: UUID { lessonID }
    public let lessonID: UUID
    public let plannedItemID: UUID?
    public let presentationLogID: UUID?
    public let contractID: UUID?
    public let isScheduled: Bool
    public let isPresented: Bool
    public let isActive: Bool
    public let isComplete: Bool
    public let lastActivityDate: Date?
    public let isStale: Bool
    public let isInboxPlan: Bool

    public init(
        lessonID: UUID,
        plannedItemID: UUID?,
        presentationLogID: UUID?,
        contractID: UUID?,
        isScheduled: Bool,
        isPresented: Bool,
        isActive: Bool,
        isComplete: Bool,
        lastActivityDate: Date?,
        isStale: Bool,
        isInboxPlan: Bool = false
    ) {
        self.lessonID = lessonID
        self.plannedItemID = plannedItemID
        self.presentationLogID = presentationLogID
        self.contractID = contractID
        self.isScheduled = isScheduled
        self.isPresented = isPresented
        self.isActive = isActive
        self.isComplete = isComplete
        self.lastActivityDate = lastActivityDate
        self.isStale = isStale
        self.isInboxPlan = isInboxPlan
    }
}

