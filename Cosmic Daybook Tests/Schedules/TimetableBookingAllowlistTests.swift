import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A booking goes to the assistants' phones, so it must never carry a lesson's
/// name or anything that leads to one. Its attributes are pinned here: adding
/// one, a text one above all, has to change this list on purpose.
@Suite("Schedules: what a booking may carry")
@MainActor
struct TimetableBookingAllowlistTests {

    /// Every attribute a booking may have, with its type.
    private static let allowed: [String: NSAttributeType] = [
        "id": .UUIDAttributeType,
        "presentationID": .stringAttributeType,
        "day": .dateAttributeType,
        "halfRaw": .stringAttributeType,
        "minute": .integer64AttributeType,
        "order": .integer64AttributeType,
        "_studentIDsData": .binaryDataAttributeType,
        "sourceModifiedAt": .dateAttributeType,
        "createdAt": .dateAttributeType,
        "modifiedAt": .dateAttributeType
    ]

    private func entity() throws -> NSEntityDescription {
        try #require(CoreDataStack.sharedModel().entitiesByName["TimetableBooking"])
    }

    @Test("Exactly the allowed attributes, and no relationships")
    func attributesAreAllowed() throws {
        let booking = try entity()
        let attributes = booking.attributesByName.mapValues(\.attributeType)
        #expect(Set(attributes.keys) == Set(Self.allowed.keys))
        for (name, type) in attributes {
            #expect(Self.allowed[name] == type, "\(name) changed type")
        }
        #expect(booking.relationshipsByName.isEmpty, "a relationship would take a lesson into the share")
    }

    @Test("Its only text is an ID and a half's name")
    func noFreeText() throws {
        let strings = try entity().attributesByName.values
            .filter { $0.attributeType == .stringAttributeType }
            .map(\.name)
        #expect(Set(strings) == ["presentationID", "halfRaw"])
    }

    @Test("Bookings are in the classroom share; the lessons they come from are not")
    func sharing() {
        #expect(CoreDataStack.sharedEntityNames.contains("TimetableBooking"))
        for name in ["LessonAssignment", "Lesson", "LessonPresentation"] {
            #expect(!CoreDataStack.sharedEntityNames.contains(name))
        }
        #expect(!ClassroomPermissions.assistantWritableEntities.contains("TimetableBooking"), "assistants only read")
    }
}
