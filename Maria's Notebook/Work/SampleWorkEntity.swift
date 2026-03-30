import Foundation
import CoreData

@objc(SampleWorkEntity)
public class CDSampleWorkEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var workKindRaw: String
    @NSManaged public var orderIndex: Int64
    @NSManaged public var notes: String
    @NSManaged public var createdAt: Date?

    // MARK: - Relationships
    @NSManaged public var lesson: NSManagedObject?   // LessonEntity
    @NSManaged public var steps: NSSet?

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "SampleWork", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.workKindRaw = "practiceLesson"
        self.orderIndex = 0
        self.notes = ""
        self.createdAt = Date()
    }
}

// MARK: - Computed Properties
extension CDSampleWorkEntity {
    /// The work kind this template produces (reuses WorkKind enum)
    var workKind: WorkKind? {
        get { WorkKind(rawValue: workKindRaw) }
        set { workKindRaw = newValue?.rawValue ?? WorkKind.practiceLesson.rawValue }
    }

    /// Returns steps sorted by orderIndex for deterministic display
    var orderedSteps: [CDSampleWorkStepEntity] {
        let stepSet = steps as? Set<CDSampleWorkStepEntity> ?? []
        return stepSet.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Number of steps in this template
    var stepCount: Int {
        (steps as? Set<CDSampleWorkStepEntity>)?.count ?? 0
    }
}

// MARK: - Generated Accessors for steps
extension CDSampleWorkEntity {
    @objc(addStepsObject:)
    @NSManaged public func addToSteps(_ value: CDSampleWorkStepEntity)

    @objc(removeStepsObject:)
    @NSManaged public func removeFromSteps(_ value: CDSampleWorkStepEntity)

    @objc(addSteps:)
    @NSManaged public func addToSteps(_ values: NSSet)

    @objc(removeSteps:)
    @NSManaged public func removeFromSteps(_ values: NSSet)
}
