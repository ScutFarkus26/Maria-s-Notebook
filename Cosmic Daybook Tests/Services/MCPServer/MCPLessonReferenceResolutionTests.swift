import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `resolveLessonReference` used to read every lesson row for every reference,
/// even an id, and `record_presentation` / `mark_mastered` did that once per
/// batch item. An id is a point read now and a call reads the table at most
/// once; every reference must resolve — or fail, word for word — as before.
@Suite("MCP lesson reference resolution")
@MainActor
struct MCPLessonReferenceResolutionTests {

    /// The resolver's old body, kept verbatim as the reference.
    private func legacyResolve(_ reference: String, in modelContext: NSManagedObjectContext) throws -> CDLesson {
        let lessons = modelContext.safeFetch(CDFetchRequest(CDLesson.self))

        if let id = UUID(uuidString: reference) {
            guard let lesson = lessons.first(where: { $0.id == id }) else {
                throw MCPToolError("No lesson with id \(reference) was found.")
            }
            return lesson
        }

        let token = reference.folded()
        guard !token.isEmpty else {
            throw MCPToolError("A lesson name or id is required.")
        }

        for candidates in [lessons.filter { $0.name.folded() == token },
                           lessons.filter { $0.name.folded().contains(token) }] {
            if candidates.count == 1, let lesson = candidates.first { return lesson }
            if candidates.count > 1 {
                let list = candidates.prefix(8).map { MCPNotebookTools.describeLesson($0) }.joined(separator: "\n")
                throw MCPToolError(
                    "More than one lesson matches \"\(reference)\". Ask which one the guide means:\n\(list)"
                )
            }
        }

        throw MCPToolError(
            "No lesson matching \"\(reference)\" is in the curriculum. "
                + "Use find_lessons to search, and ask the guide if nothing fits."
        )
    }

    private enum Outcome: Equatable {
        case lesson(ObjectIdentifier)
        case refused(String)
    }

    private func outcome(_ resolve: () throws -> CDLesson) -> Outcome {
        do {
            return .lesson(ObjectIdentifier(try resolve()))
        } catch let error as MCPToolError {
            return .refused(error.message)
        } catch {
            return .refused("unexpected: \(error)")
        }
    }

    /// A curriculum with exact, folded, partial and ambiguous names, ten
    /// lessons sharing a word (past the eight an ambiguity lists), and one
    /// lesson inserted but not yet saved.
    private func seedCurriculum(in context: NSManagedObjectContext) throws -> [CDLesson] {
        var lessons: [CDLesson] = []
        func add(_ name: String, _ area: String, _ sequence: String) {
            lessons.append(CoreDataTestHelpers.seedLesson(in: context, name: name, area: area, sequence: sequence))
        }
        add("Racks and Tubes", "Math", "Division")
        add("Checkerboard", "Math", "Multiplication")
        add("Écoute du silence", "Practical Life", "Grace")
        add("Golden Beads", "Math", "Decimal System")
        add("Golden Beads", "Math", "Numeration")
        add("Bead Frame", "Math", "Multiplication")
        for index in 1...10 {
            add("Timeline \(index)", "History", "Timelines")
        }
        #expect(CoreDataTestHelpers.save(context))
        add("Stamp Game", "Math", "Operations")
        return lessons
    }

    private func references(for lessons: [CDLesson]) throws -> [String] {
        let checkerboard = try #require(lessons[1].id)
        let unsaved = try #require(lessons.last?.id)
        return [
            checkerboard.uuidString, checkerboard.uuidString.lowercased(), unsaved.uuidString,
            UUID().uuidString,
            "Racks and Tubes", "racks and tubes", "ecoute du silence", "checker", "Stamp",
            "Golden Beads", "golden", "bead", "timeline", "Timeline 1",
            "Photosynthesis", "", "   "
        ]
    }

    @Test("Every reference resolves, or is refused word for word, as before")
    func resolutionMatchesTheOldReads() throws {
        for context in [try CoreDataTestHelpers.makeContext(), try CoreDataTestHelpers.makeSplitStoreContext()] {
            let lessons = try seedCurriculum(in: context)
            for reference in try references(for: lessons) {
                let old = outcome { try legacyResolve(reference, in: context) }
                let new = outcome { try MCPNotebookTools.resolveLessonReference(reference, in: context) }
                #expect(new == old, "\(reference)")
                let batch = MCPNotebookTools.LessonReferences(in: context)
                #expect(outcome { try batch.resolve(reference) } == old, "\(reference)")
                let preloaded = MCPNotebookTools.LessonReferences(
                    in: context, table: context.safeFetch(CDFetchRequest(CDLesson.self))
                )
                #expect(outcome { try preloaded.resolve(reference) } == old, "\(reference)")
            }
            // Not vacuous: each kind of answer is in there.
            #expect(outcome { try legacyResolve("checker", in: context) } == .lesson(ObjectIdentifier(lessons[1])))
            #expect(outcome { try legacyResolve("Stamp", in: context) } == .lesson(ObjectIdentifier(lessons[16])))
            guard case .refused(let ambiguity) = outcome({ try legacyResolve("timeline", in: context) }) else {
                Issue.record("expected an ambiguity")
                continue
            }
            #expect(ambiguity.components(separatedBy: "\n").count == 9)
        }
    }

    @Test("A call reads the lesson table at most once, and never for an id")
    func tableReadAtMostOncePerCall() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lessons = try seedCurriculum(in: context)

        let byID = MCPNotebookTools.LessonReferences(in: context)
        for lesson in lessons.prefix(5) {
            #expect(try byID.resolve(try #require(lesson.id).uuidString) === lesson)
        }
        #expect(byID.tableReads == 0)

        let byName = MCPNotebookTools.LessonReferences(in: context)
        for name in ["Racks and Tubes", "Checkerboard", "Bead Frame", "Stamp Game", "Timeline 3"] {
            _ = try byName.resolve(name)
        }
        #expect(byName.tableReads == 1)

        let mixed = MCPNotebookTools.LessonReferences(in: context)
        _ = try mixed.resolve(try #require(lessons[0].id).uuidString)
        _ = try mixed.resolve("Checkerboard")
        #expect(try mixed.resolve(try #require(lessons[5].id).uuidString) === lessons[5])
        _ = try mixed.resolve("Timeline 7")
        #expect(mixed.tableReads == 1)

        let handed = MCPNotebookTools.LessonReferences(
            in: context, table: context.safeFetch(CDFetchRequest(CDLesson.self))
        )
        _ = try handed.resolve("Checkerboard")
        #expect(handed.tableReads == 0)
    }
}
