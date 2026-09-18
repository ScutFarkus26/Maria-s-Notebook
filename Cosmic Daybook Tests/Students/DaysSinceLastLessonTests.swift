import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The roster's "days since last lesson" column. It reads a year of presented
/// assignments and folds them into one date per child, so it has to read the
/// student-id blob and the Parsha exclusion correctly — the two things the
/// fetch-shape rewrite touched.
@Suite("Days since last lesson")
@MainActor
struct DaysSinceLastLessonTests {

    private func seedStudent(in context: NSManagedObjectContext, named name: String) -> CDStudent {
        let student = CDStudent(context: context)
        student.firstName = name
        student.lastName = "Test"
        return student
    }

    private func seedLesson(
        in context: NSManagedObjectContext,
        name: String,
        area: String,
        sequence: String
    ) -> CDLesson {
        let lesson = CDLesson(context: context)
        lesson.name = name
        lesson.area = area
        lesson.sequence = sequence
        return lesson
    }

    @discardableResult
    private func seedPresentation(
        in context: NSManagedObjectContext,
        lesson: CDLesson,
        students: [CDStudent],
        on day: Date
    ) -> CDLessonAssignment {
        let assignment = CDLessonAssignment(context: context)
        assignment.lessonID = lesson.id?.uuidString ?? ""
        assignment.studentIDs = students.compactMap { $0.id?.uuidString }
        assignment.state = .presented
        assignment.presentedAt = day
        assignment.createdAt = day
        return assignment
    }

    private func daysMap(
        for students: [CDStudent],
        in context: NSManagedObjectContext
    ) -> [UUID: Int] {
        StudentsViewModel().computeDaysSinceLastLessonCache(
            for: students, using: context, calendar: AppCalendar.shared
        )
    }

    @Test("Each child's count comes from her own most recent presentation")
    func daysMapReflectsEachStudentsLastPresentation() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        SchoolCalendarService.shared.invalidateCache()
        let today = AppCalendar.startOfDay(Date())

        let maya = seedStudent(in: context, named: "Maya")
        let sarah = seedStudent(in: context, named: "Sarah")
        let tzipporah = seedStudent(in: context, named: "Tzipporah")
        let geometry = seedLesson(in: context, name: "Constructive Triangles",
                                  area: "Mathematics", sequence: "Geometry")

        seedPresentation(in: context, lesson: geometry, students: [maya],
                         on: AppCalendar.addingDays(-20, to: today))
        seedPresentation(in: context, lesson: geometry, students: [sarah],
                         on: AppCalendar.addingDays(-5, to: today))
        #expect(CoreDataTestHelpers.save(context))

        let mayaID = try #require(maya.id)
        let sarahID = try #require(sarah.id)
        let tzipporahID = try #require(tzipporah.id)
        let days = daysMap(for: [maya, sarah, tzipporah], in: context)

        let mayaDays = try #require(days[mayaID])
        let sarahDays = try #require(days[sarahID])
        #expect(mayaDays > sarahDays)
        #expect(sarahDays >= 0)
        // A child who has never been given a lesson is -1, not zero.
        #expect(days[tzipporahID] == -1)
    }

    @Test("A group presentation counts for every child on its roster")
    func groupPresentationCountsForEveryone() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        SchoolCalendarService.shared.invalidateCache()
        let today = AppCalendar.startOfDay(Date())

        let maya = seedStudent(in: context, named: "Maya")
        let sarah = seedStudent(in: context, named: "Sarah")
        let geometry = seedLesson(in: context, name: "Constructive Triangles",
                                  area: "Mathematics", sequence: "Geometry")
        let history = seedLesson(in: context, name: "Clock of Eras",
                                 area: "History", sequence: "Time")

        seedPresentation(in: context, lesson: geometry, students: [maya],
                         on: AppCalendar.addingDays(-20, to: today))
        // Both children on one row — their ids live in a single encoded blob.
        seedPresentation(in: context, lesson: history, students: [maya, sarah],
                         on: AppCalendar.addingDays(-2, to: today))
        #expect(CoreDataTestHelpers.save(context))

        let mayaID = try #require(maya.id)
        let sarahID = try #require(sarah.id)
        let days = daysMap(for: [maya, sarah], in: context)

        // The later group lesson wins for Maya over her own older one.
        let mayaDays = try #require(days[mayaID])
        let sarahDays = try #require(days[sarahID])
        #expect(mayaDays == sarahDays)
        #expect(mayaDays >= 0)
    }

    @Test("A Parsha lesson does not reset the count")
    func parshaPresentationsAreExcluded() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        SchoolCalendarService.shared.invalidateCache()
        let today = AppCalendar.startOfDay(Date())

        let maya = seedStudent(in: context, named: "Maya")
        let geometry = seedLesson(in: context, name: "Constructive Triangles",
                                  area: "Mathematics", sequence: "Geometry")
        // Padding and capitals, because the match is a trimmed, lowercased compare.
        let parsha = seedLesson(in: context, name: "Noach", area: " Parsha ", sequence: "Noach")

        seedPresentation(in: context, lesson: geometry, students: [maya],
                         on: AppCalendar.addingDays(-20, to: today))
        #expect(CoreDataTestHelpers.save(context))

        let mayaID = try #require(maya.id)
        let before = try #require(daysMap(for: [maya], in: context)[mayaID])

        seedPresentation(in: context, lesson: parsha, students: [maya], on: today)
        #expect(CoreDataTestHelpers.save(context))

        let after = try #require(daysMap(for: [maya], in: context)[mayaID])
        #expect(after == before)
    }

    @Test("A presentation that has not been saved yet still counts")
    func pendingInsertsAreCounted() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        SchoolCalendarService.shared.invalidateCache()
        let today = AppCalendar.startOfDay(Date())

        let maya = seedStudent(in: context, named: "Maya")
        let geometry = seedLesson(in: context, name: "Constructive Triangles",
                                  area: "Mathematics", sequence: "Geometry")
        #expect(CoreDataTestHelpers.save(context))

        // Deliberately not saved: the column-only fetch cannot see a pending
        // insert, so the read has to notice the dirty context and fall back.
        seedPresentation(in: context, lesson: geometry, students: [maya],
                         on: AppCalendar.addingDays(-3, to: today))

        let mayaID = try #require(maya.id)
        #expect(try #require(daysMap(for: [maya], in: context)[mayaID]) >= 0)
    }
}
