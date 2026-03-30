import Foundation
import CoreData
import SwiftUI

/// WorkStep model representing a single step in a Report-type WorkModel.
/// Steps are ordered by orderIndex to ensure deterministic progression.
@objc(WorkStep)
public class WorkStep: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var orderIndex: Int64
    @NSManaged public var title: String
    @NSManaged public var instructions: String
    @NSManaged public var completedAt: Date?
    @NSManaged public var notes: String
    @NSManaged public var completionOutcomeRaw: String?
    @NSManaged public var createdAt: Date?

    // MARK: - Relationships
    @NSManaged public var work: WorkModel?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "WorkStep", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.orderIndex = 0
        self.title = ""
        self.instructions = ""
        self.completedAt = nil
        self.notes = ""
        self.completionOutcomeRaw = nil
        self.createdAt = Date()
    }
}

// MARK: - Computed Properties

extension WorkStep {
    /// Computed convenience for completion check
    var isCompleted: Bool { completedAt != nil }

    /// Completion outcome (reuses CompletionOutcome enum from WorkTypes)
    var completionOutcome: CompletionOutcome? {
        get { completionOutcomeRaw.flatMap { CompletionOutcome(rawValue: $0) } }
        set { completionOutcomeRaw = newValue?.rawValue }
    }

    // MARK: - Styling

    /// Icon name based on completion status and outcome
    var iconName: String {
        guard isCompleted else { return "circle" }
        if let outcome = completionOutcome {
            return outcome.iconName
        }
        return "checkmark.circle.fill"
    }

    /// Color based on completion status and outcome
    var statusColor: Color {
        guard isCompleted else { return .secondary }
        if let outcome = completionOutcome {
            return outcome.color
        }
        return .green
    }
}
