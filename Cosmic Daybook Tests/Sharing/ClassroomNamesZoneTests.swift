import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Your own row is read only in the pinned classroom's zone, and the fold
/// keeps the oldest row on every device, deleting only copies in its zone or
/// never sent to iCloud (2026-10-05 hunt, #24, and its review). Where a row lives comes from `ClassroomNames.zoneNameOverride`.
@Suite("Classroom names: the pinned classroom's zone", .serialized)
@MainActor
struct ClassroomNamesZoneTests {

    private typealias Support = ClassroomNamesTestSupport

    private let classroom = "com.apple.coredata.cloudkit.share.NOW"
    private let lastClassroom = "com.apple.coredata.cloudkit.share.BEFORE"
    private let defaultZone = "com.apple.coredata.cloudkit.zone"

    private func at(_ seconds: TimeInterval) -> Date {
        Support.at(seconds)
    }

    private func pin(_ role: CDClassroomMembership.ClassroomRole, in context: NSManagedObjectContext) {
        let membership = CDClassroomMembership(context: context)
        membership.role = role
        membership.classroomZoneID = classroom
    }

    @Test("Her row in a classroom she was in before is neither renamed nor folded away")
    func anotherClassroomsRowIsLeftAlone() throws {
        let context = try CoreDataTestHelpers.makeContext()
        pin(.assistant, in: context)
        let before = Support.person("_ana", "Ana B.", role: .assistant, created: at(0), in: context)
        let now = Support.person("_ana", "Ana", role: .assistant, created: at(100), in: context)
        #expect(context.safeSave())
        let zones = [before.objectID: lastClassroom, now.objectID: classroom]
        let lookup: @Sendable (NSManagedObjectID) -> String? = { zones[$0] }

        ClassroomNames.$zoneNameOverride.withValue(lookup, operation: {
            Support.asDevice(recordName: "_ana", displayName: "Annie") {
                ClassroomNames.setMyName("Annie", role: .assistant, in: context)
            }
        })
        #expect(context.safeSave())
        #expect(!before.isDeleted && before.managedObjectContext != nil)
        #expect(before.displayName == "Ana B.")
        #expect(now.displayName == "Annie")
    }

    @Test("The guide's fold never deletes his shared row for an older one still in his own zone")
    func guideKeepsTheSharedRow() throws {
        let context = try CoreDataTestHelpers.makeContext()
        pin(.leadGuide, in: context)
        // Written on his iPad before the pin arrived, not attached yet.
        let waiting = Support.person("_guide", "Danny", role: .leadGuide, created: at(0), in: context)
        let shared = Support.person(
            "_guide", "Danny D", role: .leadGuide, created: at(50), modified: at(60), in: context
        )
        #expect(context.safeSave())
        let zones = [waiting.objectID: defaultZone, shared.objectID: classroom]
        let lookup: @Sendable (NSManagedObjectID) -> String? = { zones[$0] }

        let folded = ClassroomNames.$zoneNameOverride.withValue(lookup, operation: {
            Support.asDevice(recordName: "_guide") {
                ClassroomNames.foldMyRows(role: .leadGuide, in: context)
            }
        })
        #expect(folded == 0)
        #expect(context.safeSave())
        let rows = context.safeFetch(CDFetchRequest(CDClassroomPerson.self))
        #expect(Set(rows.map(\.objectID)) == [waiting.objectID, shared.objectID])
        // The oldest row is the one kept, and carries the newest name.
        #expect(waiting.displayName == "Danny D")
    }

    /// Two of the guide's devices that know different things about where his
    /// rows live: the iPad still sees his oldest row in his own zone, the Mac
    /// sees both in the share. Neither may delete the row the other keeps.
    @Test("Two devices with different views of the zones keep the same row")
    func devicesAgreeOnTheKeptRow() throws {
        func deviceView(oldestZone: String) throws -> (keptSurvives: Bool, deletedOthers: Int) {
            let context = try CoreDataTestHelpers.makeContext()
            pin(.leadGuide, in: context)
            let oldest = Support.person("_guide", "Danny", role: .leadGuide, created: at(0), in: context)
            let newer = Support.person(
                "_guide", "Danny D", role: .leadGuide, created: at(50), modified: at(60), in: context
            )
            #expect(context.safeSave())
            let zones = [oldest.objectID: oldestZone, newer.objectID: classroom]
            let lookup: @Sendable (NSManagedObjectID) -> String? = { zones[$0] }
            let folded = ClassroomNames.$zoneNameOverride.withValue(lookup, operation: {
                Support.asDevice(recordName: "_guide") {
                    ClassroomNames.foldMyRows(role: .leadGuide, in: context)
                }
            })
            #expect(context.safeSave())
            return (!oldest.isDeleted && oldest.managedObjectContext != nil, folded)
        }
        let iPad = try deviceView(oldestZone: defaultZone)
        let mac = try deviceView(oldestZone: classroom)
        #expect(iPad.keptSurvives && mac.keptSurvives)
        #expect(iPad.deletedOthers == 0)
        #expect(mac.deletedOthers == 1)
    }

    @Test("With no zones known (nothing exported, or sync off), folding works as before")
    func noZonesFoldsAsBefore() throws {
        let context = try CoreDataTestHelpers.makeContext()
        pin(.leadGuide, in: context)
        let older = Support.person("_guide", "Danny", role: .leadGuide, created: at(0), in: context)
        _ = Support.person("_guide", "Daniel", role: .leadGuide, created: at(50), modified: at(60), in: context)
        #expect(context.safeSave())

        Support.asDevice(recordName: "_guide") {
            #expect(ClassroomNames.foldMyRows(role: .leadGuide, in: context) == 1)
        }
        #expect(context.safeSave())
        let rows = context.safeFetch(CDFetchRequest(CDClassroomPerson.self))
        #expect(rows.map(\.objectID) == [older.objectID])
        #expect(older.displayName == "Daniel")
    }
}
