import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Lesson order and matching on the Lessons screen (bug hunt 2026-10-10, #43–45, #48):
/// a drag or Move Earlier/Later works on the whole sequence by lesson id, so a filter
/// chip can't move the wrong lesson and a tie can't swallow a move; a new lesson goes
/// after the sequence's last; area and sequence match trimmed and in any case; "Has
/// File" counts attachments.
@Suite("Lesson order, area match and Has File (fix 10-10 H)")
@MainActor
struct LessonOrderingFix1010HTests {

    private func lessons(
        _ names: [String], orders: [Int64], in context: NSManagedObjectContext,
        area: String = "Math", sequence: String = "Decimal"
    ) -> [CDLesson] {
        zip(names, orders).map { name, order in
            let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: area, sequence: sequence)
            lesson.orderInSequence = order
            return lesson
        }
    }

    private func names(_ lessons: [CDLesson]) -> [String] {
        LessonSequenceOrdering.sorted(lessons).map(\.name)
    }

    @Test("A drag moves the lesson it names, and every lesson in the sequence is renumbered")
    func dragMovesByIDOverWholeSequence() throws {
        let context = try CoreDataTestHelpers.makeContext()
        // B is personal, so an Album chip hides it from the screen; the move still counts it.
        let sequence = lessons(["A", "B", "C", "D"], orders: [0, 1, 2, 3], in: context)
        sequence[1].source = .personal

        #expect(LessonSequenceOrdering.move(sequence[3].id!, onto: sequence[0].id!, in: sequence))

        #expect(names(sequence) == ["D", "A", "B", "C"])
        #expect(LessonSequenceOrdering.sorted(sequence).map(\.orderInSequence) == [0, 1, 2, 3])

        // Moving later lands after the lesson dropped on.
        #expect(LessonSequenceOrdering.move(sequence[3].id!, onto: sequence[2].id!, in: sequence))
        #expect(names(sequence) == ["A", "B", "C", "D"])
    }

    @Test("A drag naming a lesson outside the sequence changes nothing")
    func dragOutsideSequence() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let sequence = lessons(["A", "B"], orders: [0, 1], in: context)
        #expect(!LessonSequenceOrdering.move(UUID(), onto: sequence[0].id!, in: sequence))
        #expect(names(sequence) == ["A", "B"])
    }

    @Test("Move Earlier works on two lessons that share a number")
    func stepThroughATie() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let sequence = lessons(["A", "B", "C"], orders: [0, 0, 1], in: context)

        #expect(LessonSequenceOrdering.step(sequence[1].id!, by: -1, in: sequence))

        #expect(names(sequence) == ["B", "A", "C"])
        #expect(LessonSequenceOrdering.sorted(sequence).map(\.orderInSequence) == [0, 1, 2])
        #expect(!LessonSequenceOrdering.step(sequence[1].id!, by: -1, in: sequence))
    }

    @Test("A new lesson goes after the last one in its sequence, spacing and case aside")
    func newLessonOrder() throws {
        let context = try CoreDataTestHelpers.makeContext()
        _ = lessons(["A", "B"], orders: [0, 4], in: context, area: "Math ", sequence: "decimal")
        _ = lessons(["Other"], orders: [9], in: context, area: "Math", sequence: "Fractions")
        let repository = LessonRepository(context: context)

        #expect(repository.nextOrderInSequence(area: "math", sequence: " Decimal") == 5)
        #expect(repository.nextOrderInSequence(area: "Math", sequence: "Geometry") == 0)
    }

    @Test("Bulk entry numbers after lessons stored with other spacing or case")
    func bulkEntryOrderKeys() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let existing = lessons(["A"], orders: [2], in: context, area: "Math ", sequence: "decimal")
        let repository = LessonRepository(context: context)

        let outcome = BulkLessonInsertion.insert(
            [BulkLessonDraft(name: "New", area: "Math", sequence: "Decimal", section: "", writeUp: "")],
            using: repository, source: .album, personalKind: nil,
            maxOrderBySequence: BulkLessonInsertion.maxOrders(of: existing)
        )

        #expect(outcome.inserted.map(\.orderInSequence) == [3])
    }

    @Test("Picking an area keeps lessons stored with other spacing or case")
    func areaMatchIgnoresSpacingAndCase() throws {
        let context = try CoreDataTestHelpers.makeContext()
        for (name, area) in [("A", "Math"), ("B", "Math "), ("C", "math"), ("D", " MATH"),
                             ("E", "Mathematics"), ("F", "Geometry")] {
            _ = CoreDataTestHelpers.seedLesson(in: context, name: name, area: area, sequence: "")
        }
        try context.save()

        let shown = LessonsViewModel().filteredLessons(
            viewContext: context, sourceFilter: nil, personalKindFilter: nil,
            searchText: "", selectedArea: "Math", selectedSequence: nil
        )

        #expect(Set(shown.map(\.name)) == ["A", "B", "C", "D"])
    }

    @Test("Has File counts a lesson's attachments, not only its Pages file")
    func hasFileCountsAttachments() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let plain = CoreDataTestHelpers.seedLesson(in: context, name: "Plain")
        let attached = CoreDataTestHelpers.seedLesson(in: context, name: "Attached")
        let pages = CoreDataTestHelpers.seedLesson(in: context, name: "Pages")
        let attachment = CDLessonAttachment(context: context)
        attachment.fileRelativePath = "Math/Counting/Card.pdf"
        attachment.lesson = attached
        pages.pagesFileRelativePath = "Math/Counting/Pages.pages"

        #expect(!plain.hasAnyFile)
        #expect(attached.hasAnyFile)
        #expect(pages.hasAnyFile)
    }
}
