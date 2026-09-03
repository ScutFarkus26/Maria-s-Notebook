import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

/// `BlockingAlgorithmEngine.buildPrecedingLessonCache` replaces a loop that
/// called `findPrecedingLesson` once per lesson (a filter and a sort over the
/// whole library each time). These tests pin the two to the same answer across
/// the cases the per-lesson search handled: case-insensitive and whitespace-
/// tolerant area/sequence matching, curriculum order rather than fetch order,
/// blank sections, and first-in-sequence lessons.
@Suite("Preceding Lesson Cache")
@MainActor
struct PrecedingLessonCacheTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    @discardableResult
    private func lesson(
        _ name: String,
        area: String,
        sequence: String,
        order: Int64,
        in context: NSManagedObjectContext
    ) -> CDLesson {
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: area, sequence: sequence)
        lesson.id = UUID()
        lesson.orderInSequence = order
        return lesson
    }

    @Test("Cache matches the per-lesson search for every lesson")
    func cacheMatchesPerLessonSearch() throws {
        let context = try makeContext()
        // Deliberately out of curriculum order, with case and whitespace
        // differences that the per-lesson search tolerated.
        let lessons = [
            lesson("Third", area: "Math", sequence: "Counting", order: 30, in: context),
            lesson("First", area: "math ", sequence: " counting", order: 10, in: context),
            lesson("Second", area: "MATH", sequence: "Counting", order: 20, in: context),
            lesson("Other First", area: "Language", sequence: "Grammar", order: 1, in: context),
            lesson("Other Second", area: "Language", sequence: "grammar", order: 2, in: context),
            lesson("Blank Area", area: "", sequence: "Counting", order: 5, in: context),
            lesson("Blank Sequence", area: "Math", sequence: "  ", order: 6, in: context),
            lesson("Lonely", area: "Geometry", sequence: "Solids", order: 1, in: context)
        ]

        let cache = BlockingAlgorithmEngine.buildPrecedingLessonCache(lessons)

        for current in lessons {
            let expected = BlockingAlgorithmEngine.findPrecedingLesson(currentLesson: current, lessons: lessons)
            let actual = current.id.flatMap { cache[$0] }
            #expect(actual === expected, "Mismatch for \(current.name)")
        }
    }

    @Test("Cache resolves the sequence in curriculum order")
    func cacheFollowsCurriculumOrder() throws {
        let context = try makeContext()
        let third = lesson("Third", area: "Math", sequence: "Counting", order: 30, in: context)
        let first = lesson("First", area: "Math", sequence: "Counting", order: 10, in: context)
        let second = lesson("Second", area: "Math", sequence: "Counting", order: 20, in: context)

        let cache = BlockingAlgorithmEngine.buildPrecedingLessonCache([third, first, second])

        #expect(cache[try #require(first.id)] == nil)
        #expect(cache[try #require(second.id)] === first)
        #expect(cache[try #require(third.id)] === second)
    }

    @Test("Lessons with a blank area or sequence have no preceding lesson")
    func blankSectionsAreSkipped() throws {
        let context = try makeContext()
        let anchored = lesson("Anchored", area: "Math", sequence: "Counting", order: 1, in: context)
        let blankArea = lesson("Blank Area", area: "", sequence: "Counting", order: 2, in: context)
        let blankSequence = lesson("Blank Sequence", area: "Math", sequence: "", order: 3, in: context)

        let cache = BlockingAlgorithmEngine.buildPrecedingLessonCache([anchored, blankArea, blankSequence])

        #expect(cache.isEmpty)
    }
}
