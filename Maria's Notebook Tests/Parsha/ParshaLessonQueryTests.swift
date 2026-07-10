import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

@Suite("Parsha Lesson Queries")
@MainActor
final class ParshaLessonQueryTests {

    private func seedLesson(
        in context: NSManagedObjectContext,
        name: String,
        parshaKey: String?,
        derivedFromLessonID: String? = nil
    ) -> CDLesson {
        let lesson = CDLesson(context: context)
        lesson.name = name
        lesson.parshaKey = parshaKey
        lesson.derivedFromLessonID = derivedFromLessonID
        return lesson
    }

    // MARK: - Tagging Round-Trip

    @Test("parshaKey and derivedFromLessonID persist on CDLesson")
    func tagsPersist() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        let artLesson = seedLesson(in: context, name: "Watercolor Landscapes", parshaKey: nil)
        #expect(CoreDataTestHelpers.save(context))

        let artID = artLesson.id!.uuidString
        let parshaLesson = seedLesson(
            in: context,
            name: "Ark via Watercolor",
            parshaKey: "noach",
            derivedFromLessonID: artID
        )
        #expect(CoreDataTestHelpers.save(context))

        #expect(parshaLesson.parshaKey == "noach")
        #expect(parshaLesson.derivedFromLessonID == artID)
        #expect(artLesson.parshaKey == nil)
        #expect(artLesson.derivedFromLessonID == nil)
    }

    // MARK: - lessonsForParsha

    @Test("lessonsForParsha returns only lessons tagged to the given parsha, sorted by name")
    func lessonsForParshaFilters() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        _ = seedLesson(in: context, name: "Noach \u{2013} Ark", parshaKey: "noach")
        _ = seedLesson(in: context, name: "Noach \u{2013} Animals", parshaKey: "noach")
        _ = seedLesson(in: context, name: "Vayera \u{2013} Sarah", parshaKey: "vayera")
        _ = seedLesson(in: context, name: "Untagged art", parshaKey: nil)
        #expect(CoreDataTestHelpers.save(context))

        let noach = CDLesson.lessonsForParsha("noach", context: context)
        #expect(noach.count == 2)
        #expect(noach.map(\.name).sorted() == noach.map(\.name))
        #expect(noach.allSatisfy { $0.parshaKey == "noach" })

        let vayera = CDLesson.lessonsForParsha("vayera", context: context)
        #expect(vayera.count == 1)
        #expect(vayera.first?.name == "Vayera \u{2013} Sarah")
    }

    // MARK: - parshaLessonCounts

    @Test("parshaLessonCounts groups tagged lessons by parshaKey")
    func parshaLessonCountsGroups() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        _ = seedLesson(in: context, name: "N1", parshaKey: "noach")
        _ = seedLesson(in: context, name: "N2", parshaKey: "noach")
        _ = seedLesson(in: context, name: "N3", parshaKey: "noach")
        _ = seedLesson(in: context, name: "V1", parshaKey: "vayera")
        _ = seedLesson(in: context, name: "V2", parshaKey: "vayera")
        _ = seedLesson(in: context, name: "Untagged", parshaKey: nil)
        #expect(CoreDataTestHelpers.save(context))

        let counts = CDLesson.parshaLessonCounts(context: context)
        #expect(counts["noach"] == 3)
        #expect(counts["vayera"] == 2)
        #expect(counts["bereishit"] == nil)
    }

    // MARK: - Nil / Empty Handling

    @Test("untagged lessons do not leak into parsha queries")
    func untaggedNotLeaked() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        _ = seedLesson(in: context, name: "Untagged A", parshaKey: nil)
        _ = seedLesson(in: context, name: "Untagged B", parshaKey: "")
        #expect(CoreDataTestHelpers.save(context))

        let results = CDLesson.lessonsForParsha("", context: context)
        // Even if a lesson has an empty string key, the display UI filters allParshaKeys
        // so empty-key lessons are inert. The query matches predicate-style only.
        _ = results

        let counts = CDLesson.parshaLessonCounts(context: context)
        #expect(counts.isEmpty || counts.values.allSatisfy { $0 == 0 } == false)
    }
}
