import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Deleting a lesson (bug hunt 2026-10-10, #46, Danny's answer): planned
/// presentations, open work and year-plan entries go; given presentations and
/// history stay, named; sequence- and area-wide files move to a sibling; a file
/// goes to the Trash only after the save and only when nothing else uses it; a
/// failed save rolls everything back.
@Suite("Lesson delete (fix 10-10 H)")
@MainActor
struct LessonDeletionFix1010HTests {

    private struct Fixture {
        let context: NSManagedObjectContext
        let lesson: CDLesson
        let sibling: CDLesson
        let elsewhere: CDLesson
        let ada: CDStudent
        let bruno: CDStudent
        /// Kept apart from the lesson, whose fields read nil once it is deleted.
        let lessonID: UUID
        var repository: LessonRepository { LessonRepository(context: context) }

        func presentation(_ students: [CDStudent], given: Bool) -> CDLessonAssignment {
            let assignment = PresentationFactory.makeDraft(
                lessonID: lessonID, studentIDs: students.compactMap(\.id), context: context
            )
            if given { assignment.markPresented(at: Date(timeIntervalSince1970: 1_780_000_000), snapshotLesson: false) }
            return assignment
        }

        func work(for student: CDStudent, closed: Bool) throws -> CDWorkModel {
            let work = try WorkRepository(context: context).createWork(
                studentID: student.id!, lessonID: lessonID, saveImmediately: false
            )
            if closed {
                try WorkLogService.log(
                    [.init(work: work, status: .keepPracticing)], context: context, saveImmediately: false
                )
            }
            return work
        }

        func note(_ body: String) -> CDNote {
            CoreDataTestHelpers.seedNote(in: context, body: body)
        }

        func entry(for student: CDStudent) -> CDYearPlanEntry {
            let entry = CDYearPlanEntry(context: context)
            entry.studentID = student.id!.uuidString
            entry.lessonID = lessonID.uuidString
            return entry
        }

        func attachment(_ path: String, scope: AttachmentScope = .lesson, on lesson: CDLesson) -> CDLessonAttachment {
            let attachment = CDLessonAttachment(context: context)
            attachment.fileName = (path as NSString).lastPathComponent
            attachment.fileRelativePath = path
            attachment.scope = scope
            attachment.lesson = lesson
            return attachment
        }

        func count<T: NSManagedObject>(_ type: T.Type, lessonID field: String = "lessonID") -> Int {
            let request = CDFetchRequest(type)
            request.predicate = NSPredicate(format: "\(field) == %@", lessonID.uuidString)
            return context.safeFetch(request).count
        }
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads", area: "Math", sequence: "Decimal"
        )
        lesson.section = "Introduction"
        let sibling = CoreDataTestHelpers.seedLesson(in: context, name: "Bank Game", area: "Math ", sequence: "decimal")
        sibling.orderInSequence = 1
        let elsewhere = CoreDataTestHelpers.seedLesson(
            in: context, name: "Stamp Game", area: "Math", sequence: "Operations"
        )
        elsewhere.sortIndex = -1
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Test")
        let bruno = CoreDataTestHelpers.seedStudent(in: context, firstName: "Bruno", lastName: "Test")
        try context.save()
        return Fixture(
            context: context, lesson: lesson, sibling: sibling, elsewhere: elsewhere,
            ada: ada, bruno: bruno, lessonID: try #require(lesson.id)
        )
    }

    /// Two planned presentations (one with a note), one given, open work for Ada with a
    /// note, closed work for Bruno, two year-plan entries and Ada's mastery mark.
    private func seedRecords(_ fixture: Fixture) throws -> (given: CDLessonAssignment, closed: CDWorkModel) {
        let draft = fixture.presentation([fixture.ada], given: false)
        fixture.note("Ready after the bank game").lessonAssignment = draft
        let scheduled = fixture.presentation([fixture.bruno], given: false)
        scheduled.schedule(onDay: Date(timeIntervalSince1970: 1_790_000_000))
        let given = fixture.presentation([fixture.ada, fixture.bruno], given: true)
        let open = try fixture.work(for: fixture.ada, closed: false)
        fixture.note("Counted to 9,000").work = open
        let closed = try fixture.work(for: fixture.bruno, closed: true)
        _ = fixture.entry(for: fixture.ada)
        _ = fixture.entry(for: fixture.bruno)
        let mark = CDLessonPresentation(context: fixture.context)
        mark.studentID = fixture.ada.id!.uuidString
        mark.lessonID = fixture.lessonID.uuidString
        mark.state = .proficient
        mark.masteredAt = Date(timeIntervalSince1970: 1_781_000_000)
        try fixture.context.save()
        return (given, closed)
    }

    @Test("The confirmation names what goes and what stays")
    func summaryNamesEverything() throws {
        let fixture = try makeFixture()
        _ = try seedRecords(fixture)

        let summary = LessonDeletion.plan(for: fixture.lessonID, in: fixture.context).summary

        #expect(summary.plannedPresentations == 2)
        #expect(summary.openWork == 1)
        #expect(summary.yearPlanEntries == 2)
        #expect(summary.notes == 2)
        #expect(summary.givenPresentations == 1)
        let message = summary.message(trashesFiles: true)
        #expect(message.contains("2 planned presentations"))
        #expect(message.contains("1 open work item"))
        #expect(message.contains("2 year-plan entries"))
        #expect(message.contains("2 notes written on them"))
        #expect(message.contains("already given stay"))
        #expect(message.hasSuffix("This can't be undone."))
    }

    @Test("A lesson nothing points at says only that it can't be undone")
    func emptySummary() throws {
        let fixture = try makeFixture()
        let summary = LessonDeletion.plan(for: fixture.lessonID, in: fixture.context).summary
        #expect(summary.message(trashesFiles: true) == "This can't be undone.")
    }

    @Test("Delete removes planned presentations, open work and year-plan entries; history stays named")
    func deleteRemovesAndKeeps() throws {
        let fixture = try makeFixture()
        let (given, closed) = try seedRecords(fixture)
        let lessonID = fixture.lessonID

        try fixture.repository.deleteLesson(id: lessonID, trashFiles: { _ in })

        #expect(fixture.repository.fetchLesson(id: lessonID) == nil)
        let remaining = CDFetchRequest(CDLessonAssignment.self)
        remaining.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        #expect(fixture.context.safeFetch(remaining).map(\.objectID) == [given.objectID])
        #expect(given.lessonTitleSnapshot == "Golden Beads")
        #expect(given.lessonSectionSnapshot == "Introduction")
        #expect(fixture.count(CDWorkModel.self) == 1)
        #expect(!closed.isDeleted)
        #expect(fixture.count(CDYearPlanEntry.self) == 0)
        #expect(fixture.count(CDLessonPresentation.self) == 1)
        #expect(!fixture.context.hasChanges)
    }

    @Test("A file another lesson uses stays; the lesson's own files go to the Trash after the save")
    func filesTrashedOnlyWhenUnused() throws {
        let fixture = try makeFixture()
        fixture.lesson.pagesFileRelativePath = "Math/Decimal/Golden Beads.pages"
        fixture.sibling.pagesFileRelativePath = "Math/Decimal/Golden Beads.pages"
        _ = fixture.attachment("Math/Decimal/Own Card.pdf", on: fixture.lesson)
        _ = fixture.attachment("Math/Decimal/Shared Chart.pdf", on: fixture.lesson)
        _ = fixture.attachment("math/decimal/shared chart.pdf", on: fixture.elsewhere)
        try fixture.context.save()

        var trashed: [URL] = []
        var savedBeforeTrash = false
        try fixture.repository.deleteLesson(id: fixture.lessonID, trashFiles: { urls in
            savedBeforeTrash = !fixture.context.hasChanges
            trashed += urls
        })

        #expect(trashed.map(\.lastPathComponent) == ["Own Card.pdf"])
        #expect(savedBeforeTrash)
    }

    @Test("Sequence- and area-wide attachments move to a lesson still in the sequence")
    func sharedAttachmentsHandedOver() throws {
        let fixture = try makeFixture()
        let sequenceWide = fixture.attachment("Math/Decimal/[Sequence] Beads.pdf", scope: .sequence, on: fixture.lesson)
        let areaWide = fixture.attachment("Math/Decimal/[Area] Facts.pdf", scope: .area, on: fixture.lesson)
        try fixture.context.save()

        var trashed: [URL] = []
        try fixture.repository.deleteLesson(id: fixture.lessonID, trashFiles: { trashed += $0 })

        #expect(!sequenceWide.isDeleted)
        #expect(!areaWide.isDeleted)
        #expect(sequenceWide.lesson === fixture.sibling)
        // The area-wide one prefers the same sequence over an earlier lesson elsewhere in the area.
        #expect(areaWide.lesson === fixture.sibling)
        #expect(trashed.isEmpty)
    }

    @Test("A shared attachment with no lesson left to take it goes with the lesson")
    func sharedAttachmentWithNoHeir() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Only One", area: "Music", sequence: "Bells")
        let attachment = CDLessonAttachment(context: context)
        attachment.fileRelativePath = "Music/Bells/[Area] Scale.pdf"
        attachment.scope = .area
        attachment.lesson = lesson
        try context.save()

        var trashed: [URL] = []
        try LessonRepository(context: context).deleteLesson(id: lesson.id!, trashFiles: { trashed += $0 })

        #expect(attachment.isDeleted || attachment.managedObjectContext == nil)
        #expect(trashed.map(\.lastPathComponent) == ["[Area] Scale.pdf"])
    }

    @Test("A failed save rolls the whole delete back and trashes nothing")
    func failedSaveRollsBack() throws {
        let fixture = try makeFixture()
        let (given, closed) = try seedRecords(fixture)
        let lessonScoped = fixture.attachment("Math/Decimal/Own Card.pdf", on: fixture.lesson)
        let sequenceWide = fixture.attachment("Math/Decimal/[Sequence] Beads.pdf", scope: .sequence, on: fixture.lesson)
        try fixture.context.save()

        var trashCalled = false
        #expect(throws: CocoaError.self) {
            try fixture.repository.deleteLesson(
                id: fixture.lessonID,
                trashFiles: { _ in trashCalled = true },
                save: { context in
                    if context.deletedObjects.contains(where: { $0 is CDLesson }) {
                        throw CocoaError(.validationMultipleErrors)
                    }
                    try context.save()
                }
            )
        }

        #expect(!fixture.lesson.isDeleted)
        #expect(fixture.repository.fetchLesson(id: fixture.lessonID) != nil)
        #expect(fixture.count(CDLessonAssignment.self) == 3)
        #expect(fixture.count(CDWorkModel.self) == 2)
        #expect(!closed.isDeleted)
        #expect(fixture.count(CDYearPlanEntry.self) == 2)
        #expect(given.lessonTitleSnapshot == nil)
        #expect(lessonScoped.lesson === fixture.lesson)
        #expect(sequenceWide.lesson === fixture.lesson)
        #expect(!trashCalled)
        #expect(!fixture.context.hasChanges)
    }

    @Test("In the Sample Class the confirmation doesn't speak of the Trash")
    func sampleClassMessage() {
        let summary = LessonDeletionSummary(files: 2)
        #expect(summary.message(trashesFiles: true).contains("Trash"))
        #expect(!summary.message(trashesFiles: false).contains("Trash"))
    }
}
