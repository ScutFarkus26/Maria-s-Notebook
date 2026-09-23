import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Pins the scoped student and track-step reads in `recordPresentation`
/// against the whole-table reads they replaced.
@MainActor
struct PresentationRecordingScopedReadsTests {

    @Test func orphanCleaningKeepsExactlyTheLiveStudents() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "", sequence: "")
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        _ = CoreDataTestHelpers.seedStudent(in: context, firstName: "NotOnIt")
        let adaID = try #require(ada.id).uuidString
        let benID = try #require(ben.id).uuidString

        let la = CDLessonAssignment(context: context)
        la.lessonID = try #require(lesson.id).uuidString
        let named = [adaID, UUID().uuidString, "garbage", benID.lowercased(), adaID]
        la.studentIDs = named

        // The pre-2026-09-22 rule: keep ids that are some student's uuidString.
        let everyone = Set(try context.fetch(CDFetchRequest(CDStudent.self)).compactMap { $0.id?.uuidString })
        let expected = named.filter { everyone.contains($0) }

        _ = try LifecycleService.recordPresentation(from: la, presentedAt: Date(), modelContext: context)
        #expect(la.studentIDs == expected)
        #expect(la.studentIDs == [adaID, adaID])
    }

    @Test func noValidStudentsClearsTheList() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let la = CDLessonAssignment(context: context)
        la.lessonID = UUID().uuidString
        la.studentIDs = ["garbage", UUID().uuidString]
        _ = try LifecycleService.recordPresentation(from: la, presentedAt: Date(), modelContext: context)
        #expect(la.studentIDs == [])
    }

    @Test func trackStepIsThisTracksStepForTheLesson() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = CoreDataTestHelpers.seedLesson(in: context, name: "Counting 1", area: "Math", sequence: "Counting")
        first.orderInSequence = 0
        let second = CoreDataTestHelpers.seedLesson(in: context, name: "Counting 2", area: "Math", sequence: "Counting")
        second.orderInSequence = 1
        // A decoy track that also has a step for the same lesson.
        let decoy = CDTrackEntity(context: context)
        decoy.title = "Elsewhere — Decoy"
        let decoyStep = CDTrackStep(context: context)
        decoyStep.lessonTemplateID = second.id
        decoyStep.track = decoy
        let student = CoreDataTestHelpers.seedStudent(in: context)
        try context.save()

        let la = CDLessonAssignment(context: context)
        la.lessonID = try #require(second.id).uuidString
        la.studentIDs = [try #require(student.id).uuidString]
        _ = try LifecycleService.recordPresentation(from: la, presentedAt: Date(), modelContext: context)

        let trackID = try #require(la.trackID)
        let legacy = context.safeFetch(CDFetchRequest(CDTrackStep.self)).first {
            $0.track?.id?.uuidString == trackID && $0.lessonTemplateID == second.id
        }
        let expectedStep = try #require(legacy)
        #expect(la.trackStepID == expectedStep.id?.uuidString)
        #expect(la.trackStepID != decoyStep.id?.uuidString)
    }
}
