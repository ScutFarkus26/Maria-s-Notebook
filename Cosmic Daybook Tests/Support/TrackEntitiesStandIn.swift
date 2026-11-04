import CoreData
import Foundation
@testable import CosmicDaybook

/// The four track entities and the columns that named them, as schema 22 had
/// them, for tests that open a store written before schema 23 took them out
/// (`docs/Plans/Plan - Retire the track entities.md`, Phase 3). Their classes
/// are gone, so they are plain `NSManagedObject`s: make them with
/// `insertNewObject(forEntityName:)` and read them through KVC.
enum TrackEntitiesStandIn {
    static let names: Set<String> = ["Track", "TrackStep", "SequenceTrack", "StudentTrackEnrollment"]

    /// Adds the four entities, with their relationships, to `model`, and the
    /// columns that named them: `trackID` and `trackStepID` on
    /// LessonPresentation, LessonAssignment and WorkModel, and
    /// `studentTrackEnrollmentID` on Note. `model` must be a copy no
    /// coordinator has used. The caller assigns configurations afterwards
    /// (the four lived in Private).
    static func add(to model: NSManagedObjectModel) {
        let track = entity("Track", [
            attribute("id", .UUIDAttributeType), attribute("title", .stringAttributeType, optional: false),
            attribute("createdAt", .dateAttributeType)
        ])
        let step = entity("TrackStep", [
            attribute("id", .UUIDAttributeType),
            attribute("orderIndex", .integer64AttributeType, optional: false, defaultValue: 0),
            attribute("lessonTemplateID", .UUIDAttributeType), attribute("createdAt", .dateAttributeType)
        ])
        let sequenceTrack = entity("SequenceTrack", [
            attribute("id", .UUIDAttributeType), attribute("area", .stringAttributeType, optional: false),
            attribute("sequence", .stringAttributeType, optional: false),
            attribute("isSequential", .booleanAttributeType, optional: false, defaultValue: true),
            attribute("isExplicitlyDisabled", .booleanAttributeType, optional: false, defaultValue: false),
            attribute("createdAt", .dateAttributeType)
        ])
        let enrollment = entity("StudentTrackEnrollment", [
            attribute("id", .UUIDAttributeType), attribute("createdAt", .dateAttributeType),
            attribute("studentID", .stringAttributeType, optional: false),
            attribute("trackID", .stringAttributeType, optional: false),
            attribute("startedAt", .dateAttributeType),
            attribute("isActive", .booleanAttributeType, optional: false, defaultValue: true)
        ])
        link(track, "steps", toMany: true, with: step, "track")
        link(track, "enrollments", toMany: true, with: enrollment, "track")
        link(track, "sequenceTrack", toMany: false, with: sequenceTrack, "track")

        let byName = model.entitiesByName
        for name in ["LessonPresentation", "LessonAssignment", "WorkModel"] {
            byName[name]?.properties += [
                attribute("trackID", .stringAttributeType), attribute("trackStepID", .stringAttributeType)
            ]
        }
        byName["Note"]?.properties += [attribute("studentTrackEnrollmentID", .stringAttributeType)]
        model.entities += [track, step, sequenceTrack, enrollment]
    }

    // MARK: - Pieces

    private static func entity(_ name: String, _ attributes: [NSAttributeDescription]) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = attributes
        return entity
    }

    private static func attribute(
        _ name: String, _ type: NSAttributeType, optional: Bool = true, defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        if let defaultValue {
            attribute.defaultValue = defaultValue
        } else if type == .stringAttributeType && !optional {
            attribute.defaultValue = ""
        }
        return attribute
    }

    /// `owner.name` and its to-one inverse `other.inverse`. A to-many one
    /// cascades, as the track's steps and enrollments did.
    private static func link(
        _ owner: NSEntityDescription, _ name: String, toMany: Bool,
        with other: NSEntityDescription, _ inverse: String
    ) {
        let forward = NSRelationshipDescription()
        forward.name = name
        forward.destinationEntity = other
        forward.minCount = 0
        forward.maxCount = toMany ? 0 : 1
        forward.isOptional = true
        forward.deleteRule = toMany ? .cascadeDeleteRule : .nullifyDeleteRule
        let back = NSRelationshipDescription()
        back.name = inverse
        back.destinationEntity = owner
        back.minCount = 0
        back.maxCount = 1
        back.isOptional = true
        back.deleteRule = .nullifyDeleteRule
        forward.inverseRelationship = back
        back.inverseRelationship = forward
        owner.properties += [forward]
        other.properties += [back]
    }
}
