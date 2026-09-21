import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// An observation links to a presentation as a whole; which child it is about
// is the note's scope. A note saved on a presentation with no child selected
// used to get the whole-class scope, so one girl's observation read as an
// observation of every child on the roster.

@Suite("Presentation Observation Scope")
@MainActor
struct PresentationObservationScopeTests {

    private func seedPresentation(
        of lesson: CDLesson, to students: [CDStudent], in context: NSManagedObjectContext
    ) throws -> CDLessonAssignment {
        let presentation = CDLessonAssignment(context: context)
        presentation.lessonID = try #require(lesson.id).uuidString
        presentation.lessonTitleSnapshot = lesson.name
        presentation.studentIDs = try students.map { try #require($0.id).uuidString }
        presentation.stateRaw = LessonAssignmentState.presented.rawValue
        presentation.presentedAt = Date()
        return presentation
    }

    @discardableResult
    private func seedNote(
        _ body: String, scope: NoteScope, on presentation: CDLessonAssignment, in context: NSManagedObjectContext
    ) -> CDNote {
        let note = CDNote(context: context)
        note.body = body
        note.scope = scope
        note.lessonAssignment = presentation
        note.syncStudentLinks(in: context)
        return note
    }

    @Test("An empty selection on a presentation means its roster, never the whole class")
    func selectionFallsBackToRoster() {
        let etty: UUID = UUID()
        let ora: UUID = UUID()
        let pair: Set<UUID>? = NoteScope.forSelection([], fallback: [etty, ora]).studentIDs.map { Set($0) }
        #expect(pair == Set([etty, ora]))
        let single: NoteScope = NoteScope.forSelection([], fallback: [etty])
        #expect(single == .student(etty))
        let chosen: NoteScope = NoteScope.forSelection([ora], fallback: [etty, ora])
        #expect(chosen == .student(ora))
        let nothing: NoteScope = NoteScope.forSelection([], fallback: [])
        #expect(nothing == .all)
    }

    @Test("Launch repair narrows a whole-class presentation note to the children who received it")
    func repairNarrowsWholeClassNotes() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Second Polygon Presentation")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let tiffy = CoreDataTestHelpers.seedStudent(in: context, firstName: "Tiferet", lastName: "Pardo")
        CoreDataTestHelpers.save(context)
        let presentation = try seedPresentation(of: lesson, to: [etty, ora], in: context)
        let wholeClass = seedNote("Stayed with the nomenclature cards.", scope: .all, on: presentation, in: context)
        let standalone = CoreDataTestHelpers.seedNote(in: context, body: "Class meeting went long.")
        standalone.scope = .all
        CoreDataTestHelpers.save(context)

        #expect(DataCleanupService.repairPresentationNoteScopes(using: context) == 1)
        CoreDataTestHelpers.save(context)

        #expect(wholeClass.scope.applies(to: try #require(etty.id)))
        #expect(wholeClass.scope.applies(to: try #require(ora.id)))
        #expect(!wholeClass.scope.applies(to: try #require(tiffy.id)))
        #expect(standalone.scope == .all)
        #expect(DataCleanupService.repairPresentationNoteScopes(using: context) == 0)
    }

    @Test("Coverage is judged child by child on a group presentation")
    func coverageIsPerStudent() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Second Polygon Presentation")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        CoreDataTestHelpers.save(context)
        let presentation = try seedPresentation(of: lesson, to: [etty, ora], in: context)
        let ettyID = try #require(etty.id)
        seedNote("Named every polygon unprompted.", scope: .student(ettyID), on: presentation, in: context)
        CoreDataTestHelpers.save(context)

        #expect(PresentationObservationCoverageService.unobservedStudentIDs(on: presentation) == [try #require(ora.id)])

        let start = Date().addingTimeInterval(-7 * 86_400)
        let missingForOra = PresentationObservationCoverageService.missingObservationReferences(
            in: context, from: start, through: Date(), studentIDs: [try #require(ora.id)]
        )
        #expect(missingForOra.map(\.entityID) == [try #require(presentation.id)])
        let missingForEtty = PresentationObservationCoverageService.missingObservationReferences(
            in: context, from: start, through: Date(), studentIDs: [try #require(etty.id)]
        )
        #expect(missingForEtty.isEmpty)
    }

    @Test("MCP history counts a note for the child it is about and says when it is shared")
    func historyAndCoverageOverMCP() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Second Polygon Presentation")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        CoreDataTestHelpers.save(context)
        let presentation = try seedPresentation(of: lesson, to: [etty, ora], in: context)
        let ettyID = try #require(etty.id)
        seedNote("Named every polygon unprompted.", scope: .student(ettyID), on: presentation, in: context)
        CoreDataTestHelpers.save(context)
        let tools = MCPNotebookTools.makeTools(context: { context })
        let history = try #require(tools.first { $0.name == "student_presentation_history" })
        let missing = try #require(tools.first { $0.name == "presentations_missing_observations" })

        let ettys = try await history.handler(["student_name": .string("Etty Dechter")])
        #expect(ettys.contains("1 linked observation(s))"))
        let oras = try await history.handler(["student_name": .string("Ora")])
        #expect(oras.contains("no linked observation"))

        let uncovered = try await missing.handler(["days_back": .int(7)])
        #expect(uncovered.contains("no observation yet for Ora Pardo"))
        #expect(!uncovered.contains("Etty Dechter"))

        // A group note names the other children it is shared with.
        seedNote("Worked as a pair.", scope: .students([try #require(etty.id), try #require(ora.id)]),
                 on: presentation, in: context)
        CoreDataTestHelpers.save(context)
        let shared = try await history.handler(["student_name": .string("Ora")])
        #expect(shared.contains("1 linked observation(s), shared with Etty Dechter"))
    }
}
