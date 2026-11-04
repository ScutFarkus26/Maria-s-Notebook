import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Maya, Ada and Ben, and a two-lesson sequence; the second needs the first's
/// practice and a confirmation (the built-in rules). Shared by the 2026-11-03
/// presentations suites.
@MainActor
struct Fix1103PRoom {
    let stack: CoreDataStack
    let maya: CDStudent
    let ada: CDStudent
    let ben: CDStudent
    let first: CDLesson
    let second: CDLesson
    var context: NSManagedObjectContext { stack.viewContext }

    init() throws {
        stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lane")
        ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Hart")
        first = CoreDataTestHelpers.seedLesson(in: context, name: "First", area: "Math", sequence: "Counting")
        first.orderInSequence = 1
        second = CoreDataTestHelpers.seedLesson(in: context, name: "Second", area: "Math", sequence: "Counting")
        second.orderInSequence = 2
        #expect(CoreDataTestHelpers.save(context))
    }

    func id(_ student: CDStudent) throws -> UUID { try #require(student.id) }

    /// The first lesson, given to `students` on a September day.
    func given(_ students: [CDStudent], confirmed: [CDStudent] = []) throws -> CDLessonAssignment {
        let assignment = PresentationFactory.makeDraft(
            lessonID: try #require(first.id), studentIDs: try students.map(id), context: context
        )
        assignment.markPresented(at: try CoreDataTestHelpers.day("2026-09-14"))
        for student in confirmed { assignment.confirmStudent(try id(student)) }
        return assignment
    }

    /// A draft of the second lesson.
    func plan(_ students: [CDStudent]) throws -> CDLessonAssignment {
        PresentationFactory.makeDraft(
            lessonID: try #require(second.id), studentIDs: try students.map(id), context: context
        )
    }

    @discardableResult
    func note(_ body: String, on assignment: CDLessonAssignment, scope: NoteScope) -> CDNote {
        let note = CoreDataTestHelpers.seedNote(in: context, body: body)
        note.scope = scope
        note.lessonAssignment = assignment
        return note
    }

    /// A history row for `student` on `lesson`, filed on `assignment` when given.
    @discardableResult
    func historyRow(
        _ student: CDStudent, lesson: CDLesson, on assignment: CDLessonAssignment?,
        mastered: Bool = false, text: String? = nil
    ) throws -> CDLessonPresentation {
        let row = CDLessonPresentation(context: context)
        row.studentID = try id(student).uuidString
        row.lessonID = try #require(lesson.id).uuidString
        row.presentationID = assignment?.id?.uuidString
        row.presentedAt = try CoreDataTestHelpers.day("2026-09-14")
        row.state = .presented
        if mastered { row.masteredAt = try CoreDataTestHelpers.day("2026-09-20") }
        row.notes = text
        return row
    }

    var liveNotes: [CDNote] {
        context.safeFetch(CDFetchRequest(CDNote.self)).filter { !$0.isDeleted }
    }

    var liveRows: [CDLessonPresentation] {
        context.safeFetch(CDFetchRequest(CDLessonPresentation.self)).filter { !$0.isDeleted }
    }

    /// Whether the store still holds it. By object ID: a deleted object's
    /// attributes read nil once the delete is saved.
    func exists(_ assignment: CDLessonAssignment) -> Bool {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "SELF == %@", assignment.objectID)
        return !context.safeFetch(request).isEmpty
    }

    func update(_ vm: PresentationsViewModel, showTestStudents: Bool = true, testNames: String = "") async {
        context.processPendingChanges()
        vm.update(
            viewContext: context,
            calendar: AppCalendar.shared,
            inboxOrderRaw: "",
            showTestStudents: showTestStudents,
            testStudentNamesRaw: testNames,
            lessons: context.safeFetch(CDFetchRequest(CDLesson.self)),
            students: context.safeFetch(CDFetchRequest(CDStudent.self))
        )
        await vm.pendingUpdateTask?.value
    }

    static func children(of scope: NoteScope) -> Set<UUID> {
        switch scope {
        case .all: return []
        case .student(let id): return [id]
        case .students(let ids): return Set(ids)
        }
    }
}

