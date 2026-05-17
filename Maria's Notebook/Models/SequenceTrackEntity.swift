import Foundation
import CoreData

@objc(CDSequenceTrackEntity)
public class CDSequenceTrackEntity: NSManagedObject {
    // MARK: - Attributes
    @NSManaged public var id: UUID?
    @NSManaged public var area: String
    @NSManaged public var sequence: String
    @NSManaged public var isSequential: Bool
    @NSManaged public var isExplicitlyDisabled: Bool
    @NSManaged public var createdAt: Date?

    // MARK: - Relationships
    @NSManaged public var track: CDTrackEntity?

    // MARK: - Convenience Init
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "SequenceTrack", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.area = ""
        self.sequence = ""
        self.isSequential = true
        self.isExplicitlyDisabled = false
        self.createdAt = Date()
    }
}

// MARK: - Computed Properties
extension CDSequenceTrackEntity {
    /// Unique identifier for this (area, sequence) combination
    var sequenceKey: String {
        "\(area)|\(sequence)"
    }
}
