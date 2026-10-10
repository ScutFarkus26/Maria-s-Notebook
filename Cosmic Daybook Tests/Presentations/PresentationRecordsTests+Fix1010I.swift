import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, P2 #62–64 and #58's Give Lesson save: merging keeps
/// notes and year-plan entries, Change Lesson moves the history with it,
/// mastery edits reach every row, and recording with practice saves once.
@Suite("Presentation records (bug hunt 2026-10-10)")
@MainActor
struct PresentationRecordsFix1010ITests {

    private struct Room {
        let context: NSManagedObjectContext
        let ada: CDStudent
        let ben: CDStudent
        let lesson: CDLesson
        let other: CDLesson
    }

    private func makeRoom() throws -> Room {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lane")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Ross")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads", sequence: "Decimal")
        let other = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", sequence: "Decimal")
        #expect(CoreDataTestHelpers.save(context))
        return Room(context: context, ada: ada, ben: ben, lesson: lesson, other: other)
    }

    private func draft(_ lesson: CDLesson, _ students: [CDStudent], in context: NSManagedObjectContext) throws
        -> CDLessonAssignment {
        PresentationFactory.makeDraft(
            lessonID: try #require(lesson.id), studentIDs: try students.map { try #require($0.id) }, context: context
        )
    }

    private func promotedEntry(
        for student: CDStudent, into plan: CDLessonAssignment, in context: NSManagedObjectContext
    ) throws -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = try #require(student.id).uuidString
        entry.lessonID = plan.lessonID
        entry.status = .promoted
        entry.promotedAssignmentID = try #require(plan.id).uuidString
        return entry
    }

    private func rows(_ context: NSManagedObjectContext) -> [CDLessonPresentation] {
        context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
    }

    // MARK: - #62 Merging

    @Test("Merging two plans keeps the source's notes and points its promoted entries at the target")
    func mergeKeepsNotesAndEntries() throws {
        let room = try makeRoom()
        let target = try draft(room.lesson, [room.ada], in: room.context)
        let source = try draft(room.lesson, [room.ben], in: room.context)
        CoreDataTestHelpers.seedNote(in: room.context, body: "Ben counted to a thousand").lessonAssignment = source
        let entry = try promotedEntry(for: room.ben, into: source, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        let merged = PresentationMergeService.merge(
            sourceID: try #require(source.id), targetID: try #require(target.id), context: room.context
        )
        #expect(merged)
        #expect(room.context.safeFetch(CDFetchRequest(CDLessonAssignment.self)) == [target])
        // Fetched, not read off `note`: a note that cascaded away can't be read.
        let notes = room.context.safeFetch(CDFetchRequest(CDNote.self))
        #expect(notes.count == 1)
        #expect(notes.first?.lessonAssignment == target)
        #expect(entry.isPromoted)
        #expect(entry.promotedAssignmentID == target.id?.uuidString)
    }

    @Test("Moving one child between plans takes her promoted entry with her")
    func moveStudentTakesHerEntry() throws {
        let room = try makeRoom()
        let source = try draft(room.lesson, [room.ada, room.ben], in: room.context)
        let target = try draft(room.lesson, [], in: room.context)
        let adasEntry = try promotedEntry(for: room.ada, into: source, in: room.context)
        let bensEntry = try promotedEntry(for: room.ben, into: source, in: room.context)

        let adaID = try #require(room.ada.id).uuidString
        PresentationRecordCleanup.moveStudents([adaID], from: source, to: target, in: room.context)

        #expect(adasEntry.promotedAssignmentID == target.id?.uuidString)
        #expect(bensEntry.promotedAssignmentID == source.id?.uuidString)
    }

    @Test("Folding an emptied plan into another moves its notes; an entry for a child not on the target goes back")
    func prepareToMergeEmptiedPlan() throws {
        let room = try makeRoom()
        let target = try draft(room.lesson, [room.ada], in: room.context)
        let source = try draft(room.lesson, [], in: room.context)
        let note = CoreDataTestHelpers.seedNote(in: room.context, body: "Planned with the beads")
        note.lessonAssignment = source
        let stranded = try promotedEntry(for: room.ben, into: source, in: room.context)

        PresentationRecordCleanup.prepareToMerge(source, into: target, in: room.context)
        room.context.delete(source)
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(note.lessonAssignment == target)
        #expect(stranded.status == .planned)
        #expect(stranded.promotedAssignmentID == nil)
    }

    @Test("The draft dedup points entries promoted into a duplicate at the survivor")
    func draftDedupKeepsEntries() throws {
        let room = try makeRoom()
        let older = try draft(room.lesson, [room.ada], in: room.context)
        older.createdAt = Date(timeIntervalSince1970: 1_000)
        let newer = try draft(room.lesson, [room.ada], in: room.context)
        newer.createdAt = Date(timeIntervalSince1970: 2_000)
        let entry = try promotedEntry(for: room.ada, into: newer, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        DataCleanupService.deduplicateDraftLessonAssignments(using: room.context)

        #expect(room.context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).count == 1)
        #expect(entry.isPromoted)
        #expect(entry.promotedAssignmentID == older.id?.uuidString)
    }

    // MARK: - #63 Change Lesson

    private func given(_ students: [CDStudent], lesson: CDLesson, in context: NSManagedObjectContext) throws
        -> CDLessonAssignment {
        let assignment = try draft(lesson, students, in: context)
        _ = try LifecycleService.recordPresentation(
            from: assignment, presentedAt: try CoreDataTestHelpers.day("2026-09-14"), modelContext: context
        )
        #expect(CoreDataTestHelpers.save(context))
        return assignment
    }

    private func detailViewModel(for assignment: CDLessonAssignment, in context: NSManagedObjectContext)
        -> PresentationDetailViewModel {
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        return PresentationDetailViewModel(
            lessonAssignment: assignment, viewContext: context, saveCoordinator: coordinator
        )
    }

    @Test("Change Lesson on a dated given presentation moves the children's history rows to the new lesson")
    func changeLessonMovesDatedHistory() throws {
        let room = try makeRoom()
        let assignment = try given([room.ada, room.ben], lesson: room.lesson, in: room.context)
        #expect(rows(room.context).count == 2)

        let vm = detailViewModel(for: assignment, in: room.context)
        vm.editingLessonID = try #require(room.other.id)
        vm.save(
            studentsAll: [room.ada, room.ben], lessons: [room.lesson, room.other],
            lessonAssignmentsAll: [assignment], calendar: AppCalendar.shared
        )

        let otherID = try #require(room.other.id).uuidString
        let history = rows(room.context)
        #expect(history.count == 2)
        #expect(history.allSatisfy { $0.lessonID == otherID })
        #expect(history.allSatisfy { $0.presentationID == assignment.id?.uuidString })
    }

    @Test("Change Lesson on an undated given presentation moves its rows and makes no unlinked one")
    func changeLessonMovesUndatedHistory() throws {
        let room = try makeRoom()
        let assignment = try draft(room.lesson, [room.ada], in: room.context)
        assignment.markPreviouslyPresented()
        let row = CDLessonPresentation(context: room.context)
        row.studentID = try #require(room.ada.id).uuidString
        row.lessonID = assignment.lessonID
        row.presentationID = try #require(assignment.id).uuidString
        row.state = .presented
        #expect(CoreDataTestHelpers.save(room.context))

        let vm = detailViewModel(for: assignment, in: room.context)
        vm.editingLessonID = try #require(room.other.id)
        vm.save(
            studentsAll: [room.ada], lessons: [room.lesson, room.other],
            lessonAssignmentsAll: [assignment], calendar: AppCalendar.shared
        )

        let history = rows(room.context)
        #expect(history.count == 1)
        #expect(history.first?.lessonID == room.other.id?.uuidString)
        #expect(history.allSatisfy { $0.presentationID != nil })
    }

    @Test("Recording again after the lesson changed moves the rows rather than leaving them behind")
    func recordingRelinksRows() throws {
        let room = try makeRoom()
        let assignment = try given([room.ada], lesson: room.lesson, in: room.context)
        let row = try #require(rows(room.context).first)
        row.trackStepID = UUID().uuidString

        assignment.lessonID = try #require(room.other.id).uuidString
        _ = try LifecycleService.recordPresentation(
            from: assignment, presentedAt: try CoreDataTestHelpers.day("2026-09-15"), modelContext: room.context
        )

        #expect(rows(room.context).count == 1)
        #expect(row.lessonID == room.other.id?.uuidString)
        #expect(row.trackStepID == nil)
    }

    @Test("Change Lesson returns the old lesson's promoted entries to planned and keeps the new lesson's")
    func changeLessonReturnsOldLessonsEntries() throws {
        let room = try makeRoom()
        let assignment = try given([room.ada, room.ben], lesson: room.lesson, in: room.context)
        let oldEntry = try promotedEntry(for: room.ada, into: assignment, in: room.context)
        let newEntry = try promotedEntry(for: room.ben, into: assignment, in: room.context)
        newEntry.lessonID = try #require(room.other.id).uuidString
        #expect(CoreDataTestHelpers.save(room.context))

        let vm = detailViewModel(for: assignment, in: room.context)
        vm.editingLessonID = try #require(room.other.id)
        vm.save(
            studentsAll: [room.ada, room.ben], lessons: [room.lesson, room.other],
            lessonAssignmentsAll: [assignment], calendar: AppCalendar.shared
        )

        #expect(oldEntry.status == .planned)
        #expect(oldEntry.promotedAssignmentID == nil)
        #expect(newEntry.isPromoted)
        #expect(newEntry.promotedAssignmentID == assignment.id?.uuidString)
    }

    @Test("Recording a presentation on another lesson returns the old lesson's promoted entries")
    func recordingOnAnotherLessonReturnsEntries() throws {
        let room = try makeRoom()
        let plan = try draft(room.lesson, [room.ada], in: room.context)
        let entry = try promotedEntry(for: room.ada, into: plan, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        plan.lessonID = try #require(room.other.id).uuidString
        _ = try LifecycleService.recordPresentation(
            from: plan, presentedAt: try CoreDataTestHelpers.day("2026-09-15"), modelContext: room.context
        )

        #expect(entry.status == .planned)
        #expect(entry.promotedAssignmentID == nil)
    }

    // MARK: - #64 Every row for the pair

    @Test("The Sequence Recap's mastery edit reaches every row the child has for the lesson")
    func siblingMasteryReachesEveryRow() throws {
        let room = try makeRoom()
        let first = try given([room.ada], lesson: room.lesson, in: room.context)
        _ = try given([room.ada], lesson: room.lesson, in: room.context)
        #expect(rows(room.context).count == 2)

        let vm = detailViewModel(for: first, in: room.context)
        vm.updateSiblingLessonProficiencyState(
            lessonID: try #require(room.lesson.id).uuidString,
            studentID: try #require(room.ada.id).uuidString,
            state: .proficient,
            lessons: [room.lesson, room.other],
            currentLesson: room.lesson,
            students: [room.ada]
        )

        #expect(rows(room.context).count == 2)
        #expect(rows(room.context).allSatisfy { $0.state == .proficient && $0.masteredAt != nil })
    }

    @Test("The detail view's mastery control reaches every row the child has for the lesson")
    func detailMasteryReachesEveryRow() throws {
        let room = try makeRoom()
        let first = try given([room.ada], lesson: room.lesson, in: room.context)
        _ = try given([room.ada], lesson: room.lesson, in: room.context)

        let vm = detailViewModel(for: first, in: room.context)
        vm.updateProficiencyState(
            lessonID: first.lessonID, studentIDs: first.studentIDs, state: .proficient, guideChangedState: true
        )

        #expect(rows(room.context).count == 2)
        #expect(rows(room.context).allSatisfy { $0.state == .proficient })
    }

    // MARK: - #58 Give Lesson saves once

    @Test("Recording with practice leaves the work unsaved for the caller's one save")
    func explodeWorkDoesNotSaveEachChild() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        #expect(CoreDataTestHelpers.save(context))
        let assignment = try draft(lesson, [ada, ben], in: context)

        let result = try LifecycleService.recordPresentationAndExplodeWork(
            from: assignment, presentedAt: Date(), modelContext: context
        )
        #expect(result.work.count == 2)

        let background = stack.newBackgroundContext()
        let savedWork = await background.perform {
            (try? background.count(for: CDFetchRequest(CDWorkModel.self))) ?? -1
        }
        #expect(savedWork == 0)
        #expect(context.hasChanges)
    }
}
