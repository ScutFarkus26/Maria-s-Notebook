import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Pins the scoped student and track-step reads in `recordPresentation`
/// against the whole-table reads they replaced, and which children get
/// history rows.
@MainActor
struct PresentationRecordingScopedReadsTests {

    /// Until 2026-10-05 recording took every id that wasn't some student's
    /// `uuidString` off the assignment; now every id stays, and only the
    /// students found (ids compared trimmed and upper-cased) get history rows.
    @Test func unknownIDsStayAndOnlyLiveStudentsGetHistory() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "", sequence: "")
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        _ = CoreDataTestHelpers.seedStudent(in: context, firstName: "NotOnIt")
        let adaID = try #require(ada.id).uuidString
        let benID = try #require(ben.id).uuidString

        let la = CDLessonAssignment(context: context)
        la.id = UUID()
        la.lessonID = try #require(lesson.id).uuidString
        let named = [adaID, UUID().uuidString, "garbage", benID.lowercased(), adaID]
        la.studentIDs = named

        _ = try LifecycleService.recordPresentation(from: la, presentedAt: Date(), modelContext: context)
        #expect(la.studentIDs == named)

        let history = CDFetchRequest(CDLessonPresentation.self)
        history.predicate = NSPredicate(format: "presentationID == %@", try #require(la.id).uuidString)
        #expect(Set(context.safeFetch(history).map(\.studentID)) == [adaID, benID])
        #expect(context.safeFetch(history).count == 2)
    }

    @Test func noKnownStudentsKeepsTheListAndWritesNoHistory() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let la = CDLessonAssignment(context: context)
        la.lessonID = UUID().uuidString
        la.studentIDs = ["garbage", UUID().uuidString]
        let named = la.studentIDs
        _ = try LifecycleService.recordPresentation(from: la, presentedAt: Date(), modelContext: context)
        #expect(la.studentIDs == named)
        #expect(context.safeFetch(CDFetchRequest(CDLessonPresentation.self)).isEmpty)
    }
}
