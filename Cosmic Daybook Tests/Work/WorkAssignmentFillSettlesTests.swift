import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Domain logic Phase 10, cold review finding 5: an `assignmentID` the launch
// fill stamped on part of a group (the rest hadn't come down from iCloud yet)
// used to stay as it was, so the copies stopped matching once the others
// arrived, and a lone copy stamped shared stayed shared. The fill now joins
// what the guess links to the lowest id any of them carries, and two devices
// that filled different parts of one group end with the same answer.

@Suite("Work assignment fill settles (domain logic, Phase 10)")
@MainActor
struct WorkAssignmentFillSettlesTests {

    /// One group of three copies made before schema 25, each child's own
    /// row naming all three, as rows that can be put in either store.
    private struct Group {
        let lesson = UUID()
        let children = [UUID(), UUID(), UUID()]
        /// The rows' ids, lowest first.
        let rowIDs = [UUID(), UUID(), UUID()].sorted { $0.uuidString < $1.uuidString }
        let made = Date(timeIntervalSince1970: 1_790_000_000)

        /// Copy `index` (0 is the lowest id), unfilled, inserted in `context`.
        @discardableResult
        func copy(_ index: Int, in context: NSManagedObjectContext) -> CDWorkModel {
            let row = CDWorkModel(context: context)
            row.id = rowIDs[index]
            row.title = "Checkerboard"
            row.lessonID = lesson.uuidString
            row.studentID = children[index].uuidString
            row.kind = .practiceLesson
            row.createdAt = made.addingTimeInterval(Double(index) / 1000)
            row.assignmentID = nil
            row.isSharedRow = false
            for child in children {
                let participant = CDWorkParticipantEntity(context: context)
                participant.id = UUID()
                participant.studentID = child.uuidString
                participant.work = row
            }
            return row
        }

        func row(_ index: Int, in context: NSManagedObjectContext) throws -> CDWorkModel {
            let request = CDFetchRequest(CDWorkModel.self)
            request.predicate = NSPredicate(format: "id == %@", rowIDs[index] as CVarArg)
            return try #require(context.safeFetch(request).first)
        }
    }

    private func store() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    @Test("A copy that arrives after the rest were filled joins them, and the lowest id wins")
    func lateCopyJoinsAtTheLowestID() throws {
        let group = Group()
        let context = try store()
        group.copy(1, in: context)
        group.copy(2, in: context)
        #expect(CoreDataTestHelpers.save(context))
        WorkAssignmentFill.run(in: context)
        #expect(try group.row(2, in: context).assignmentID == group.rowIDs[1].uuidString)

        // The lowest copy comes down from iCloud later, with no assignment.
        group.copy(0, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let changed = WorkAssignmentFill.run(in: context)

        let lowest = group.rowIDs[0].uuidString
        for index in 0..<3 {
            #expect(
                try group.row(index, in: context).assignmentID == lowest, "the id a device with every copy works out"
            )
        }
        #expect(changed == 3)
        #expect(WorkAssignmentFill.run(in: context) == 0, "settled, so a second run changes nothing")
    }

    @Test("A lone copy stamped shared stops being shared when its classmates' copies arrive")
    func loneCopyLosesTheSharedFlag() throws {
        let group = Group()
        let context = try store()
        let first = group.copy(2, in: context)
        #expect(CoreDataTestHelpers.save(context))
        WorkAssignmentFill.run(in: context)
        #expect(first.isSharedRow, "one row naming three children, nothing beside it: the guess says shared")

        group.copy(0, in: context)
        group.copy(1, in: context)
        #expect(CoreDataTestHelpers.save(context))
        WorkAssignmentFill.run(in: context)

        #expect(!first.isSharedRow, "it has copies beside it now, so each is one child's")
        #expect(first.assignmentID == group.rowIDs[0].uuidString)
        let reader = WorkOwnership.Reader(rows: try (0..<3).map { try group.row($0, in: context) })
        #expect(!reader.isWork(first, of: group.children[0]), "a classmate's copy isn't hers")
    }

    @Test("Copies that already agree keep their id, even one above their own row ids")
    func agreeingCopiesKeepTheirID() throws {
        let group = Group()
        let context = try store()
        // A lone row marked shared, as a restore brings it back, and a group
        // short one copy (a child taken off), both carrying an id above
        // every row id they have.
        let lone = group.copy(0, in: context)
        lone.lessonID = UUID().uuidString
        lone.assignmentID = "FFFFFFFF-0000-0000-0000-000000000000"
        lone.isSharedRow = true
        let short = [group.copy(1, in: context), group.copy(2, in: context)]
        for row in short { row.assignmentID = "FFFFFFFF-1111-0000-0000-000000000000" }
        #expect(CoreDataTestHelpers.save(context))

        #expect(WorkAssignmentFill.run(in: context) == 0)
        #expect(lone.assignmentID == "FFFFFFFF-0000-0000-0000-000000000000")
        #expect(lone.isSharedRow, "a lone row's flag is its own word")
        #expect(short.allSatisfy { $0.assignmentID == "FFFFFFFF-1111-0000-0000-000000000000" })
    }

    @Test("Two devices that filled different parts of one group settle on the same id")
    func twoDevicesSettle() throws {
        let group = Group()
        // The Mac had every copy when it filled; the iPad had only two.
        let mac = try store()
        (0..<3).forEach { group.copy($0, in: mac) }
        #expect(CoreDataTestHelpers.save(mac))
        WorkAssignmentFill.run(in: mac)
        let ipad = try store()
        group.copy(1, in: ipad)
        group.copy(2, in: ipad)
        #expect(CoreDataTestHelpers.save(ipad))
        WorkAssignmentFill.run(in: ipad)
        let ipadsID = group.rowIDs[1].uuidString
        #expect(try group.row(1, in: ipad).assignmentID == ipadsID)

        // iCloud keeps the later write of each row: the iPad's for the two it
        // had, the Mac's for the lowest. Every row is filled, but split.
        for index in 1...2 {
            try group.row(index, in: mac).assignmentID = ipadsID
        }
        #expect(CoreDataTestHelpers.save(mac))
        // The iPad gets the lowest copy as the Mac stamped it.
        let arrived = group.copy(0, in: ipad)
        arrived.assignmentID = group.rowIDs[0].uuidString
        #expect(CoreDataTestHelpers.save(ipad))

        WorkAssignmentFill.run(in: mac)
        WorkAssignmentFill.run(in: ipad)

        let lowest = group.rowIDs[0].uuidString
        for index in 0..<3 {
            #expect(try group.row(index, in: mac).assignmentID == lowest)
            #expect(try group.row(index, in: ipad).assignmentID == lowest)
        }
        #expect(WorkAssignmentFill.run(in: mac) == 0)
        #expect(WorkAssignmentFill.run(in: ipad) == 0)
    }
}
