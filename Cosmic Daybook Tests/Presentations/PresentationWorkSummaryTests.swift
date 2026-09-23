import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Pins that the once-per-load "Related Work" summary equals the per-body
/// reads it replaced (related work, completion stats, practice sessions, and
/// each row's student).
@MainActor
struct PresentationWorkSummaryTests {

    @Test func summaryMatchesPerBodyReads() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        let presentation = CDLessonAssignment(context: context)
        let other = CDLessonAssignment(context: context)
        let presentationID = try #require(presentation.id).uuidString

        var works: [CDWorkModel] = []
        for (index, student) in [ada, ben, ada].enumerated() {
            let work = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "W\(index)", studentID: try #require(student.id)
            )
            work.presentationID = presentationID
            work.createdAt = Date(timeIntervalSince1970: 1_780_000_000 + Double(index) * 60)
            work.status = index == 1 ? .mastered : .active
            works.append(work)
        }
        let orphan = CoreDataTestHelpers.seedWorkModel(in: context, title: "no student")
        orphan.presentationID = presentationID
        orphan.studentID = ""
        let unrelated = CoreDataTestHelpers.seedWorkModel(in: context, title: "other")
        unrelated.presentationID = try #require(other.id).uuidString

        for (index, work) in (works + [unrelated]).enumerated() {
            let session = CDPracticeSession(context: context)
            session.date = Date(timeIntervalSince1970: 1_781_000_000 + Double(index) * 3_600)
            session.workItemIDsArray = [try #require(work.id).uuidString]
        }
        try context.save()

        let summary = PresentationWorkSummary.load(for: presentation, context: context)

        let legacyWork = presentation.fetchRelatedWork(from: context)
        #expect(summary.workItems.map(\.objectID) == legacyWork.map(\.objectID))
        #expect(summary.workItems.count == 4)
        let legacyStats = presentation.workCompletionStats(from: context)
        #expect(summary.stats.completed == legacyStats.completed)
        #expect(summary.stats.total == legacyStats.total)
        #expect(summary.stats.completed == 1)
        let legacySessions = presentation.fetchRelatedPracticeSessions(from: context)
        #expect(summary.practiceSessions.map(\.objectID) == legacySessions.map(\.objectID))
        #expect(summary.practiceSessions.count == 3)
        for work in legacyWork {
            #expect(summary.student(for: work)?.objectID == work.fetchStudent(from: context)?.objectID)
        }
        #expect(summary.student(for: works[0])?.objectID == ada.objectID)
        #expect(summary.student(for: orphan) == nil)
    }
}
