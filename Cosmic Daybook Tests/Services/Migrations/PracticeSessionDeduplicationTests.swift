import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Practice sessions had no deduplication, and the live notebook carried three
/// copies of the same session (same id), which `practice_sessions` over MCP
/// printed three times. A session owns its notes through a Cascade rule, so the
/// merge must move notes onto the survivor before the copy is deleted.
@Suite("Practice session deduplication")
@MainActor
struct PracticeSessionDeduplicationTests {

    @Test("Copies of one session collapse to one, keeping every copy's notes")
    func copiesCollapseKeepingNotes() throws {
        let ctx = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let sessionID = UUID()
        let copies: [CDPracticeSession] = (0..<3).map { _ in
            let session = CDPracticeSession(context: ctx)
            session.id = sessionID
            session.date = Date(timeIntervalSince1970: 1_774_000_000)
            session.sharedNotes = "They did great together."
            return session
        }
        for (index, copy) in copies.enumerated() {
            let note = CDNote(context: ctx)
            note.id = UUID()
            note.body = "Note \(index)"
            note.practiceSession = copy
        }
        let other = CDPracticeSession(context: ctx)
        other.id = UUID()
        #expect(CoreDataTestHelpers.save(ctx))

        let results = DataCleanupService.deduplicateAllModels(using: ctx)
        #expect(results["PracticeSession"] == 2)

        let sessions = ctx.safeFetch(CDFetchRequest(CDPracticeSession.self))
        #expect(sessions.count == 2)
        let survivor = try #require(sessions.first { $0.id == sessionID })
        #expect(survivor.sharedNotes == "They did great together.")

        let notes = ctx.safeFetch(CDFetchRequest(CDNote.self))
        #expect(notes.count == 3)
        #expect(notes.allSatisfy { $0.practiceSession == survivor })
    }
}
