import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Deleting a lesson keeps the presentations already given, and their history
/// rows, as history (2026-10-10 hunt). Clean Up Old Records mustn't then remove
/// those rows as "lessons given whose lesson was deleted".
@Suite("Notebook junk cleanup — kept history of a deleted lesson")
@MainActor
struct NotebookJunkCleanupKeptHistoryTests {

    @Test("a deleted lesson's history row stays while its given presentation does, and its mastery mark stays")
    func keptHistoryStays() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context)
        let given = CDLessonAssignment(context: context)
        given.id = UUID()
        given.lessonID = UUID().uuidString  // a lesson that no longer exists
        CoreDataTestHelpers.save(context)

        let kept = CDLessonPresentation(context: context)
        kept.studentID = student.id?.uuidString ?? ""
        kept.lessonID = given.lessonID
        kept.presentationID = given.id?.uuidString.lowercased()
        let orphan = CDLessonPresentation(context: context)
        orphan.studentID = student.id?.uuidString ?? ""
        orphan.lessonID = given.lessonID
        orphan.presentationID = UUID().uuidString  // its presentation is gone too
        // A mastery mark of the deleted lesson stays, as `LessonDeletion` keeps it.
        let mark = CDLessonPresentation(context: context)
        mark.studentID = student.id?.uuidString ?? ""
        mark.lessonID = given.lessonID
        mark.state = .proficient
        mark.masteredAt = Date()
        CoreDataTestHelpers.save(context)

        let today = AppCalendar.startOfDay(Date())
        let preview = NotebookJunkCleanup.run(in: context, today: today, apply: false)
        let done = NotebookJunkCleanup.run(in: context, today: today, apply: true)
        #expect(done == preview)
        #expect(CoreDataTestHelpers.save(context))

        #expect(done.presentationsOfDeletedLessons == 1)
        #expect(kept.isDeleted == false && kept.managedObjectContext != nil)
        #expect(orphan.managedObjectContext == nil || orphan.isDeleted)
        #expect(mark.isDeleted == false && mark.managedObjectContext != nil)
    }
}
