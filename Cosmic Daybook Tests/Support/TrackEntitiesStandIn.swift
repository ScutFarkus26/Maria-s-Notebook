import CoreData
import Foundation
@testable import CosmicDaybook

/// What schema 22 had of the track entities beyond the current model, for
/// tests that open a store written before schema 23
/// (`docs/Plans/Plan - Retire the track entities.md`, Phase 3). The four
/// entities are still in the model, as dormant tombstones in no store
/// (`CoreDataStack.dormantTombstoneEntities`); a schema-22 model routes them
/// to Private. Their classes are gone, so they are plain `NSManagedObject`s:
/// make them with `insertNewObject(forEntityName:)` and read them through KVC.
enum TrackEntitiesStandIn {
    static let names: Set<String> = ["Track", "TrackStep", "SequenceTrack", "StudentTrackEnrollment"]

    /// Adds the columns schema 23 dropped: `trackID` and `trackStepID` on
    /// LessonPresentation, LessonAssignment and WorkModel, and
    /// `studentTrackEnrollmentID` on Note. `model` must be a copy no
    /// coordinator has used. The caller assigns configurations afterwards,
    /// with the four entities in Private.
    static func add(to model: NSManagedObjectModel) {
        let byName = model.entitiesByName
        for name in ["LessonPresentation", "LessonAssignment", "WorkModel"] {
            byName[name]?.properties += [column("trackID"), column("trackStepID")]
        }
        byName["Note"]?.properties += [column("studentTrackEnrollmentID")]
    }

    private static func column(_ name: String) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = true
        return attribute
    }
}