/// Bug hunt 2026-11-03, the presentations core's deletes and split: Delete in
/// the history kept nothing and asked nothing (#1), Remove in Merge Groups
/// took the plan's notes when it emptied it (#3), and a split left the ready
/// children's notes and year-plan entries behind (#11).
@Suite("Presentation deletes and splits (bug hunt 2026-11-03)")
@MainActor
struct PresentationsFix1103PTests {

    // MARK: - #1 Delete in the history

    @Test("Deleting a given presentation keeps its notes on the children and their mastery marks")
    func deleteKeepsNotesAndMarks() throws {
        let room = try Fix1103PRoom()
        let context = room.context
        let presentation = try room.given([room.maya, room.ada])
        let groupNote = room.note("Both counted to 100", on: presentation, scope: .all)
        let mayasNote = room.note("Skipped 14", on: presentation, scope: .student(try room.id(room.maya)))
        let mark = try room.historyRow(room.maya, lesson: room.first, on: presentation, mastered: true)
        try room.historyRow(room.ada, lesson: room.first, on: presentation, text: "Needed the chain again")
        #expect(CoreDataTestHelpers.save(context))

        PresentationDeletion.delete(presentation, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let lessonKey = try #require(room.first.id).uuidString
        #expect(!room.exists(presentation))
        let notes = room.liveNotes
        let kept = try #require(notes.first { $0.body == "Both counted to 100" })
        #expect(kept === groupNote)
        #expect(kept.lessonAssignment == nil)
        #expect(Fix1103PRoom.children(of: kept.scope) == [try room.id(room.maya), try room.id(room.ada)])
        #expect(kept.lessonID == lessonKey)
        let hers = try #require(notes.first { $0.body == "Skipped 14" })
        #expect(hers === mayasNote)
        #expect(hers.scope == .student(try room.id(room.maya)))
        #expect(hers.lessonID == lessonKey)
        // The history row's own text is kept as a note on Ada.
        let adasText = try #require(notes.first { $0.body == "Needed the chain again" })
        #expect(adasText.scope == .student(try room.id(room.ada)))
        #expect(adasText.lessonID == lessonKey)
        // Maya's mark stands on its own; the unmarked row went with the presentation.
        let rows = room.liveRows
        #expect(rows.count == 1)
        #expect(rows.first === mark)
        #expect(mark.masteredAt != nil)
        #expect(mark.presentationID == nil)
    }

    @Test("Delete asks first, naming the notes and marks, and asking deletes nothing")
    func deleteAsksFirst() throws {
        let room = try Fix1103PRoom()
        let context = room.context
        let presentation = try room.given([room.maya, room.ada])
        room.note("Both counted to 100", on: presentation, scope: .all)
        room.note("Skipped 14", on: presentation, scope: .student(try room.id(room.maya)))
        try room.historyRow(room.maya, lesson: room.first, on: presentation, mastered: true)
        #expect(CoreDataTestHelpers.save(context))

        let request = try #require(
            PresentationDeletion.deleteRequest(for: presentation, childNames: ["Maya S", "Ada L"], in: context)
        )
        #expect(request.summary == PresentationDeletion.Summary(isGiven: true, notes: 2, masteryMarks: 1))
        #expect(request.message.contains("2 notes stay on Maya S and Ada L"))
        #expect(request.message.contains("Mastery marks stay"))

        // Cancel drops the request: nothing has changed.
        #expect(!context.hasChanges)
        #expect(room.exists(presentation))
        #expect(room.liveNotes.count == 2)
        #expect(room.liveRows.count == 1)
    }

    @Test("Deleting a given presentation keeps its work, no longer pointing at it")
    func deleteKeepsTheWork() throws {
        let room = try Fix1103PRoom()
        let context = room.context
        let presentation = try room.given([room.maya])
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Bead chains", studentID: try room.id(room.maya), lessonID: try #require(room.first.id)
        )
        work.presentationID = presentation.id?.uuidString
        #expect(CoreDataTestHelpers.save(context))

        PresentationDeletion.delete(presentation, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(!work.isDeleted && work.managedObjectContext != nil)
        #expect(work.presentationID == nil)
    }

