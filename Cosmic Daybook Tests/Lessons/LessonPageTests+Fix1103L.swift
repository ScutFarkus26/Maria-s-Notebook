import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-11-03, #7, #16 and #17 (the lesson page's part).
//
// #7: moving a lesson to another area or sub-area in the edit form kept its
// old order number, so it tied with or jumped ahead of lessons already there.
// It now lands last, as Add Lesson and a drag place it.
//
// #16: the Lesson Journey named and counted hidden test students and
// children who left.
//
// #17: Import… and Remove for the Pages file saved at once, so Cancel undid
// neither. The form now holds the change in its draft until Save.

@Suite("The lesson page: moves, the Journey's roster, the Pages file (bug hunt 11-03)")
@MainActor
struct LessonPageFix1103LTests {

    // MARK: - #7 A moved lesson lands last

    @Test("A lesson moved to another sub-area lands after its last lesson, not at its old number")
    func movedLessonLandsLast() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let repository = LessonRepository(context: context)
        let halves = try repository.createLesson(
            name: "Halves", area: "Math", sequence: "Fractions", orderInSequence: 0
        )
        _ = try repository.createLesson(name: "Thirds", area: "Math", sequence: "Fractions", orderInSequence: 1)
        let quarters = try repository.createLesson(
            name: "Quarters", area: "Math", sequence: "Fractions", orderInSequence: 2
        )
        _ = try repository.createLesson(name: "Tenths", area: "Math", sequence: "Decimals", orderInSequence: 0)
        let hundredths = try repository.createLesson(
            name: "Hundredths", area: "Math", sequence: "Decimals", orderInSequence: 1
        )
        #expect(CoreDataTestHelpers.save(context))

        var draft = LessonEditDraft(lesson: hundredths)
        draft.sequence = " fractions"
        #expect(try draft.apply(to: hundredths))

        #expect(hundredths.orderInSequence == 3)
        let fractions = context.safeFetch(CDFetchRequest(CDLesson.self))
            .filter { $0.sequence.trimmed().lowercased() == "fractions" }
        let ordered = LessonSequenceOrdering.sorted(fractions)
        #expect(ordered.first === halves)
        #expect(ordered.last === hundredths)
        #expect(ordered.dropLast().last === quarters)
    }

    @Test("Moving to another area lands last there; an edit that keeps the sub-area keeps the number")
    func areaMoveLandsLastAndPlainEditsKeepTheirPlace() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let repository = LessonRepository(context: context)
        _ = try repository.createLesson(name: "Square", area: "Geometry", sequence: "Area", orderInSequence: 0)
        _ = try repository.createLesson(name: "Rectangle", area: "Geometry", sequence: "Area", orderInSequence: 4)
        let triangle = try repository.createLesson(name: "Triangle", area: "Math", sequence: "Area", orderInSequence: 1)
        let circle = try repository.createLesson(name: "Circle", area: "Math", sequence: "Area", orderInSequence: 2)
        #expect(CoreDataTestHelpers.save(context))

        var moved = LessonEditDraft(lesson: triangle)
        moved.area = "Geometry"
        #expect(try moved.apply(to: triangle))
        #expect(triangle.orderInSequence == 5)

        var renamed = LessonEditDraft(lesson: circle)
        renamed.name = "Circles"
        renamed.sequence = "area "
        #expect(try renamed.apply(to: circle))
        #expect(circle.orderInSequence == 2)
    }

    @Test("A failed save puts a moved lesson back at its old number")
    func restorePutsTheOldNumberBack() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let repository = LessonRepository(context: context)
        _ = try repository.createLesson(name: "Halves", area: "Math", sequence: "Fractions", orderInSequence: 0)
        let tenths = try repository.createLesson(name: "Tenths", area: "Math", sequence: "Decimals", orderInSequence: 7)
        #expect(CoreDataTestHelpers.save(context))

        let onDisk = LessonEditDraft(lesson: tenths)
        var draft = onDisk
        draft.sequence = "Fractions"
        #expect(try draft.apply(to: tenths))
        #expect(tenths.orderInSequence == 1)

        onDisk.restore(tenths)
        #expect(tenths.sequence == "Decimals")
        #expect(tenths.orderInSequence == 7)
    }

    // MARK: - #16 The Lesson Journey's roster

    @Test("The Lesson Journey shows enrolled, visible children only")
    func journeyShowsEnrolledVisibleChildren() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stein")
        let left = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Eli", lastName: "Gold", enrollmentStatus: .withdrawn
        )
        let moved = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Noa", lastName: "Katz", enrollmentStatus: .transferred
        )
        let test = CoreDataTestHelpers.seedStudent(in: context, firstName: "Lil Dan", lastName: "D")

        let shown = LessonJourneyTimeline.shownStudents(
            [maya, left, moved, test], showTestStudents: false, testStudentNames: "Lil Dan D"
        )
        #expect(shown.map(\.shortName) == ["Maya S"])
    }

    // MARK: - #17 The Pages file waits for Save

    @Test("Remove in the form leaves the lesson's Pages file until Save, and a failed save puts it back")
    func removeWaitsForSave() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Timeline of Life")
        lesson.pagesFileBookmark = Data([1, 2, 3])
        lesson.pagesFileRelativePath = "Timeline of Life.pages"
        #expect(CoreDataTestHelpers.save(context))

        let onDisk = LessonEditDraft(lesson: lesson)
        var draft = onDisk
        draft.pagesFileChange = .removed
        #expect(lesson.pagesFileRelativePath == "Timeline of Life.pages")

        #expect(try draft.apply(to: lesson))
        #expect(lesson.pagesFileBookmark == nil)
        #expect(lesson.pagesFileRelativePath == nil)

        onDisk.restore(lesson)
        #expect(lesson.pagesFileBookmark == Data([1, 2, 3]))
        #expect(lesson.pagesFileRelativePath == "Timeline of Life.pages")
    }

    @Test("Import in the form points the lesson at the copy only on Save; an untouched draft keeps the file")
    func importWaitsForSave() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Timeline of Life")
        lesson.pagesFileRelativePath = "Old.pages"
        #expect(CoreDataTestHelpers.save(context))

        var untouched = LessonEditDraft(lesson: lesson)
        untouched.writeUp = "Unroll it slowly."
        #expect(try untouched.apply(to: lesson))
        #expect(lesson.pagesFileRelativePath == "Old.pages")

        var draft = LessonEditDraft(lesson: lesson)
        let copy = LessonEditDraft.PagesFileCopy(
            url: URL(fileURLWithPath: "/tmp/Timeline of Life 2.pages"),
            bookmark: Data([9]),
            relativePath: "Timeline of Life 2.pages"
        )
        draft.pagesFileChange = .imported(copy)
        #expect(draft.pendingPagesCopyURL == copy.url)
        #expect(lesson.pagesFileRelativePath == "Old.pages")

        #expect(try draft.apply(to: lesson))
        #expect(lesson.pagesFileBookmark == Data([9]))
        #expect(lesson.pagesFileRelativePath == "Timeline of Life 2.pages")
    }
}
