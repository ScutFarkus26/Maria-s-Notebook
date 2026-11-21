import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Domain-logic review R21: two lessons tied on `orderInSequence` (older
/// lessons took 0, and two devices can each take max+1) used to get a
/// different "next" on each screen. Plan-next sorted by order only, Groups
/// and the ready queue broke the tie by name, the Checklist by `sortIndex`
/// then name, and Claude and Meetings had their own. One `LessonOrder` now
/// decides: order, then `sortIndex`, then name, then id.
@Suite("Lesson order agreement (domain logic R21)")
@MainActor
struct LessonOrderAgreementTests {

    /// Math › Decimal: A (0), then Zebra and Apple tied on 1 (Zebra has the
    /// lower `sortIndex`, so it comes first), then D (2). Passed in the order
    /// A, Apple, Zebra, D, so a rule that ignores `sortIndex` reads Apple next.
    private struct Fixture {
        let context: NSManagedObjectContext
        let first: CDLesson
        let zebra: CDLesson
        let apple: CDLesson
        let last: CDLesson

        var shuffled: [CDLesson] { [first, apple, zebra, last] }
        var expected: [CDLesson] { [first, zebra, apple, last] }
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        func lesson(_ name: String, order: Int64, sortIndex: Int64) -> CDLesson {
            let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: "Math", sequence: "Decimal")
            lesson.orderInSequence = order
            lesson.sortIndex = sortIndex
            return lesson
        }
        let fixture = Fixture(
            context: context,
            first: lesson("Decimal A", order: 0, sortIndex: 0),
            zebra: lesson("Zebra step", order: 1, sortIndex: 1),
            apple: lesson("Apple step", order: 1, sortIndex: 2),
            last: lesson("Decimal D", order: 2, sortIndex: 3)
        )
        try context.save()
        return fixture
    }

    @Test("plan-next, Unlock and the meeting's Complete read the same next lesson")
    func planNextAgrees() throws {
        let fixture = try makeFixture()
        let next = PlanNextLessonService.findNextLesson(after: fixture.first, in: fixture.shuffled)
        #expect(next?.id == fixture.zebra.id)
        let afterZebra = PlanNextLessonService.findNextLesson(after: fixture.zebra, in: fixture.shuffled)
        #expect(afterZebra?.id == fixture.apple.id)
        let before = BlockingAlgorithmEngine.findPrecedingLesson(currentLesson: fixture.last, lessons: fixture.shuffled)
        #expect(before?.id == fixture.apple.id)
    }

    @Test("the ready queue, Groups and the sequence ladder read the same next lesson")
    func readyQueueAndGroupsAgree() throws {
        let fixture = try makeFixture()
        let firstID = try #require(fixture.first.id)
        let zebraID = try #require(fixture.zebra.id)
        let next = BlockingAlgorithmEngine.buildNextLessonCache(fixture.shuffled)
        #expect(next[firstID]?.id == fixture.zebra.id)
        #expect(next[zebraID]?.id == fixture.apple.id)
        let preceding = BlockingAlgorithmEngine.buildPrecedingLessonCache(fixture.shuffled)
        #expect(preceding[try #require(fixture.last.id)]?.id == fixture.apple.id)

        let order = LessonSequenceOrder(lessons: fixture.shuffled)
        #expect(order.position(of: firstID.uuidString)?.nextLessonID == zebraID.uuidString)
        #expect(order.lessonIDs(area: "Math", sequence: "Decimal") == fixture.expected.compactMap(\.id?.uuidString))
    }

    @Test("the meeting's Ready for Next names the same next lesson")
    func meetingsAgree() throws {
        let fixture = try makeFixture()
        let names = MeetingDraftModel.nextLessonNames(in: fixture.context)
        #expect(names[try #require(fixture.first.id)] == "Zebra step")
        #expect(names[try #require(fixture.zebra.id)] == "Apple step")
        #expect(names[try #require(fixture.apple.id)] == "Decimal D")
        #expect(names[try #require(fixture.last.id)] == nil)
    }

    @Test("Claude's curriculum tools and the Lessons screens list the sub-area in the same order")
    func listingsAgree() throws {
        let fixture = try makeFixture()
        let expected = fixture.expected.map(\.id)
        let claude = MCPNotebookTools.lessonsInSequence("Decimal", area: "Math", from: fixture.shuffled)
        #expect(claude.map(\.id) == expected)
        #expect(LessonSequenceOrdering.sorted(fixture.shuffled).map(\.id) == expected)
    }

    @Test("a tied sub-area is renumbered once, in the shared order, and a second pass changes nothing")
    func tiesAreRenumberedOnce() throws {
        let fixture = try makeFixture()
        let untied = CoreDataTestHelpers.seedLesson(
            in: fixture.context, name: "Untied", area: "Math", sequence: "Other"
        )
        untied.orderInSequence = 5
        #expect(LessonOrder.renumberTies(in: fixture.shuffled + [untied]) == 2)
        #expect(fixture.expected.map(\.orderInSequence) == [0, 1, 2, 3])
        #expect(untied.orderInSequence == 5)
        #expect(LessonOrder.renumberTies(in: fixture.shuffled + [untied]) == 0)
        #expect(LessonOrder.next(after: fixture.zebra, in: fixture.shuffled)?.id == fixture.apple.id)
        #expect(LessonOrder.previous(before: fixture.zebra, in: fixture.shuffled)?.id == fixture.first.id)
        #expect(LessonOrder.next(after: fixture.last, in: fixture.shuffled) == nil)
    }

    @Test("the Class Grid orders two lessons tied on everything but their id one way")
    func classGridBreaksAFullTie() {
        func ref(_ id: UUID) -> CurriculumLessonRef {
            CurriculumLessonRef(
                id: id, name: "Same", area: "Math", sequence: "Decimal", section: "",
                orderInSequence: 1, sortIndex: 1, greatLessonRaw: nil, isStory: false, isKeyLesson: false
            )
        }
        let lower = ref(UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID())
        let higher = ref(UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID())
        #expect(ClassGridEngine.precedes(lower, higher))
        #expect(!ClassGridEngine.precedes(higher, lower))
    }
}