    // MARK: - #3 Remove in Merge Groups

    @Test("Removing the last child in Merge Groups asks first and keeps the plan's notes as hers")
    func removeLastChildKeepsNotes() throws {
        let room = try Fix1103PRoom()
        let context = room.context
        let mayaKey = try room.id(room.maya).uuidString
        let draft = try room.plan([room.maya])
        let planNote = room.note("Bring the bead frame", on: draft, scope: .all)
        #expect(CoreDataTestHelpers.save(context))

        let request = try #require(
            PresentationDeletion.removeRequest(mayaKey, childName: "Maya S", from: draft, in: context)
        )
        #expect(request.message.contains("note stays on Maya S"))
        #expect(!context.hasChanges)
        #expect(room.exists(draft))

        PresentationDeletion.remove(mayaKey, from: draft, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(!room.exists(draft))
        let kept = try #require(room.liveNotes.first)
        #expect(kept === planNote)
        #expect(kept.scope == .student(try room.id(room.maya)))
        #expect(kept.lessonID == (try #require(room.second.id)).uuidString)
    }

    @Test("Removing the last child keeps a history row's text as one note, not two")
    func removeLastChildKeepsRowTextOnce() throws {
        let room = try Fix1103PRoom()
        let context = room.context
        let mayaKey = try room.id(room.maya).uuidString
        let draft = try room.plan([room.maya])
        _ = try room.historyRow(room.maya, lesson: room.second, on: draft, text: "Counted by tens.")
        #expect(CoreDataTestHelpers.save(context))

        PresentationDeletion.remove(mayaKey, from: draft, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(room.liveNotes.filter { $0.body == "Counted by tens." }.count == 1)
    }

    @Test("Removing one child of several in Merge Groups keeps her mastery mark and asks nothing")
    func removeOneChildKeepsHerMark() throws {
        let room = try Fix1103PRoom()
        let context = room.context
        let mayaKey = try room.id(room.maya).uuidString
        let draft = try room.plan([room.maya, room.ada])
        let mark = try room.historyRow(room.maya, lesson: room.second, on: draft, mastered: true)
        #expect(CoreDataTestHelpers.save(context))

        #expect(PresentationDeletion.removeRequest(mayaKey, childName: "Maya S", from: draft, in: context) == nil)
        PresentationDeletion.remove(mayaKey, from: draft, in: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(draft.studentIDs == [try room.id(room.ada).uuidString])
        #expect(room.liveRows.first === mark)
        #expect(mark.masteredAt != nil)
        #expect(mark.presentationID == nil)
    }

    // MARK: - #11 The split

    @Test("Splitting the ready children off takes their own notes and year-plan entries with them")
    func splitMovesNotesAndEntries() throws {
        let room = try Fix1103PRoom()
        let context = room.context
        let brewing = try room.plan([room.ada, room.ben])
        let adasNote = room.note("Ready for it", on: brewing, scope: .student(try room.id(room.ada)))
        let groupNote = room.note("Use the green beads", on: brewing, scope: .all)
        func entry(_ student: CDStudent) throws -> CDYearPlanEntry {
            let entry = CDYearPlanEntry(context: context)
            entry.studentID = try room.id(student).uuidString
            entry.lessonID = try #require(room.second.id).uuidString
            entry.status = .promoted
            entry.promotedAssignmentID = brewing.id?.uuidString
            return entry
        }
        let adasEntry = try entry(room.ada)
        let bensEntry = try entry(room.ben)
        #expect(CoreDataTestHelpers.save(context))

        let split = try #require(PresentationSplitService.splitReadyStudents(
            from: brewing, readyStudentIDs: [try room.id(room.ada)], asDraft: true, context: context
        ))
        #expect(CoreDataTestHelpers.save(context))

        #expect(adasNote.lessonAssignment === split)
        #expect(groupNote.lessonAssignment === brewing)
        #expect(adasEntry.promotedAssignmentID == split.id?.uuidString)
        #expect(bensEntry.promotedAssignmentID == brewing.id?.uuidString)
        #expect(brewing.studentIDs == [try room.id(room.ben).uuidString])
    }
}
