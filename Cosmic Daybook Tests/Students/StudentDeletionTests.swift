import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Deleting a child must take everything that is hers alone and leave every
// other child's records exactly as they were. Each test seeds her records
// beside a classmate's and checks both halves.

@Suite("Student Deletion")
@MainActor
struct StudentDeletionTests {

    // MARK: - Fixtures

    private struct Pair {
        let context: NSManagedObjectContext
        let danny: UUID
        let maya: UUID
    }

    private func makePair() throws -> Pair {
        let context = try CoreDataTestHelpers.makeContext()
        let danny = try #require(
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Danny", lastName: "Test").id
        )
        let maya = try #require(
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Singer").id
        )
        return Pair(context: context, danny: danny, maya: maya)
    }

    @discardableResult
    private func insert(
        _ entity: String, studentID: UUID, in context: NSManagedObjectContext
    ) -> NSManagedObject {
        let row = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
        row.setValue(studentID.uuidString, forKey: "studentID")
        return row
    }

    private func count(
        _ entity: String, studentID: UUID, in context: NSManagedObjectContext
    ) -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "studentID == %@", studentID.uuidString)
        return context.safeFetch(request).count
    }

    private func delete(_ studentID: UUID, in context: NSManagedObjectContext) throws -> StudentDeletionReport {
        CoreDataTestHelpers.save(context)
        return try StudentRepository(context: context).deleteStudent(id: studentID)
    }

    // MARK: - Her own records

    @Test("records that are hers alone go with her; the classmate's stay")
    func ownedRecordsGo() throws {
        let pair = try makePair()
        let context = pair.context
        let owned = ["AttendanceRecord", "LessonPresentation", "StudentTrackEnrollment",
                     "YearPlanEntry", "Guardian", "StudentFocusItem", "ScheduledMeeting"]
        for entity in owned {
            insert(entity, studentID: pair.danny, in: context)
            insert(entity, studentID: pair.maya, in: context)
        }

        let report = try delete(pair.danny, in: context)

        for entity in owned {
            #expect(count(entity, studentID: pair.danny, in: context) == 0, "\(entity) left for her")
            #expect(count(entity, studentID: pair.maya, in: context) == 1, "\(entity) lost for the classmate")
        }
        #expect(report.deleted["Student"] == 1)
        #expect(report.deleted["AttendanceRecord"] == 1)
        #expect(StudentRepository(context: context).fetchStudent(id: pair.danny) == nil)
        #expect(StudentRepository(context: context).fetchStudent(id: pair.maya) != nil)
    }

    @Test("her meeting goes and takes its notes with it")
    func meetingTakesItsNotes() throws {
        let pair = try makePair()
        let context = pair.context
        let meeting = try #require(
            insert("StudentMeeting", studentID: pair.danny, in: pair.context) as? CDStudentMeeting
        )
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Met about reading")
        note.studentMeeting = meeting
        insert("StudentMeeting", studentID: pair.maya, in: context)

        _ = try delete(pair.danny, in: context)

        #expect(count("StudentMeeting", studentID: pair.danny, in: context) == 0)
        #expect(count("StudentMeeting", studentID: pair.maya, in: context) == 1)
        #expect(context.safeFetch(CDFetchRequest(CDNote.self)).isEmpty)
    }

    // MARK: - Notes

    @Test("a note about her alone goes; a group note loses her; a whole-class note stays")
    func notesFollowTheirScope() throws {
        let pair = try makePair()
        let context = pair.context
        let hers = CoreDataTestHelpers.seedNote(in: context, body: "Hers")
        hers.scope = .student(pair.danny)
        let shared = CoreDataTestHelpers.seedNote(in: context, body: "Both")
        shared.scope = .students([pair.danny, pair.maya])
        shared.syncStudentLinks(in: context)
        let classNote = CoreDataTestHelpers.seedNote(in: context, body: "Everyone")
        classNote.scope = .all
        let mayas = CoreDataTestHelpers.seedNote(in: context, body: "Maya's")
        mayas.scope = .student(pair.maya)

        let report = try delete(pair.danny, in: context)

        let bodies = Set(context.safeFetch(CDFetchRequest(CDNote.self)).map(\.body))
        #expect(bodies == ["Both", "Everyone", "Maya's"])
        #expect(shared.scope == .student(pair.maya))
        let links = context.safeFetch(CDFetchRequest(CDNoteStudentLink.self))
        #expect(!links.contains { $0.studentID == pair.danny.uuidString })
        #expect(report.deleted["Note"] == 1)
        #expect(report.detached["Note"] == 1)
    }

    // MARK: - Presentations

    @Test("a group presentation loses her; one given only to her goes")
    func presentationsFollowTheirRoster() throws {
        let pair = try makePair()
        let context = pair.context
        let group = CDLessonAssignment(context: context)
        group.studentIDs = [pair.danny.uuidString, pair.maya.uuidString]
        group.confirmedStudentIDs = [pair.danny.uuidString, pair.maya.uuidString]
        let solo = CDLessonAssignment(context: context)
        solo.studentIDs = [pair.danny.uuidString]
        let soloNote = CoreDataTestHelpers.seedNote(in: context, body: "On her lesson")
        soloNote.lessonAssignment = solo
        // Confirmed but not on the roster: only the confirmation goes.
        let confirmedOnly = CDLessonAssignment(context: context)
        confirmedOnly.studentIDs = []
        confirmedOnly.confirmedStudentIDs = [pair.danny.uuidString]

        _ = try delete(pair.danny, in: context)

        let remaining = context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        #expect(remaining.count == 2)
        #expect(confirmedOnly.confirmedStudentIDs.isEmpty)
        #expect(group.studentIDs == [pair.maya.uuidString])
        #expect(group.confirmedStudentIDs == [pair.maya.uuidString])
        #expect(context.safeFetch(CDFetchRequest(CDNote.self)).isEmpty)
    }

    // MARK: - Work

    @Test("work only she is on goes with its check-ins; shared work passes to the classmate")
    func workFollowsItsChildren() throws {
        let pair = try makePair()
        let context = pair.context
        let solo = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead frame", studentID: pair.danny)
        let participant = CDWorkParticipantEntity(context: context)
        participant.studentID = pair.danny.uuidString
        participant.work = solo
        CDWorkCheckIn.make(for: solo, on: Date(), in: context)

        let shared = CoreDataTestHelpers.seedWorkModel(in: context, title: "Poster", studentID: pair.danny)
        for child in [pair.danny, pair.maya] {
            let row = CDWorkParticipantEntity(context: context)
            row.studentID = child.uuidString
            row.work = shared
        }

        _ = try delete(pair.danny, in: context)

        let works = context.safeFetch(CDFetchRequest(CDWorkModel.self))
        #expect(works.map(\.title) == ["Poster"])
        #expect(shared.studentID == pair.maya.uuidString)
        #expect(context.safeFetch(CDFetchRequest(CDWorkCheckIn.self)).isEmpty)
        let participants = context.safeFetch(CDFetchRequest(CDWorkParticipantEntity.self))
        #expect(participants.map(\.studentID) == [pair.maya.uuidString])
    }

    // MARK: - Shared lists

    @Test("a todo and a project lose her and stay; a practice session only she was in goes")
    func sharedListsLoseHer() throws {
        let pair = try makePair()
        let context = pair.context
        let todo = CDTodoItem(context: context)
        todo.title = "Call about field trip"
        todo.studentIDsArray = [pair.danny.uuidString]
        let project = CDProject(context: context)
        project.memberStudentIDsArray = [pair.danny.uuidString, pair.maya.uuidString]
        let practice = CDPracticeSession(context: context)
        practice.studentIDsArray = [pair.danny.uuidString]

        _ = try delete(pair.danny, in: context)

        #expect(!todo.isDeleted && todo.managedObjectContext != nil)
        #expect(todo.studentIDsArray.isEmpty)
        #expect(project.memberStudentIDsArray == [pair.maya.uuidString])
        #expect(context.safeFetch(CDFetchRequest(CDPracticeSession.self)).isEmpty)
    }

    @Test("deleting a student nobody has is a no-op")
    func unknownStudentIsNoOp() throws {
        let pair = try makePair()
        insert("AttendanceRecord", studentID: pair.maya, in: pair.context)

        let report = try delete(UUID(), in: pair.context)

        #expect(report.deletedTotal == 0)
        #expect(count("AttendanceRecord", studentID: pair.maya, in: pair.context) == 1)
    }
}
