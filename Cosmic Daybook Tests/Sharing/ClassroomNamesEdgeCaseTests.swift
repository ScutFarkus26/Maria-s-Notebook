import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

extension ClassroomNamesSuites {

    // Three cases the Phase 4 review found (docs/Plans/Plan - Names you set
    // yourself.md): copies of one row, a name saved with no classroom open, and a
    // guide's row left from another class.
    @Suite("Classroom names: edge cases", .serialized)
    @MainActor
    struct ClassroomNamesEdgeCaseTests {

        private typealias Support = ClassroomNamesTestSupport

        private func at(_ seconds: TimeInterval) -> Date {
            Support.at(seconds)
        }

        private func rows(_ recordName: String, in context: NSManagedObjectContext) -> [CDClassroomPerson] {
            context.safeFetch(CDFetchRequest(CDClassroomPerson.self)).filter { $0.recordName == recordName }
        }

        @Test("Two copies of one row (a restore beside CloudKit's) are both kept, so no device deletes the name")
        func copiesOfOneRowAreNeverFolded() async throws {
            let context = try CoreDataTestHelpers.makeContext()
            let id = UUID()
            Support.person("_guide", "Danny", role: .leadGuide, created: at(0), modified: at(10), id: id, in: context)
            Support.person("_guide", "Danny", role: .leadGuide, created: at(0), modified: at(10), id: id, in: context)
            #expect(context.safeSave())

            await Support.asDevice(recordName: "_guide") {
                #expect(await ClassroomNames.foldMyRows(role: .leadGuide, in: context) == 0)
            }
            #expect(context.safeSave())
            #expect(rows("_guide", in: context).count == 2, "nothing deleted")
            #expect(ClassroomNames.name(forRecordName: "_guide", in: context) == "Danny")

            // A genuinely different row of his still folds away.
            Support.person("_guide", "Daniel", role: .leadGuide, created: at(5), modified: at(90), in: context)
            #expect(context.safeSave())
            _ = await Support.asDevice(recordName: "_guide") {
                await ClassroomNames.foldMyRows(role: .leadGuide, in: context)
            }
            #expect(context.safeSave())
            #expect(rows("_guide", in: context).count == 2)
            #expect(rows("_guide", in: context).allSatisfy { $0.id == id })
            #expect(ClassroomNames.name(forRecordName: "_guide", in: context) == "Daniel")
        }

        @Test("A name marked waiting is written over the row she already has")
        func waitingRenameReachesAnExistingRow() async throws {
            let context = try CoreDataTestHelpers.makeContext()
            Support.person("_ana", "Ana", role: .assistant, created: at(0), in: context)
            #expect(context.safeSave())

            await Support.asDevice(recordName: "_ana", displayName: "Annie") {
                // Saved with no classroom open (or the Sample Class): it waits.
                ClassroomNames.markWaiting(as: .assistant)
                #expect(await ClassroomNames.writeWaitingName(role: .assistant, in: context))
                #expect(ClassroomIdentity.nameWaitingAs == nil)
            }
            #expect(ClassroomNames.name(forRecordName: "_ana", in: context) == "Annie")
            #expect(rows("_ana", in: context).count == 1)
        }

        @Test("The guide's name is the classroom owner's row, not a guide's row left from another class")
        func guideIsTheClassroomsOwner() throws {
            let context = try CoreDataTestHelpers.makeContext()
            Support.person("_oldGuide", "Mr. Cole", role: .leadGuide, created: at(0), modified: at(500), in: context)
            Support.person("_guide", "Danny", role: .leadGuide, created: at(0), modified: at(10), in: context)
            let membership = CDClassroomMembership(context: context)
            membership.role = .assistant
            membership.ownerIdentity = "_guide"
            #expect(context.safeSave())
            #expect(ClassroomNames.snapshot(in: context).guideName == "Danny")

            // With no real owner name on the row, the newest guide's row it is.
            membership.ownerIdentity = "unknown"
            #expect(context.safeSave())
            #expect(ClassroomNames.snapshot(in: context).guideName == "Mr. Cole")
        }
    }
}
