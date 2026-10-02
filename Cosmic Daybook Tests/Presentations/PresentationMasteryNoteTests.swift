import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Present-a-lesson mastery note")
@MainActor
struct PresentationMasteryNoteTests {

    private func row(
        _ context: NSManagedObjectContext, student: String, lesson: String,
        state: LessonPresentationState, masteredAt: Date? = nil
    ) {
        let row = CDLessonPresentation(context: context)
        row.studentID = student
        row.lessonID = lesson
        row.state = state
        row.masteredAt = masteredAt
    }

    @Test("Only marked children come back, each with the day first marked")
    func masteryDates() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let lesson = UUID().uuidString, otherLesson = UUID().uuidString
        let maya = UUID().uuidString, ada = UUID().uuidString, iris = UUID().uuidString
        let noa = UUID().uuidString, outside = UUID().uuidString
        let sep12 = try CoreDataTestHelpers.day("2026-09-12")
        let oct1 = try CoreDataTestHelpers.day("2026-10-01")

        // Maya: mastered Sep 12, then given again (a second, presented-only row).
        row(context, student: maya, lesson: lesson, state: .proficient, masteredAt: sep12)
        row(context, student: maya, lesson: lesson, state: .presented)
        // Ada: two marked rows; the earlier day wins.
        row(context, student: ada, lesson: lesson, state: .proficient, masteredAt: oct1)
        row(context, student: ada, lesson: lesson, state: .proficient, masteredAt: sep12)
        // Iris: proficient with no date.
        row(context, student: iris, lesson: lesson, state: .proficient)
        // Noa: presented only here, mastered on another lesson.
        row(context, student: noa, lesson: lesson, state: .practicing)
        row(context, student: noa, lesson: otherLesson, state: .proficient, masteredAt: sep12)
        // Not in the group.
        row(context, student: outside, lesson: lesson, state: .proficient, masteredAt: sep12)
        #expect(CoreDataTestHelpers.save(context))

        let dates = PresentationRecordIndex.masteryDates(
            lessonID: lesson, studentIDs: [maya, ada, iris, noa], in: context
        )
        #expect(Set(dates.keys) == [maya, ada, iris])
        #expect(dates[maya] == .some(sep12))
        #expect(dates[ada] == .some(sep12))
        #expect(dates[iris] == .some(nil))
        #expect(PresentationRecordIndex.masteryDates(lessonID: lesson, studentIDs: [], in: context).isEmpty)
    }

    @Test("The note reads \"mastered Sep 12\", adds the year outside this one, or says just \"mastered\"")
    func noteText() throws {
        let calendar = AppCalendar.shared
        let now = try CoreDataTestHelpers.day("2026-10-02")
        let sep12 = try CoreDataTestHelpers.day("2026-09-12")
        let lastYear = try CoreDataTestHelpers.day("2025-05-03")
        #expect(PresentationMasteryNote.text(masteredOn: sep12, now: now, calendar: calendar) == "mastered Sep 12")
        #expect(PresentationMasteryNote.text(masteredOn: lastYear, now: now, calendar: calendar) == "mastered May 3, 2025")
        #expect(PresentationMasteryNote.text(masteredOn: nil, now: now, calendar: calendar) == "mastered")
    }
}
