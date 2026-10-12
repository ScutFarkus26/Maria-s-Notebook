import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-12 #38: a child who finished her own copy of linked work
/// is counted as finished, not listed as still working on a classmate's copy
/// that names her.
@Suite("Work peers, bug hunt 2026-10-12")
@MainActor
struct WorkPeersFix1012WTests {

    private struct Classroom {
        let context: NSManagedObjectContext

        func child(_ first: String, _ last: String) -> UUID {
            let student = CoreDataTestHelpers.seedStudent(in: context, firstName: first, lastName: last)
            let id = UUID()
            student.id = id
            return id
        }

        /// One row per child, each naming the whole group — what `assign_work`
        /// and the Quick New Work sheet write.
        func fanOut(_ title: String, to children: [UUID], on lessonID: UUID) -> [CDWorkModel] {
            let made = Date()
            return children.map { owner in
                let work = CoreDataTestHelpers.seedWorkModel(
                    in: context, title: title, studentID: owner, lessonID: lessonID
                )
                work.kind = .practiceLesson
                work.createdAt = made
                for studentID in children {
                    let participant = CDWorkParticipantEntity(context: context)
                    participant.id = UUID()
                    participant.studentID = studentID.uuidString
                    participant.work = work
                }
                return work
            }
        }
    }

    @Test("A child who mastered her copy is counted finished, not shown on a classmate's open copy")
    func finishedOwnerIsNotListedAsWorking() throws {
        let room = Classroom(context: try CoreDataTestHelpers.makeContext())
        let maya = room.child("Maya", "Stein")
        let eli = room.child("Eli", "Rosen")
        let ana = room.child("Ana", "Tal")
        let copies = room.fanOut("Bead chain 7", to: [eli, maya, ana], on: UUID())
        let mayas = try #require(copies.first { $0.studentID == maya.uuidString })
        mayas.status = .mastered
        let anas = try #require(copies.first { $0.studentID == ana.uuidString })
        #expect(CoreDataTestHelpers.save(room.context))

        let list = WorkPeers.others(doing: anas, in: room.context)

        #expect(list.peers.map(\.name) == ["Eli R"], "Maya finished hers; Eli's copy naming her isn't her work")
        #expect(list.finishedCount == 1)
    }

    @Test("The lesson's list counts the finished child once, as finished")
    func lessonListCountsFinishedOwner() throws {
        let room = Classroom(context: try CoreDataTestHelpers.makeContext())
        let maya = room.child("Maya", "Stein")
        let eli = room.child("Eli", "Rosen")
        let lessonID = UUID()
        let copies = room.fanOut("Bead chain 7", to: [eli, maya], on: lessonID)
        let mayas = try #require(copies.first { $0.studentID == maya.uuidString })
        mayas.status = .mastered
        #expect(CoreDataTestHelpers.save(room.context))

        let list = WorkPeers.children(workingOn: lessonID, in: room.context)

        #expect(list.peers.map(\.name) == ["Eli R"])
        #expect(list.finishedCount == 1)
    }

    @Test("A child with an open copy of her own is still listed, whatever else she finished")
    func ownOpenCopyStillWins() throws {
        let room = Classroom(context: try CoreDataTestHelpers.makeContext())
        let maya = room.child("Maya", "Stein")
        let eli = room.child("Eli", "Rosen")
        let lessonID = UUID()
        let first = room.fanOut("Bead chain 7", to: [eli, maya], on: lessonID)
        for copy in first { copy.status = .mastered }
        // Given again later, on her own: she is working on it now.
        let again = CoreDataTestHelpers.seedWorkModel(
            in: room.context, title: "Bead chain 7", studentID: maya, lessonID: lessonID
        )
        again.kind = .practiceLesson
        #expect(CoreDataTestHelpers.save(room.context))

        let list = WorkPeers.children(workingOn: lessonID, in: room.context)

        #expect(list.peers.map(\.name) == ["Maya S"])
        #expect(list.peers.first?.workID == again.id)
        #expect(list.finishedCount == 1, "Eli")
    }
}
