import CoreData
import Foundation
@testable import CosmicDaybook

/// Seed data, a comparable snapshot, and the pre-2026-09-26 code for
/// `LaunchRepairPassTests`.
@MainActor
enum LaunchRepairFixture {

    // MARK: - Stores

    nonisolated enum Store: String, Sendable {
        case inMemory, sqlite

        /// A fresh store's main-queue context, plus whatever keeps its stores alive.
        @MainActor
        func make() throws -> (context: NSManagedObjectContext, owner: AnyObject?) {
            switch self {
            case .inMemory:
                let stack = try CoreDataTestHelpers.makeInMemoryStack()
                return (stack.viewContext, stack)
            case .sqlite:
                return (try CoreDataTestHelpers.makeSplitStoreContext(), nil)
            }
        }
    }

    /// A private-queue context on `context`'s coordinator, set up the way
    /// `CoreDataStack.newBackgroundContext()` sets one up.
    static func backgroundContext(beside context: NSManagedObjectContext) -> NSManagedObjectContext {
        let background = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        background.persistentStoreCoordinator = context.persistentStoreCoordinator
        background.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        background.transactionAuthor = PersistentHistoryProcessor.transactionAuthor
        return background
    }

    // MARK: - Ids

    /// Fixed ids, so two stores are seeded alike and compared row by row.
    static func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012lX", number))!
    }

    static let ada = uuid(0xA1)
    static let ben = uuid(0xB1)
    static let cy = uuid(0xC1)
    /// Students no longer on file.
    static let goneOne = uuid(0xD1)
    static let goneTwo = uuid(0xD2)

    static func workID(_ number: Int) -> UUID { uuid(0x100 + number) }
    static func participantID(_ number: Int) -> UUID { uuid(0x200 + number) }
    static func assignmentID(_ number: Int) -> UUID { uuid(0x300 + number) }

    /// Monday 8 June 2026, start of day.
    static var monday: Date {
        AppCalendar.startOfDay(AppCalendar.shared.date(from: DateComponents(year: 2026, month: 6, day: 8))!)
    }

    static let createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - Seeding

    /// Ada, Ben and Cy plus a student with no id; work and assignment rows that
    /// name them, students no longer on file, a lower-cased copy of a real id,
    /// junk and blanks; and a participant that belongs to no work.
    static func seed(_ context: NSManagedObjectContext) throws {
        for (id, name) in [(ada, "Ada"), (ben, "Ben"), (cy, "Cy")] {
            CoreDataTestHelpers.seedStudent(in: context, firstName: name, lastName: "Test").id = id
        }
        CoreDataTestHelpers.seedStudent(in: context, firstName: "No", lastName: "Id").id = nil

        let (adaID, benID, cyID) = (ada.uuidString, ben.uuidString, cy.uuidString)
        let (goneOneID, goneTwoID) = (goneOne.uuidString, goneTwo.uuidString)
        work(1, studentID: adaID, participants: [(1, adaID)], in: context)
        work(2, studentID: goneOneID, participants: [(2, goneOneID), (3, benID)], in: context)
        work(3, studentID: "", participants: [(4, goneTwoID)], in: context)
        work(4, studentID: "not-a-student", participants: [], in: context)
        work(5, studentID: cyID.lowercased(), participants: [], in: context)
        work(6, studentID: benID, participants: [(5, benID), (6, cyID), (7, "")], in: context)
        work(7, studentID: cyID, participants: [(8, cyID)], in: context)
        // Reached through no work, so the cleanup (old and new) never sees it.
        let stray = CDWorkParticipantEntity(context: context)
        stray.id = participantID(9)
        stray.studentID = goneOneID

        let at = { (hour: Int) in AppCalendar.shared.date(bySettingHour: hour, minute: 0, second: 0, of: monday)! }
        assignment(1, students: [adaID, goneOneID], scheduledFor: at(9), day: .distantPast, in: context)
        assignment(2, students: [benID], scheduledFor: nil, day: monday, in: context)
        assignment(3, students: [goneTwoID, cyID.lowercased()], scheduledFor: at(10), day: monday, in: context)
        assignment(4, students: [], scheduledFor: nil, day: .distantPast, in: context)
        assignment(5, students: [cyID, benID], scheduledFor: at(11), day: monday, in: context)
        try context.save()
    }

    /// A second row for Ada (same id) and a newer copy of work 2 (same id) that
    /// names a student no longer on file and one who is: the launch dedup folds
    /// both before the work cleanup runs.
    static func seedDuplicates(_ context: NSManagedObjectContext) throws {
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Twin").id = ada
        let copy = work(
            2, studentID: goneOne.uuidString,
            participants: [(10, goneTwo.uuidString), (11, cy.uuidString)], in: context
        )
        copy.createdAt = createdAt.addingTimeInterval(60)
        try context.save()
    }

    @discardableResult
    static func work(
        _ number: Int,
        studentID: String,
        participants: [(Int, String)],
        in context: NSManagedObjectContext
    ) -> CDWorkModel {
        let work = CDWorkModel(context: context)
        work.id = workID(number)
        work.title = "Work \(number)"
        work.createdAt = createdAt
        work.studentID = studentID
        for (participantNumber, student) in participants {
            let participant = CDWorkParticipantEntity(context: context)
            participant.id = participantID(participantNumber)
            participant.studentID = student
            participant.work = work
        }
        return work
    }

    static func assignment(
        _ number: Int,
        students: [String],
        scheduledFor: Date?,
        day: Date,
        in context: NSManagedObjectContext
    ) {
        let assignment = CDLessonAssignment(context: context)
        assignment.id = assignmentID(number)
        assignment.studentIDs = students
        assignment.scheduledFor = scheduledFor
        assignment.scheduledForDay = day
    }

    // MARK: - Snapshot

    /// What the repairs can change, read back through a fresh context so only
    /// saved state counts.
    struct Snapshot: Equatable {
        var rowCounts: [String: Int] = [:]
        var workStudents: [UUID: String] = [:]
        var participantStudents: [UUID: String] = [:]
        var participantWorks: [UUID: UUID] = [:]
        var assignmentStudents: [UUID: [String]] = [:]
        var assignmentDays: [UUID: Date] = [:]
    }

    static func snapshot(of context: NSManagedObjectContext) -> Snapshot {
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = context.persistentStoreCoordinator
        var snapshot = Snapshot()

        let students = reader.safeFetch(CDFetchRequest(CDStudent.self))
        let works = reader.safeFetch(CDFetchRequest(CDWorkModel.self))
        let participants = reader.safeFetch(CDFetchRequest(CDWorkParticipantEntity.self))
        let assignments = reader.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        snapshot.rowCounts = [
            "Student": students.count, "WorkModel": works.count,
            "WorkParticipantEntity": participants.count, "LessonAssignment": assignments.count
        ]
        for work in works {
            guard let id = work.id else { continue }
            snapshot.workStudents[id] = work.studentID
        }
        for participant in participants {
            guard let id = participant.id else { continue }
            snapshot.participantStudents[id] = participant.studentID
            snapshot.participantWorks[id] = participant.work?.id
        }
        for assignment in assignments {
            guard let id = assignment.id else { continue }
            snapshot.assignmentStudents[id] = assignment.studentIDs
            snapshot.assignmentDays[id] = assignment.scheduledForDay
        }
        return snapshot
    }
}
