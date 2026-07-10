import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

/// Tests for `ReportGeneratorService.fetchReportNotes` — the filter that
/// decides which observation notes appear in a student's parent-facing
/// report. A scoping bug here leaks one student's notes into another
/// student's report, so the isolation rules are pinned down explicitly.
@Suite("Report Note Scoping")
@MainActor
final class ReportNoteScopingTests {

    @discardableResult
    private func makeFlaggedNote(
        in context: NSManagedObjectContext,
        body: String,
        createdAt: Date = Date(),
        scope: NoteScope? = nil
    ) -> CDNote {
        let note = CDNote(context: context)
        note.body = body
        note.includeInReport = true
        note.createdAt = createdAt
        if let scope {
            note.scope = scope
        }
        return note
    }

    private func wideRange(around date: Date = Date()) -> ClosedRange<Date> {
        date.addingTimeInterval(-86_400)...date.addingTimeInterval(86_400)
    }

    @Test("Per-student notes never leak into another student's report")
    func scopeIsolation() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let alice = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Alice", lastName: "A")
        let ben = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Ben", lastName: "B")
        let aliceID = try #require(alice.id)
        let benID = try #require(ben.id)

        makeFlaggedNote(in: ctx, body: "Alice only", scope: .student(aliceID))
        makeFlaggedNote(in: ctx, body: "Ben only", scope: .student(benID))
        makeFlaggedNote(in: ctx, body: "Both", scope: .students([aliceID, benID]))
        makeFlaggedNote(in: ctx, body: "Whole class", scope: .all)
        #expect(CoreDataTestHelpers.save(ctx))

        let service = ReportGeneratorService()
        let range = wideRange()

        let aliceNotes = service.fetchReportNotes(for: alice, dateRange: range, context: ctx)
        #expect(aliceNotes.map(\.body).sorted() == ["Alice only", "Both", "Whole class"])

        let benNotes = service.fetchReportNotes(for: ben, dateRange: range, context: ctx)
        #expect(benNotes.map(\.body).sorted() == ["Ben only", "Both", "Whole class"])
        #expect(!benNotes.map(\.body).contains("Alice only"))
    }

    @Test("Multi-student scope excludes students outside the list")
    func multiStudentScopeExcludesOthers() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let alice = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Alice", lastName: "A")
        let ben = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Ben", lastName: "B")
        let benID = try #require(ben.id)

        makeFlaggedNote(in: ctx, body: "Ben's group", scope: .students([benID]))
        #expect(CoreDataTestHelpers.save(ctx))

        let service = ReportGeneratorService()
        let aliceNotes = service.fetchReportNotes(for: alice, dateRange: wideRange(), context: ctx)
        #expect(aliceNotes.isEmpty)
    }

    @Test("Only notes flagged for reports are returned")
    func unflaggedNotesExcluded() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let alice = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Alice", lastName: "A")
        let aliceID = try #require(alice.id)

        let unflagged = CDNote(context: ctx)
        unflagged.body = "Private working note"
        unflagged.includeInReport = false
        unflagged.scope = .student(aliceID)
        #expect(CoreDataTestHelpers.save(ctx))

        let service = ReportGeneratorService()
        let notes = service.fetchReportNotes(for: alice, dateRange: wideRange(), context: ctx)
        #expect(notes.isEmpty)
    }

    @Test("Date range bounds are inclusive at both ends")
    func dateRangeBounds() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let alice = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Alice", lastName: "A")
        let aliceID = try #require(alice.id)

        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 2_000_000)
        makeFlaggedNote(in: ctx, body: "At start", createdAt: start, scope: .student(aliceID))
        makeFlaggedNote(in: ctx, body: "At end", createdAt: end, scope: .student(aliceID))
        makeFlaggedNote(
            in: ctx,
            body: "Before",
            createdAt: start.addingTimeInterval(-1),
            scope: .student(aliceID)
        )
        makeFlaggedNote(
            in: ctx,
            body: "After",
            createdAt: end.addingTimeInterval(1),
            scope: .student(aliceID)
        )
        #expect(CoreDataTestHelpers.save(ctx))

        let service = ReportGeneratorService()
        let notes = service.fetchReportNotes(for: alice, dateRange: start...end, context: ctx)
        #expect(notes.map(\.body).sorted() == ["At end", "At start"])
    }

    @Test("Notes that never had a scope set behave as whole-class notes")
    func missingScopeFallsBackToAll() throws {
        // CDNote.scope decodes a nil scopeBlob as .all — legacy notes created
        // before scoping existed appear in every student's report. This test
        // documents that fallback so a change to it is a deliberate decision.
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let alice = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Alice", lastName: "A")

        makeFlaggedNote(in: ctx, body: "Unscoped legacy note", scope: nil)
        #expect(CoreDataTestHelpers.save(ctx))

        let service = ReportGeneratorService()
        let notes = service.fetchReportNotes(for: alice, dateRange: wideRange(), context: ctx)
        #expect(notes.map(\.body) == ["Unscoped legacy note"])
    }
}
